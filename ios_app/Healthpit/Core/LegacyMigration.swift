//
//  LegacyMigration.swift
//  HealthPitCore
//
//  HEALTHPIT-CONVERT-2026-08 – VORUEBERGEHEND.
//
//  Uebernimmt den vorhandenen Bestand in das neue Modell.
//
//  Diese Datei ist auf Abriss gebaut. Sie wird gebraucht, solange es
//  Installationen gibt, auf denen die Fassung vor dem Datenmodell lief und
//  deren Werte nur in den alten Zwischenspeichern stehen. Ist der letzte
//  Umstieg durch, faellt sie ersatzlos weg – wie sie zu entfernen ist, steht
//  in UMWANDLER-ENTFERNEN.md.
//
//  Grundsaetze:
//  * Nichts wird geloescht. Die alten Dateien und der alte Cache bleiben
//    liegen, bis die neue Struktur im Betrieb bestaetigt ist.
//  * Nichts wird weggeworfen. Was sich nicht eindeutig zuordnen laesst, wird
//    trotzdem gespeichert und als `UNRESOLVED_METRIC` markiert.
//  * Mehrfaches Ausfuehren aendert nichts. Workouts behalten ihre bisherige
//    UUID, Messwerte laufen ueber dieselbe Deduplizierung wie ein Import.
//

import Foundation

struct LegacyMigrationReport: Sendable, Equatable {
    var workouts = 0
    var workoutObservations = 0
    var metricObservations = 0
    var sleepObservations = 0
    var unresolvedObservations = 0
    /// Cache-Schluessel, die die Migration nicht kennt. Sie bleiben
    /// unangetastet – hier steht nur, dass es sie gab.
    var untouchedCacheKeys: [String] = []
    var alreadyMigrated = false
}

/// Was an Altbestand gefunden wurde – ohne etwas zu veraendern.
///
/// Grundlage fuer den Transferdialog beim Start: Erst zeigen, was da ist,
/// dann fragen, dann uebernehmen.
struct LegacyInventory: Sendable, Equatable {
    var localWorkouts = 0
    var appleHealthWorkouts = 0
    var dashboardValues = 0
    var sleepSessions = 0
    var sleepSegments = 0
    /// Cache-Schluessel, die die Uebernahme nicht auswertet (Abgeleitetes).
    var untouchedCacheKeys: [String] = []
    /// Wurde die Uebernahme schon einmal vollstaendig ausgefuehrt?
    var alreadyMigrated = false

    /// Werte, die uebernommen wuerden – Workouts zaehlen nicht mit, die
    /// stehen daneben.
    var valueCount: Int { dashboardValues + sleepSessions * 7 + sleepSegments }
    var workoutCount: Int { localWorkouts + appleHealthWorkouts }
    var hasAnything: Bool { workoutCount > 0 || dashboardValues > 0 || sleepSessions > 0 }
}

struct LegacyMigration: Sendable {
    static let flagKey = "legacy_data_migration"
    /// Version des Migrationslaufs. Wird sie erhoeht, laeuft die Migration
    /// erneut – die Deduplizierung faengt Doppeleintraege ab.
    static let flagValue = "v1"

    let store: HealthPitStore
    /// `Application Support/LocalWorkouts/workouts.json`.
    var localWorkoutsURL: URL?
    var userID: String = HealthPitUser.local

    init(store: HealthPitStore,
         localWorkoutsURL: URL? = LegacyMigration.defaultLocalWorkoutsURL(),
         userID: String = HealthPitUser.local) {
        self.store = store
        self.localWorkoutsURL = localWorkoutsURL
        self.userID = userID
    }

    static func defaultLocalWorkoutsURL(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appending(path: "LocalWorkouts", directoryHint: .isDirectory)
            .appending(path: "workouts.json")
    }

    /// Sieht nach, was an Altbestand vorhanden ist. Schreibt nichts.
    func inspect() async throws -> LegacyInventory {
        var inventory = LegacyInventory()
        inventory.alreadyMigrated = try await store.migrationFlag(Self.flagKey) == Self.flagValue

        let decoder = LegacyDecoder.make()
        if let localWorkoutsURL,
           let data = try? Data(contentsOf: localWorkoutsURL),
           let workouts = try? decoder.decode([LegacyLocalWorkout].self, from: data) {
            inventory.localWorkouts = workouts.count
        }

        var seenWorkoutUUIDs = Set<UUID>()
        var seenSleepNights = Set<String>()
        for key in try await store.legacyCacheKeys() {
            guard let data = try await store.legacyCacheEntry(key: key) else {
                inventory.untouchedCacheKeys.append(key)
                continue
            }
            if key == "dashboard.metric.values",
               let entries = try? decoder.decode([LegacyDashboardMetricEntry].self, from: data) {
                inventory.dashboardValues += entries.count
            } else if key.hasPrefix("sleep_sessions."),
                      let sessions = try? decoder.decode([LegacySleepSession].self, from: data) {
                // Dieselbe Nacht steht in mehreren Zeitraum-Caches. Fuer die
                // Anzeige zaehlt sie einmal.
                for session in sessions where seenSleepNights.insert(
                    "\(session.start.timeIntervalSince1970)-\(session.end.timeIntervalSince1970)").inserted {
                    inventory.sleepSessions += 1
                    inventory.sleepSegments += session.segments.count
                }
            } else if key.hasPrefix("health_workouts."),
                      let summaries = try? decoder.decode([LegacyWorkoutSummary].self, from: data) {
                for summary in summaries where seenWorkoutUUIDs.insert(summary.uuid).inserted {
                    inventory.appleHealthWorkouts += 1
                }
            } else {
                inventory.untouchedCacheKeys.append(key)
            }
        }
        return inventory
    }

    @discardableResult
    func run(force: Bool = false) async throws -> LegacyMigrationReport {
        if !force, try await store.migrationFlag(Self.flagKey) == Self.flagValue {
            var report = LegacyMigrationReport()
            report.alreadyMigrated = true
            return report
        }

        // Apple Health ist der Anbieter, aus dem der Altbestand stammt – die
        // Mappings muessen also stehen, bevor irgendetwas importiert wird.
        for mapping in AppleHealthMapping.providerMappings() {
            try await store.upsertMapping(mapping)
        }

        var report = LegacyMigrationReport()
        try await migrateLocalWorkouts(into: &report)
        try await migrateCacheEntries(into: &report)
        report.unresolvedObservations = try await store.observations(reviewState: .unresolvedMetric).count

        try await store.setMigrationFlag(Self.flagKey, value: Self.flagValue)
        return report
    }

    // MARK: - Lokale Workouts

    private func migrateLocalWorkouts(into report: inout LegacyMigrationReport) async throws {
        guard let localWorkoutsURL,
              let data = try? Data(contentsOf: localWorkoutsURL) else { return }
        let decoder = LegacyDecoder.make()
        guard let workouts = try? decoder.decode([LegacyLocalWorkout].self, from: data) else { return }

        for legacy in workouts {
            let origin = Self.provider(forLegacySource: legacy.source)
            // Die bisherige UUID wird zur Workout-ID. Damit bleiben
            // Verweise aus Bridge-Uploads und Sicherungsdateien gueltig.
            let workoutID = WorkoutID(uuid: legacy.id)
            let existing = try await store.workout(workoutID)

            let workout = StoredWorkout(workoutID: workoutID,
                                        userID: userID,
                                        sportType: Self.sportCode(legacy.sport),
                                        title: legacy.title,
                                        notes: legacy.notes,
                                        startTime: legacy.start,
                                        endTime: legacy.end,
                                        timezone: existing?.timezone ?? TimeZone.current.identifier,
                                        originProvider: origin,
                                        ingestProvider: origin == .appleHealth ? .appleHealth : .healthPit,
                                        sourceRecordID: origin == .appleHealth ? legacy.id.uuidString : nil,
                                        version: existing?.version ?? 1,
                                        createdAt: existing?.createdAt ?? legacy.start,
                                        metadata: [
                                            "legacy_source": legacy.source,
                                            "legacy_sport": legacy.sport
                                        ],
                                        // Der Originaldatensatz bleibt erhalten:
                                        // Felder, die das neue Modell heute nicht
                                        // abbildet, sind damit nicht verloren.
                                        rawPayload: Self.jsonString(legacy))

            if existing == nil {
                try await store.insert(workout)
                report.workouts += 1
                try await store.append(SyncEvent(entityType: .workout,
                                                 entityID: workoutID.rawValue,
                                                 provider: origin,
                                                 direction: .importing,
                                                 action: .create,
                                                 metadata: ["source": "legacy_migration"]))
            }

            if origin == .appleHealth {
                // Die alte ID ist zugleich die HealthKit-UUID: als externe
                // Referenz festhalten, sonst legt der naechste Apple-Import
                // dasselbe Workout ein zweites Mal an.
                try await store.upsert(ExternalReference(userID: userID,
                                                         entityType: .workout,
                                                         entityID: workoutID.rawValue,
                                                         provider: .appleHealth,
                                                         externalRecordID: legacy.id.uuidString,
                                                         importedAt: Date(),
                                                         metadata: ["source": "legacy_migration"]))
            }

            report.workoutObservations += try await migrateWorkoutValues(legacy,
                                                                         workoutID: workoutID,
                                                                         origin: origin)
        }
    }

    private func migrateWorkoutValues(_ legacy: LegacyLocalWorkout,
                                      workoutID: WorkoutID,
                                      origin: ProviderCode) async throws -> Int {
        var incoming: [IncomingObservation] = []

        func add(_ metric: MetricID,
                 value: Double?,
                 unit: UnitCode,
                 aggregation: Aggregation = .sum,
                 sourceMetric: String) {
            guard let value, value > 0 else { return }
            incoming.append(IncomingObservation(sourceMetric: sourceMetric,
                                                metricID: metric,
                                                value: value,
                                                unit: unit,
                                                startTime: legacy.start,
                                                endTime: legacy.end,
                                                aggregation: aggregation,
                                                periodType: .workout,
                                                originProvider: origin,
                                                sourceAppID: legacy.source,
                                                workoutID: workoutID,
                                                metadata: ["source": "legacy_migration"]))
        }

        add("WRK_DURATION", value: legacy.end.timeIntervalSince(legacy.start),
            unit: .second, sourceMetric: "local_workout.duration")
        add("WRK_DISTANCE", value: legacy.distanceKm, unit: .kilometer,
            sourceMetric: "local_workout.distance_km")
        add("WRK_ENERGY", value: legacy.energyKcal, unit: .kilocalorie,
            sourceMetric: "local_workout.energy_kcal")
        add("HRT_RATE", value: legacy.averageHeartRate, unit: .beatsPerMinute,
            aggregation: .average, sourceMetric: "local_workout.average_heart_rate")
        add("HRT_MAX_RATE", value: legacy.maxHeartRate, unit: .beatsPerMinute,
            aggregation: .maximum, sourceMetric: "local_workout.max_heart_rate")

        // Strukturierte Zusatzdaten wandern unveraendert als JSON mit. Sie
        // gingen sonst verloren – Apple Health kennt keine Saetze und keine
        // Verletzungsnotiz.
        if let exercises = legacy.exercises, !exercises.isEmpty,
           let payload = Self.jsonString(exercises) {
            incoming.append(IncomingObservation(sourceMetric: "local_workout.exercises",
                                                metricID: "WRK_STRENGTH_SET",
                                                valueText: payload,
                                                startTime: legacy.start,
                                                endTime: legacy.end,
                                                periodType: .workout,
                                                originProvider: origin,
                                                workoutID: workoutID,
                                                metadata: ["source": "legacy_migration"],
                                                rawPayload: payload))
        }
        if let route = legacy.route, !route.isEmpty, let payload = Self.jsonString(route) {
            incoming.append(IncomingObservation(sourceMetric: "local_workout.route",
                                                metricID: "WRK_ROUTE",
                                                valueText: payload,
                                                startTime: legacy.start,
                                                endTime: legacy.end,
                                                periodType: .workout,
                                                originProvider: origin,
                                                workoutID: workoutID,
                                                metadata: ["source": "legacy_migration"],
                                                rawPayload: payload))
        }
        if let weather = legacy.weather, let payload = Self.jsonString(weather) {
            incoming.append(IncomingObservation(sourceMetric: "local_workout.weather",
                                                metricID: "WRK_WEATHER",
                                                valueText: payload,
                                                startTime: legacy.start,
                                                endTime: legacy.end,
                                                periodType: .workout,
                                                originProvider: origin,
                                                workoutID: workoutID,
                                                metadata: ["source": "legacy_migration"],
                                                rawPayload: payload))
        }
        if let injury = legacy.injury, let payload = Self.jsonString(injury) {
            incoming.append(IncomingObservation(sourceMetric: "local_workout.injury",
                                                metricID: "WRK_INJURY",
                                                valueText: payload,
                                                startTime: legacy.start,
                                                endTime: legacy.end,
                                                periodType: .workout,
                                                originProvider: origin,
                                                workoutID: workoutID,
                                                metadata: ["source": "legacy_migration"],
                                                rawPayload: payload))
        }

        let pipeline = ImportPipeline(store: store)
        let results = try await pipeline.import(incoming,
                                                from: origin == .appleHealth ? .appleHealth : .healthPit,
                                                userID: userID)
        return results.filter { $0.action == .create }.count
    }

    // MARK: - Cache-Eintraege

    private func migrateCacheEntries(into report: inout LegacyMigrationReport) async throws {
        let decoder = LegacyDecoder.make()

        // Dieselbe Nacht steht in mehreren Zeitraum-Caches – Tag, Woche,
        // Monat, Jahr –, oft in unterschiedlich vollstaendigen Staenden.
        // Erst alles einsammeln, den besten Stand je Nacht behalten, dann
        // uebernehmen. Sonst laegen am Ende mehrere Phasenreihen derselben
        // Nacht uebereinander.
        var bestNightPerWindow: [String: LegacySleepSession] = [:]

        for key in try await store.legacyCacheKeys() {
            guard let data = try await store.legacyCacheEntry(key: key) else {
                report.untouchedCacheKeys.append(key)
                continue
            }

            if key == "dashboard.metric.values",
               let entries = try? decoder.decode([LegacyDashboardMetricEntry].self, from: data) {
                report.metricObservations += try await migrate(dashboardEntries: entries)
                continue
            }
            if key.hasPrefix("sleep_sessions."),
               let sessions = try? decoder.decode([LegacySleepSession].self, from: data) {
                for session in sessions {
                    let window = Self.nightWindowKey(session)
                    if let existing = bestNightPerWindow[window],
                       !Self.isMoreComplete(session, than: existing) {
                        continue
                    }
                    bestNightPerWindow[window] = session
                }
                continue
            }
            if key.hasPrefix("health_workouts."),
               let summaries = try? decoder.decode([LegacyWorkoutSummary].self, from: data) {
                report.workouts += try await migrate(workoutSummaries: summaries)
                continue
            }
            // Alles Uebrige ist abgeleitet (Rekord-Snapshots, Zaehler) und
            // wird aus den Observations neu berechnet.
            report.untouchedCacheKeys.append(key)
        }

        if !bestNightPerWindow.isEmpty {
            let nights = bestNightPerWindow.values.sorted { $0.start < $1.start }
            report.sleepObservations += try await migrate(sleepSessions: nights)
        }
    }

    /// Zwei Eintraege beschreiben dieselbe Nacht, wenn Anfang und Ende auf die
    /// Minute genau zusammenfallen. Sekundengenau waere zu streng: Die alten
    /// Caches wurden zu verschiedenen Zeitpunkten geschrieben.
    private static func nightWindowKey(_ session: LegacySleepSession) -> String {
        let start = Int((session.start.timeIntervalSince1970 / 60).rounded())
        let end = Int((session.end.timeIntervalSince1970 / 60).rounded())
        return "\(start)-\(end)"
    }

    /// Welcher Stand derselben Nacht ist der bessere?
    ///
    /// Mehr Phasen heisst feiner ausgewertet; bei gleichem Detailgrad
    /// entscheidet die laengere Zeit im Bett – ein spaeter geschriebener
    /// Cache hat die Nacht meist vollstaendiger erwischt.
    private static func isMoreComplete(_ candidate: LegacySleepSession,
                                       than existing: LegacySleepSession) -> Bool {
        if candidate.segments.count != existing.segments.count {
            return candidate.segments.count > existing.segments.count
        }
        let candidateSpan = candidate.segments.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        let existingSpan = existing.segments.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        if candidateSpan != existingSpan { return candidateSpan > existingSpan }
        return candidate.inBed > existing.inBed
    }

    private func migrate(dashboardEntries: [LegacyDashboardMetricEntry]) async throws -> Int {
        var incoming: [IncomingObservation] = []
        for entry in dashboardEntries {
            let mapping = AppleHealthMapping.byIdentifier[entry.metricID]
            let measuredAt = entry.measuredAt ?? entry.updatedAt
            incoming.append(IncomingObservation(sourceMetric: entry.metricID,
                                                metricID: mapping?.metricID,
                                                value: entry.value,
                                                unit: mapping?.sourceUnit,
                                                startTime: measuredAt,
                                                endTime: measuredAt,
                                                aggregation: mapping?.aggregation ?? .raw,
                                                periodType: mapping?.periodType ?? .instant,
                                                originProvider: .appleHealth,
                                                metadata: [
                                                    "source": "legacy_migration",
                                                    "legacy_key": "dashboard.metric.values",
                                                    "legacy_metric_id": entry.metricID
                                                ]))
        }
        let pipeline = ImportPipeline(store: store)
        let results = try await pipeline.import(incoming, from: .appleHealth, userID: userID)
        return results.filter { $0.action == .create }.count
    }

    private func migrate(sleepSessions: [LegacySleepSession]) async throws -> Int {
        var incoming: [IncomingObservation] = []
        for session in sleepSessions {
            let durations = Self.durations(of: session)
            func add(_ metric: MetricID, _ value: Double, _ unit: UnitCode, _ sourceMetric: String) {
                incoming.append(IncomingObservation(sourceMetric: sourceMetric,
                                                    metricID: metric,
                                                    value: value,
                                                    unit: unit,
                                                    startTime: session.start,
                                                    endTime: session.end,
                                                    aggregation: .sum,
                                                    periodType: .night,
                                                    originProvider: .appleHealth,
                                                    sessionID: session.id.uuidString,
                                                    metadata: ["source": "legacy_migration"]))
            }
            let asleep = durations["deep", default: 0] + durations["core", default: 0] + durations["rem", default: 0]
            let inBed = max(session.inBed, session.end.timeIntervalSince(session.start))
            add("SLP_DURATION", asleep, .second, "sleep_session.asleep")
            add("SLP_TIME_IN_BED", inBed, .second, "sleep_session.in_bed")
            add("SLP_DEEP_DURATION", durations["deep", default: 0], .second, "sleep_session.deep")
            add("SLP_CORE_DURATION", durations["core", default: 0], .second, "sleep_session.core")
            add("SLP_REM_DURATION", durations["rem", default: 0], .second, "sleep_session.rem")
            add("SLP_AWAKE_DURATION", durations["awake", default: 0], .second, "sleep_session.awake")
            if inBed > 0 {
                incoming.append(IncomingObservation(sourceMetric: "sleep_session.efficiency",
                                                    metricID: "SLP_EFFICIENCY",
                                                    value: asleep / inBed * 100,
                                                    unit: .percent,
                                                    startTime: session.start,
                                                    endTime: session.end,
                                                    aggregation: .average,
                                                    periodType: .night,
                                                    originProvider: .appleHealth,
                                                    sessionID: session.id.uuidString,
                                                    metadata: ["source": "legacy_migration"]))
            }

            for segment in session.segments {
                incoming.append(IncomingObservation(sourceMetric: "HKCategoryTypeIdentifierSleepAnalysis",
                                                    metricID: "SLP_STAGE",
                                                    valueCode: segment.stage.uppercased(),
                                                    startTime: segment.start,
                                                    endTime: segment.end,
                                                    aggregation: .raw,
                                                    periodType: .interval,
                                                    originProvider: .appleHealth,
                                                    sessionID: session.id.uuidString,
                                                    metadata: ["source": "legacy_migration"]))
            }
        }
        let pipeline = ImportPipeline(store: store)
        let results = try await pipeline.import(incoming, from: .appleHealth, userID: userID)
        return results.filter { $0.action == .create }.count
    }

    private func migrate(workoutSummaries: [LegacyWorkoutSummary]) async throws -> Int {
        var created = 0
        for summary in workoutSummaries {
            let workoutID = WorkoutID(uuid: summary.uuid)
            if try await store.workout(workoutID) != nil {
                continue
            }
            // Eine Kopie, die GymPit ueber Apple Health abgelegt hat, behaelt
            // GymPit als Erzeuger. Sonst waere spaeter nicht mehr erkennbar,
            // dass der Originaldatensatz woanders liegt.
            let origin: ProviderCode = (summary.sourceName?.lowercased().contains("gympit") ?? false)
                ? .gymPit
                : .appleHealth
            let workout = StoredWorkout(workoutID: workoutID,
                                        userID: userID,
                                        sportType: Self.sportCode(summary.activityName),
                                        title: summary.activityName,
                                        startTime: summary.start,
                                        endTime: summary.end,
                                        originProvider: origin,
                                        ingestProvider: .appleHealth,
                                        sourceRecordID: summary.uuid.uuidString,
                                        sourceAppID: summary.sourceName,
                                        createdAt: summary.start,
                                        metadata: [
                                            "legacy_key": "health_workouts",
                                            "legacy_activity": summary.activityName
                                        ])
            try await store.insert(workout)
            try await store.upsert(ExternalReference(userID: userID,
                                                     entityType: .workout,
                                                     entityID: workoutID.rawValue,
                                                     provider: .appleHealth,
                                                     externalRecordID: summary.uuid.uuidString,
                                                     importedAt: Date(),
                                                     metadata: ["source": "legacy_migration"]))
            if let externalWorkoutID = summary.externalWorkoutID, origin == .gymPit {
                try await store.upsert(ExternalReference(userID: userID,
                                                         entityType: .workout,
                                                         entityID: workoutID.rawValue,
                                                         provider: .gymPit,
                                                         externalRecordID: externalWorkoutID,
                                                         importedAt: Date(),
                                                         metadata: ["source": "legacy_migration"]))
            }
            created += 1

            var values: [IncomingObservation] = []
            if let distance = summary.distanceKm, distance > 0 {
                values.append(IncomingObservation(sourceMetric: "workout_summary.distance_km",
                                                  metricID: "WRK_DISTANCE",
                                                  value: distance,
                                                  unit: .kilometer,
                                                  startTime: summary.start,
                                                  endTime: summary.end,
                                                  aggregation: .sum,
                                                  periodType: .workout,
                                                  originProvider: origin,
                                                  workoutID: workoutID,
                                                  metadata: ["source": "legacy_migration"]))
            }
            if let energy = summary.energyKcal, energy > 0 {
                values.append(IncomingObservation(sourceMetric: "workout_summary.energy_kcal",
                                                  metricID: "WRK_ENERGY",
                                                  value: energy,
                                                  unit: .kilocalorie,
                                                  startTime: summary.start,
                                                  endTime: summary.end,
                                                  aggregation: .sum,
                                                  periodType: .workout,
                                                  originProvider: origin,
                                                  workoutID: workoutID,
                                                  metadata: ["source": "legacy_migration"]))
            }
            let pipeline = ImportPipeline(store: store)
            _ = try await pipeline.import(values, from: .appleHealth, userID: userID)
        }
        return created
    }

    // MARK: - Hilfen

    private static func durations(of session: LegacySleepSession) -> [String: TimeInterval] {
        session.segments.reduce(into: [:]) { result, segment in
            result[segment.stage.lowercased(), default: 0] += segment.end.timeIntervalSince(segment.start)
        }
    }

    /// Herkunft eines Altdatensatzes.
    ///
    /// `gpx`/`tcx` sind Dateiimporte ohne fremdes System dahinter – die zaehlen
    /// als in HealthPit entstanden. `garmin` kann in alten Sicherungsdateien
    /// stehen und bekommt jetzt seinen richtigen Provider-Code.
    static func provider(forLegacySource source: String) -> ProviderCode {
        switch source.lowercased() {
        case "apple_health": return .appleHealth
        case "gympit": return .gymPit
        case "garmin": return .garmin
        default: return .healthPit
        }
    }

    /// Sportart als neutraler Code. Die deutschen Anzeigenamen bleiben in der
    /// App; hier zaehlt ein stabiler Schluessel.
    static func sportCode(_ sport: String) -> String {
        let normalized = sport
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
            .map { character -> Character in
                (character.isLetter || character.isNumber) ? character : "_"
            }
            .reduce(into: "") { result, character in
                if character == "_", result.last == "_" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return normalized.isEmpty ? "OTHER" : normalized
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
