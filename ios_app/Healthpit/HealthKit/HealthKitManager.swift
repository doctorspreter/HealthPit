//
//  HealthKitManager.swift
//  Healthpit
//
//  Der zentrale, read-only HealthKit-Service (PLAN.md Abschnitt 4.1). Kapselt
//  Autorisierung und die generischen Abfragen, sodass ViewModels/Views nie
//  direkt mit HealthKit-Klassen hantieren müssen. Async/await-API.
//
//  Thread-Sicherheit: HKHealthStore ist laut Apple thread-safe, daher ist die
//  Klasse als @unchecked Sendable markiert und kann von beliebigen Aktoren
//  (z. B. @MainActor-ViewModels) aufgerufen werden.
//

import Foundation
import HealthKit
import CoreLocation
import os

private actor HealthAuthorizationCoordinator {
    private var didRequest = false
    private var inFlight: Task<Void, Error>?

    func requestOnce(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        if didRequest { return }
        if let inFlight {
            try await inFlight.value
            return
        }

        let task = Task {
            try await operation()
        }
        inFlight = task
        do {
            try await task.value
            didRequest = true
            inFlight = nil
        } catch {
            inFlight = nil
            throw error
        }
    }
}

final class HealthKitManager: @unchecked Sendable {

    /// Geteilte Instanz – ein HKHealthStore pro App ist die empfohlene Praxis.
    nonisolated static let shared = HealthKitManager()

    /// Nicht private: die Zyklus-Erweiterung in HealthKitManager+Cycle.swift
    /// schreibt und loescht ueber denselben Store.
    let healthStore = HKHealthStore()

    /// Logger – Ausgaben erscheinen in der Xcode-Konsole (Subsystem "HealthPit").
    private let log = Logger(subsystem: "HealthPit", category: "HealthKit")
    private let authorizationCoordinator = HealthAuthorizationCoordinator()

    /// Gemerkt, dass der Freigabedialog schon einmal beantwortet wurde.
    private static let didRequestKey = "healthAuthorizationRequested"

    private init() {}

    enum SampleQueryScope {
        case none
        case predicate(NSPredicate)
    }

    /// Ob HealthKit auf diesem Gerät überhaupt verfügbar ist (false z. B. auf iPad).
    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Autorisierung (PLAN Schritt 2)

    /// Fragt Lesezugriff für alle in `HealthKitTypes.readTypes` definierten Typen an.
    ///
    /// Wichtig (PLAN Abschnitt 3.3 / 9): Bei reinem Lesezugriff verrät iOS aus
    /// Datenschutzgründen NICHT, ob der Nutzer zugestimmt hat. Daher gibt es hier
    /// bewusst kein "ist autorisiert?"-Ergebnis – ein erfolgreicher Aufruf heißt
    /// nur, dass der Dialog gezeigt wurde. Fehlender Zugriff zeigt sich später
    /// als leeres Query-Ergebnis (Empty-State), nicht als Fehler.
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            log.error("HealthKit nicht verfügbar auf diesem Gerät.")
            throw HealthError.healthDataUnavailable
        }
        try await authorizationCoordinator.requestOnce {
            // Steht nichts mehr aus, darf der Systemdialog auch nicht mehr
            // angestossen werden: iOS zeigt sonst bei jedem Start ein Blatt,
            // das ueber dem gerade offenen Hinweis liegt und dort haengen
            // bleibt.
            guard await self.hasPendingAuthorizationRequest(
                toShare: HealthKitTypes.shareTypes,
                read: HealthKitTypes.readTypes
            ) else { return }
            try await self.performAuthorizationRequest()
        }
    }

    /// Bereitet Hintergrundarbeit vor, ohne je den Systemdialog zu zeigen.
    ///
    /// Vorladen und Aktualisieren laufen beim Start los — genau dann, wenn
    /// womoeglich schon ein anderes Blatt offen ist. Ein Freigabedialog
    /// daneben ist nicht bedienbar. Fehlt die Freigabe, bleiben die Abfragen
    /// eben leer; gefragt wird ueber die Kachel auf der Startseite.
    func prepareForBackgroundWork() async {
        guard isHealthDataAvailable else { return }
        guard await !needsAuthorizationRequest() else { return }
        await UnitPreference.refreshFromAppleHealth(store: healthStore)
    }

    /// Ob der Freigabedialog für die *Lesetypen* noch aussteht.
    ///
    /// Bei reinem Lesezugriff verrät iOS nicht, ob zugestimmt wurde — wohl aber,
    /// ob überhaupt schon gefragt wurde. Genau das braucht die Startseite, um
    /// die Kachel für die erneute Anfrage einzublenden.
    ///
    /// Die Schreibtypen bleiben hier bewusst aussen vor: sie wachsen mit jeder
    /// Fassung (zuletzt die Zyklustypen), und ein neu hinzugekommener
    /// Schreibtyp wuerde die Kachel wieder einblenden, obwohl das Lesen laengst
    /// freigegeben ist. Um Schreibrechte wird dort gebeten, wo geschrieben wird.
    func needsAuthorizationRequest() async -> Bool {
        guard isHealthDataAvailable else { return false }
        if UserDefaults.standard.bool(forKey: Self.didRequestKey) { return false }

        guard await hasPendingAuthorizationRequest(toShare: [], read: HealthKitTypes.readTypes) else {
            markAuthorizationRequested()
            return false
        }

        // Der Status meldet auch dann noch "offen", wenn nur ein einzelner Typ
        // nie im Dialog stand — etwa einer, der erst mit dieser Fassung
        // dazugekommen ist. Kommen Werte an, ist die Freigabe da, und die
        // Kachel haette nichts zu melden.
        if await hasReadableData() {
            markAuthorizationRequested()
            return false
        }
        return true
    }

    /// Ob sich ueberhaupt ein Wert lesen laesst — der einzige verlaessliche
    /// Beweis fuer erteilten Lesezugriff, den iOS herausgibt.
    private func hasReadableData() async -> Bool {
        for metric in HealthMetric.all.prefix(8) {
            if let latest = try? await latestValue(for: metric), latest.value != 0 {
                return true
            }
        }
        return (try? await fetchAllWorkouts(limit: 1))?.isEmpty == false
    }

    private func markAuthorizationRequested() {
        UserDefaults.standard.set(true, forKey: Self.didRequestKey)
    }

    private func hasPendingAuthorizationRequest(toShare share: Set<HKSampleType>,
                                                read: Set<HKObjectType>) async -> Bool {
        guard isHealthDataAvailable else { return false }
        do {
            let status = try await healthStore.statusForAuthorizationRequest(toShare: share, read: read)
            return status == .shouldRequest
        } catch {
            log.error("Autorisierungsstatus nicht ermittelbar: \(error.localizedDescription)")
            return false
        }
    }

    private func performAuthorizationRequest() async throws {
        let types = HealthKitTypes.readTypes
        let shareTypes = HealthKitTypes.shareTypes
        log.info("Fordere Lesezugriff für \(types.count, privacy: .public) Typen an …")
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: types)
            log.info("requestAuthorization zurückgekehrt (Dialog beantwortet).")
            // Der Dialog stand einmal — danach hat die Kachel auf der
            // Startseite nichts mehr zu suchen, egal wie der Nutzer entschieden
            // hat. Was fehlt, zeigen die Empty-States.
            markAuthorizationRequested()
            // Erst jetzt darf nach den bevorzugten Einheiten gefragt werden –
            // ohne Autorisierung liefert preferredUnits nichts Brauchbares.
            await UnitPreference.refreshFromAppleHealth(store: healthStore)
        } catch {
            log.error("requestAuthorization fehlgeschlagen: \(error.localizedDescription)")
            throw HealthError.authorizationFailed(underlying: error)
        }
    }

    // MARK: - Datenquellen

    /// Liefert alle Apps und Geräte, die Daten in Apple Health bereitstellen,
    /// zusammen mit den Datentypen, die Healthpit bei ihnen gefunden hat.
    func discoverDataSources() async throws -> [HealthSourceDescriptor] {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        await prepareForBackgroundWork()

        var names: [String: String] = [:]
        var dataPoints: [String: Set<String>] = [:]

        func collect(_ sources: Set<HKSource>, dataPointID: String) {
            for source in sources {
                names[source.bundleIdentifier] = source.name
                dataPoints[source.bundleIdentifier, default: []].insert(dataPointID)
            }
        }

        for metric in HealthMetric.all {
            collect(try await sources(for: metric.quantityType), dataPointID: metric.id)
        }
        collect(try await sources(for: .workoutType()), dataPointID: HealthDataPointDescriptor.workoutsID)
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            collect(try await sources(for: sleepType), dataPointID: HealthDataPointDescriptor.sleepID)
        }
        for identifier in HealthKitTypes.cycleIdentifiers {
            guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { continue }
            collect(try await sources(for: type), dataPointID: HealthDataPointDescriptor.cycleID)
        }

        return names.map { id, name in
            HealthSourceDescriptor(id: id, name: name, dataPointIDs: dataPoints[id] ?? [])
        }
        .sorted {
            if $0.isHealthpit != $1.isHealthpit { return $0.isHealthpit }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func sources(for sampleType: HKSampleType) async throws -> Set<HKSource> {
        let store = healthStore
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSourceQuery(sampleType: sampleType, samplePredicate: nil) { _, sources, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                } else {
                    continuation.resume(returning: sources ?? [])
                }
            }
            store.execute(query)
        }
    }

    func configuredScope(basePredicate: NSPredicate,
                                 sampleType: HKSampleType,
                                 dataPointID: String) async throws -> SampleQueryScope {
        let disabledSources = Set(UserDefaults.standard.stringArray(
            forKey: HealthDataSourceSettings.disabledSourcesKey
        ) ?? [])
        let disabledDataPoints = Set(UserDefaults.standard.stringArray(
            forKey: HealthDataSourceSettings.disabledDataPointsKey
        ) ?? [])
        guard !disabledSources.isEmpty || !disabledDataPoints.isEmpty else {
            return .predicate(basePredicate)
        }

        let available = try await sources(for: sampleType)
        let allowed = Set(available.filter { source in
            !disabledSources.contains(source.bundleIdentifier)
                && !disabledDataPoints.contains("\(source.bundleIdentifier)|\(dataPointID)")
        })
        guard !allowed.isEmpty else { return .none }

        let sourcePredicate = HKQuery.predicateForObjects(from: allowed)
        return .predicate(NSCompoundPredicate(andPredicateWithSubpredicates: [basePredicate, sourcePredicate]))
    }

    func saveToAppleHealth(_ workout: LocalWorkout) async throws {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        guard HealthDataSourceSettings.isWritingEnabled(forKey: HealthDataSourceSettings.writeWorkoutsKey) else {
            throw HealthError.queryFailed(underlying: NSError(
                domain: "HealthPit",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "Das Schreiben von Trainings nach Apple Health ist in den Datenquellen-Einstellungen deaktiviert."]
            ))
        }
        try await requestAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: workout.sport)
        configuration.locationType = workout.route.isEmpty ? .unknown : .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore,
                                       configuration: configuration,
                                       device: .local())

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: workout.start) { success, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: NSError(
                        domain: "HealthPit",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Apple Health hat das Workout nicht gespeichert."]
                    )))
                }
            }
        }

        var samples: [HKSample] = []
        if HealthDataSourceSettings.isWritingEnabled(forKey: HealthDataSourceSettings.writeActiveEnergyKey),
           let kcal = workout.energyKcal, kcal > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                            start: workout.start,
                                            end: workout.end))
        }
        if let km = workout.distanceKm,
           km > 0,
           let distanceType = Self.distanceType(for: workout.sport),
           Self.isWritingEnabled(for: distanceType) {
            samples.append(HKQuantitySample(type: distanceType,
                                            quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km),
                                            start: workout.start,
                                            end: workout.end))
        }
        if !samples.isEmpty {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.add(samples) { success, error in
                    if let error {
                        continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HealthError.queryFailed(underlying: NSError(
                            domain: "HealthPit",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Apple Health hat die Workout-Werte nicht gespeichert."]
                        )))
                    }
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: workout.end) { success, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: NSError(
                        domain: "HealthPit",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Apple Health hat das Workout nicht abgeschlossen."]
                    )))
                }
            }
        }

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout, Error>) in
            builder.finishWorkout { sample, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                } else if let sample {
                    continuation.resume(returning: sample)
                } else {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: NSError(
                        domain: "HealthPit",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Apple Health hat kein Workout zurueckgegeben."]
                    )))
                }
            }
        }
    }

    /// Entfernt ausschliesslich Objekte, die Healthpit selbst in Apple Health
    /// geschrieben hat. Daten anderer Apps kann iOS hier bewusst nicht loeschen.
    func deleteDataWrittenByHealthpit() async throws -> Int {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        try await requestAuthorization()
        let predicate = HKQuery.predicateForObjects(from: [HKSource.default()])
        var deleted = 0
        for type in HealthKitTypes.shareTypes {
            let count: Int = try await withCheckedThrowingContinuation { continuation in
                healthStore.deleteObjects(of: type, predicate: predicate) { success, count, error in
                    if let error {
                        continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    } else if success {
                        continuation.resume(returning: count)
                    } else {
                        continuation.resume(returning: 0)
                    }
                }
            }
            deleted += count
        }
        return deleted
    }

    // MARK: - Einzelnes Training in Apple Health

    /// Wer einen Eintrag in Apple Health geschrieben hat.
    ///
    /// Die Unterscheidung ist keine Feinheit, sondern die Grenze des
    /// Moeglichen: iOS laesst jede App nur ihre eigenen Eintraege loeschen.
    /// Kommt dasselbe Training dreimal — von Health Sync, von Huawei, von der
    /// Uhr — kann HealthPit keine dieser Kopien entfernen, und ein Knopf, der
    /// das verspricht, wuerde luegen.
    enum AppleHealthOrigin: Sendable, Equatable {
        /// Von HealthPit selbst geschrieben; loeschbar.
        case ours(String)
        /// Von einer anderen App geschrieben; nur dort loeschbar.
        case foreign(String)
        /// In Apple Health nicht (mehr) vorhanden.
        case missing

        var isDeletable: Bool {
            if case .ours = self { return true }
            return false
        }

        var appName: String? {
            switch self {
            case .ours(let name), .foreign(let name): return name
            case .missing: return nil
            }
        }
    }

    /// Woher ein Training in Apple Health stammt.
    func origin(ofWorkout uuid: UUID) async -> AppleHealthOrigin {
        // `try?` faltet die beiden Optionals zusammen: kein Treffer und ein
        // Fehler bei der Abfrage laufen hier bewusst auf dasselbe hinaus.
        guard let sample = try? await workoutSample(uuid: uuid) else { return .missing }
        let name = sample.sourceRevision.source.name
        return sample.sourceRevision.source == HKSource.default() ? .ours(name) : .foreign(name)
    }

    /// Loescht ein Training aus Apple Health, sofern HealthPit es geschrieben hat.
    ///
    /// Gibt zurueck, was tatsaechlich geschehen ist, statt einen Fehler zu
    /// werfen: „geht nicht, weil eine andere App den Eintrag angelegt hat" ist
    /// keine Stoerung, sondern eine Auskunft, die der Anwender lesen soll.
    @discardableResult
    func deleteWorkout(uuid: UUID) async throws -> AppleHealthOrigin {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        try await requestAuthorization()
        guard let sample = try await workoutSample(uuid: uuid) else { return .missing }
        let name = sample.sourceRevision.source.name
        guard sample.sourceRevision.source == HKSource.default() else { return .foreign(name) }

        let store = healthStore
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.delete(sample) { _, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                } else {
                    continuation.resume()
                }
            }
        }
        return .ours(name)
    }

    private func workoutSample(uuid: UUID) async throws -> HKWorkout? {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        try await requestAuthorization()
        let store = healthStore
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                      predicate: HKQuery.predicateForObject(with: uuid),
                                      limit: 1,
                                      sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                } else {
                    continuation.resume(returning: samples?.first as? HKWorkout)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Aggregierter Verlauf (für Diagramme)

    /// Lädt den über `range` aggregierten Verlauf einer Metrik (Bucket-weise).
    ///
    /// Nutzt `HKStatisticsCollectionQuery`, das Werte aus mehreren Quellen
    /// (iPhone, Apple Watch, …) korrekt zusammenfasst und Duplikate vermeidet.
    func fetchStatistics(for metric: HealthMetric,
                         in range: TimeRange,
                         referenceDate now: Date = .now) async throws -> [DailyStatistic] {
        let interval = range.dateInterval(referenceDate: now)
        let anchor = range.anchorDate(referenceDate: now)
        let bucket = range.bucketComponents
        return try await fetchStatistics(for: metric,
                                         interval: interval,
                                         anchorDate: anchor,
                                         bucket: bucket)
    }

    /// Lädt Metrik-Verläufe für ein frei gewähltes Intervall.
    /// Wird für Trends genutzt, die bewusst nicht an Tag/Woche/Monat/Jahr gebunden sind.
    func fetchStatistics(for metric: HealthMetric,
                         interval: DateInterval,
                         anchorDate: Date? = nil,
                         bucket: DateComponents = DateComponents(day: 1)) async throws -> [DailyStatistic] {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }

        let quantityType = metric.quantityType
        let unit = metric.unit
        let aggregation = metric.aggregation
        let options = aggregation.statisticsOptions
        let anchor = anchorDate ?? Calendar.healthApp.startOfDay(for: interval.start)
        let store = healthStore

        let predicate = HKQuery.predicateForSamples(withStart: interval.start,
                                                    end: interval.end,
                                                    options: .strictStartDate)

        let scope = try await configuredScope(basePredicate: predicate,
                                              sampleType: quantityType,
                                              dataPointID: metric.id)
        guard case .predicate(let configuredPredicate) = scope else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: configuredPredicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: bucket
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var result: [DailyStatistic] = []
                collection.enumerateStatistics(from: interval.start, to: interval.end) { stats, _ in
                    let quantity: HKQuantity?
                    switch aggregation {
                    case .cumulativeSum:   quantity = stats.sumQuantity()
                    case .discreteAverage: quantity = stats.averageQuantity()
                    }
                    if let quantity, quantity.is(compatibleWith: unit) {
                        result.append(DailyStatistic(date: stats.startDate,
                                                     value: quantity.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: result)
            }

            store.execute(query)
        }
    }

    private func earliestSampleDate(for metric: HealthMetric) async throws -> Date? {
        let type = metric.quantityType
        let basePredicate = HKQuery.predicateForSamples(withStart: .distantPast,
                                                        end: .now,
                                                        options: .strictStartDate)
        let scope = try await configuredScope(basePredicate: basePredicate,
                                              sampleType: type,
                                              dataPointID: metric.id)
        guard case .predicate(let predicate) = scope else { return nil }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type,
                                      predicate: predicate,
                                      limit: 1,
                                      sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: samples?.first?.startDate)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Aktueller Wert (für Dashboard-Kacheln)

    /// Tagessumme über eine kumulierbare Metrik via `HKStatisticsQuery`.
    private func todaySum(for metric: HealthMetric, referenceDate now: Date) async throws -> Double? {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }

        let quantityType = metric.quantityType
        let unit = metric.unit
        let interval = TimeRange.day.dateInterval(referenceDate: now)
        let store = healthStore
        let predicate = HKQuery.predicateForSamples(withStart: interval.start,
                                                    end: interval.end,
                                                    options: .strictStartDate)

        let scope = try await configuredScope(basePredicate: predicate,
                                              sampleType: quantityType,
                                              dataPointID: metric.id)
        guard case .predicate(let configuredPredicate) = scope else { return nil }

        log.info("Starte Tagessummen-Abfrage für \(metric.title) …")
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType,
                                          quantitySamplePredicate: configuredPredicate,
                                          options: .cumulativeSum) { [log] _, stats, error in
                if let error {
                    log.error("Tagessummen-Abfrage fehlgeschlagen: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                let sum = stats?.sumQuantity()
                let value = (sum?.is(compatibleWith: unit) == true) ? sum?.doubleValue(for: unit) : nil
                let valueText = value.map { "\($0)" } ?? "nil"
                log.info("Tagessummen-Abfrage zurück: \(valueText, privacy: .public)")
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Jüngste Einzelmessung einer Metrik (für Momentaufnahmen wie Gewicht/Puls).
    private func mostRecentValue(for metric: HealthMetric) async throws -> Double? {
        try await latestValue(for: metric)?.value
    }

    func latestValue(for metric: HealthMetric) async throws -> LatestMetricValue? {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }

        let quantityType = metric.quantityType
        let unit = metric.unit
        let store = healthStore
        let predicate = HKQuery.predicateForSamples(withStart: .distantPast,
                                                    end: .now,
                                                    options: .strictStartDate)
        let scope = try await configuredScope(basePredicate: predicate,
                                              sampleType: quantityType,
                                              dataPointID: metric.id)
        guard case .predicate(let configuredPredicate) = scope else { return nil }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType,
                                      predicate: configuredPredicate,
                                      limit: 1,
                                      sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                guard let sample = (samples as? [HKQuantitySample])?.first,
                      sample.quantity.is(compatibleWith: unit) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: LatestMetricValue(value: sample.quantity.doubleValue(for: unit),
                                                                 date: sample.startDate))
            }
            store.execute(query)
        }
    }

    /// Gibt es für diese Metrik überhaupt jemals Daten? (Leichtgewichtig: limit 1
    /// über die gesamte Historie.) Liefert false auch bei fehlendem Zugriff –
    /// solche Metriken werden in der UI ausgegraut und nach unten sortiert.
    func hasEverData(for metric: HealthMetric) async -> Bool {
        guard isHealthDataAvailable else { return false }
        let store = healthStore
        let predicate = HKQuery.predicateForSamples(withStart: .distantPast, end: .now)
        guard let scope = try? await configuredScope(basePredicate: predicate,
                                                     sampleType: metric.quantityType,
                                                     dataPointID: metric.id),
              case .predicate(let configuredPredicate) = scope else { return false }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: metric.quantityType,
                                      predicate: configuredPredicate,
                                      limit: 1,
                                      sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples?.isEmpty == false))
            }
            store.execute(query)
        }
    }

    // MARK: - Rohdaten (für Sample-Liste, PLAN Screen 3)

    /// Lädt einzelne Messungen einer Metrik inkl. Quelle, sortiert nach Datum.
    func fetchSamples(for metric: HealthMetric,
                      in range: TimeRange,
                      limit: Int = HKObjectQueryNoLimit,
                      newestFirst: Bool = true,
                      referenceDate now: Date = .now) async throws -> [MetricSample] {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }

        let quantityType = metric.quantityType
        let unit = metric.unit
        let unitSymbol = metric.unitSymbol
        let interval = range.dateInterval(referenceDate: now)
        let store = healthStore
        let predicate = HKQuery.predicateForSamples(withStart: interval.start,
                                                    end: interval.end,
                                                    options: .strictStartDate)
        let scope = try await configuredScope(basePredicate: predicate,
                                              sampleType: quantityType,
                                              dataPointID: metric.id)
        guard case .predicate(let configuredPredicate) = scope else { return [] }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: !newestFirst)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType,
                                      predicate: configuredPredicate,
                                      limit: limit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                let mapped = quantitySamples.compactMap { sample -> MetricSample? in
                    guard sample.quantity.is(compatibleWith: unit) else { return nil }
                    return MetricSample(startDate: sample.startDate,
                                        endDate: sample.endDate,
                                        value: sample.quantity.doubleValue(for: unit),
                                        unitSymbol: unitSymbol,
                                        sourceName: sample.sourceRevision.source.name)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts (PLAN Schritt 10, Vorab-Version fürs Dashboard)

    /// Lädt Workouts im Zeitraum, neueste zuerst, inkl. Dauer/Distanz/Kalorien.
    func fetchWorkouts(in range: TimeRange,
                       limit: Int = 50,
                       referenceDate now: Date = .now) async throws -> [WorkoutSummary] {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }

        let interval = range.dateInterval(referenceDate: now)
        return try await fetchWorkouts(start: interval.start,
                                       end: interval.end,
                                       limit: limit,
                                       logLabel: range.title)
    }

    func fetchWorkouts(start: Date,
                       end: Date = Date.distantFuture,
                       limit: Int = HKObjectQueryNoLimit) async throws -> [WorkoutSummary] {
        try await fetchWorkouts(start: start,
                                end: end,
                                limit: limit,
                                logLabel: "inkrementell")
    }

    private func fetchWorkouts(start: Date,
                               end: Date,
                               limit: Int,
                               logLabel: String) async throws -> [WorkoutSummary] {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }

        let store = healthStore
        let predicate = HKQuery.predicateForSamples(withStart: start,
                                                    end: end,
                                                    options: .strictStartDate)
        let scope = try await configuredScope(basePredicate: predicate,
                                              sampleType: .workoutType(),
                                              dataPointID: HealthDataPointDescriptor.workoutsID)
        guard case .predicate(let configuredPredicate) = scope else { return [] }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]

        log.info("Starte Workout-Abfrage (\(logLabel, privacy: .public)) …")
        return try await withCheckedThrowingContinuation { [log] continuation in
            let query = HKSampleQuery(sampleType: .workoutType(),
                                      predicate: configuredPredicate,
                                      limit: limit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error {
                    log.error("Workout-Abfrage fehlgeschlagen: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let mapped = workouts.map { Self.makeSummary(from: $0) }
                log.info("Workout-Abfrage zurück: \(mapped.count, privacy: .public) Workouts")
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// Laedt alle Workouts aus Apple Health, unabhaengig vom Alter.
    func fetchAllWorkouts(limit: Int = HKObjectQueryNoLimit) async throws -> [WorkoutSummary] {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }

        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let store = healthStore

        let allPredicate = HKQuery.predicateForSamples(withStart: .distantPast,
                                                       end: .distantFuture,
                                                       options: .strictStartDate)
        let scope = try await configuredScope(basePredicate: allPredicate,
                                              sampleType: .workoutType(),
                                              dataPointID: HealthDataPointDescriptor.workoutsID)
        guard case .predicate(let configuredPredicate) = scope else { return [] }

        log.info("Starte Workout-Abfrage (gesamt) ...")
        return try await withCheckedThrowingContinuation { [log] continuation in
            let query = HKSampleQuery(sampleType: .workoutType(),
                                      predicate: configuredPredicate,
                                      limit: limit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error {
                    log.error("Workout-Abfrage gesamt fehlgeschlagen: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let mapped = workouts.map { Self.makeSummary(from: $0) }
                log.info("Workout-Abfrage gesamt zurueck: \(mapped.count, privacy: .public) Workouts")
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// Wandelt ein HKWorkout in unser schlankes Anzeige-Modell um.
    private static func makeSummary(from workout: HKWorkout) -> WorkoutSummary {
        // Energie & Distanz über die moderne statistics(for:)-API (vermeidet
        // die veralteten totalEnergyBurned/totalDistance-Properties).
        let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        let distanceIDs: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning,
                                                       .distanceCycling,
                                                       .distanceSwimming]
        var km: Double?
        for id in distanceIDs {
            if let meters = workout.statistics(for: HKQuantityType(id))?
                .sumQuantity()?.doubleValue(for: .meter()) {
                km = meters / 1000
                break
            }
        }

        let type = workout.workoutActivityType
        let externalWorkoutID = (workout.metadata?[HKMetadataKeyExternalUUID] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutSummary(uuid: workout.uuid,
                              externalWorkoutID: externalWorkoutID?.isEmpty == false ? externalWorkoutID : nil,
                              activityName: type.displayName,
                              sportType: AppleHealthIngest.sportType(type),
                              symbol: type.symbol,
                              sourceName: workout.sourceRevision.source.name,
                              start: workout.startDate,
                              end: workout.endDate,
                              duration: workout.duration,
                              energyKcal: kcal,
                              distanceKm: km,
                              weather: Self.weather(from: workout.metadata))
    }

    private static func weather(from metadata: [String: Any]?) -> WorkoutWeather? {
        guard let metadata else { return nil }
        let condition = (metadata[HKMetadataKeyWeatherCondition] as? NSNumber)
            .map { weatherConditionTitle($0.intValue) }
        let temperature = (metadata[HKMetadataKeyWeatherTemperature] as? HKQuantity)?
            .doubleValue(for: .degreeCelsius())
        let rawHumidity = (metadata[HKMetadataKeyWeatherHumidity] as? HKQuantity)?
            .doubleValue(for: .percent())
        let humidity = rawHumidity.map { $0 <= 1 ? $0 * 100 : $0 }
        let weather = WorkoutWeather(condition: condition,
                                     temperatureCelsius: temperature,
                                     humidityPercent: humidity)
        return weather.summary.isEmpty ? nil : weather
    }

    private static func weatherConditionTitle(_ value: Int) -> String {
        switch value {
        case 1: return "Klar"
        case 2: return "Heiter"
        case 3: return "Teilweise bewölkt"
        case 4: return "Überwiegend bewölkt"
        case 5: return "Bewölkt"
        case 6: return "Nebel"
        case 7: return "Dunst"
        case 8: return "Windig"
        case 11: return "Schnee"
        case 12: return "Hagel"
        case 20: return "Nieselregen"
        case 21, 22: return "Schauer"
        case 23: return "Gewitter"
        default: return ""
        }
    }

    // MARK: - Schlaf (PLAN Schritt 11)

    /// Lädt Schlafphasen für ein frei gewähltes Intervall.
    func fetchSleep(interval: DateInterval) async throws -> [SleepSession] {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }

        let store = healthStore
        let predicate = HKQuery.predicateForSamples(withStart: interval.start,
                                                    end: interval.end, options: [])
        let scope = try await configuredScope(basePredicate: predicate,
                                              sampleType: type,
                                              dataPointID: HealthDataPointDescriptor.sleepID)
        guard case .predicate(let configuredPredicate) = scope else { return [] }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type,
                                      predicate: configuredPredicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        return Self.groupIntoNights(samples)
    }

    /// Gruppiert Schlaf-Samples zu Nächten: ein Abstand > 3 h startet eine neue.
    private static func groupIntoNights(_ samples: [HKCategorySample]) -> [SleepSession] {
        guard !samples.isEmpty else { return [] }
        let gapThreshold: TimeInterval = 3 * 3600

        var sessions: [SleepSession] = []
        var group: [HKCategorySample] = []

        func stage(for value: Int) -> SleepStage? {
            switch HKCategoryValueSleepAnalysis(rawValue: value) {
            case .asleepDeep:                  return .deep
            case .asleepCore, .asleepUnspecified: return .core
            case .asleepREM:                   return .rem
            case .awake:                       return .awake
            default:                           return nil   // inBed u. a. → kein Segment
            }
        }

        func flush() {
            guard let first = group.first else { return }
            let start = group.map(\.startDate).min() ?? first.startDate
            let end = group.map(\.endDate).max() ?? first.endDate
            var inBed = 0.0
            var segments: [SleepSegment] = []
            for s in group {
                if HKCategoryValueSleepAnalysis(rawValue: s.value) == .inBed {
                    inBed += s.endDate.timeIntervalSince(s.startDate)
                } else if let st = stage(for: s.value) {
                    segments.append(SleepSegment(stage: st, start: s.startDate, end: s.endDate))
                }
            }
            sessions.append(SleepSession(start: start, end: end, inBed: inBed, segments: segments))
        }

        var lastEnd: Date?
        for sample in samples {
            if let lastEnd, sample.startDate.timeIntervalSince(lastEnd) > gapThreshold {
                flush(); group.removeAll()
            }
            group.append(sample)
            lastEnd = max(lastEnd ?? sample.endDate, sample.endDate)
        }
        flush()

        return sessions.sorted { $0.start > $1.start }   // neueste zuerst
    }

    // MARK: - Workout-Detail inkl. Route (PLAN Schritt 10)

    /// Lädt für ein Workout (per UUID) alle verfügbaren Kennzahlen + GPS-Route.
    func workoutDetail(for uuid: UUID) async throws -> WorkoutDetail {
        guard let workout = try await fetchWorkout(uuid: uuid) else {
            return WorkoutDetail(stats: [], route: [], splits: [], heartRate: nil)
        }
        let route = (try? await fetchRoute(for: workout)) ?? []
        let splits = Self.splits(from: route)
        let workoutHeartRate = Self.heartRateSummary(from: workout)
        let sampledHeartRate = try? await heartRateSummary(start: workout.startDate, end: workout.endDate)
        let heartRate = Self.combinedHeartRate(preferred: workoutHeartRate, samples: sampledHeartRate)
        let stats = Self.allStats(from: workout, route: route, splits: splits, heartRate: heartRate)
        log.info("Workout-Detail: \(stats.count, privacy: .public) Kennzahlen, \(route.count, privacy: .public) Routenpunkte")
        return WorkoutDetail(stats: stats, route: route, splits: splits, heartRate: heartRate)
    }

    /// Holt normale Herzfrequenz-Samples im Zeitfenster eines Workouts.
    /// Das ist der Fallback, wenn das Workout selbst keine Pulsstatistik enthält.
    func heartRateSummary(start: Date, end: Date) async throws -> HeartRateSummary? {
        guard isHealthDataAvailable, end > start else { return nil }
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let scope = try await configuredScope(basePredicate: predicate,
                                              sampleType: type,
                                              dataPointID: HKQuantityTypeIdentifier.heartRate.rawValue)
        guard case .predicate(let configuredPredicate) = scope else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let store = healthStore

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type,
                                      predicate: configuredPredicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        let points = samples
            .map { HeartRatePoint(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit)) }
            .filter { $0.bpm > 0 && $0.bpm.isFinite }
        guard !points.isEmpty else { return nil }
        let values = points.map(\.bpm)
        return HeartRateSummary(average: values.reduce(0, +) / Double(values.count),
                                minimum: values.min() ?? 0,
                                maximum: values.max() ?? 0,
                                samples: points)
    }

    /// Holt das HKWorkout per UUID zurück.
    private func fetchWorkout(uuid: UUID) async throws -> HKWorkout? {
        let store = healthStore
        let predicate = HKQuery.predicateForObjects(with: [uuid])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(),
                                      predicate: predicate,
                                      limit: 1,
                                      sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout])?.first)
            }
            store.execute(query)
        }
    }

    /// Extrahiert alle verfügbaren Kennzahlen eines Workouts.
    private static func allStats(from workout: HKWorkout,
                                 route: [RoutePoint],
                                 splits: [WorkoutSplit],
                                 heartRate: HeartRateSummary?) -> [WorkoutStat] {
        var out: [WorkoutStat] = []

        let durationText = formatWorkoutDuration(workout.duration)
        out.append(WorkoutStat(label: "Dauer", value: durationText, systemImage: "clock"))

        // Summen-Kennzahlen (Distanz, Kalorien, Schritte …).
        let specs: [(HKQuantityTypeIdentifier, String, HKUnit, String, Int, String)] = [
            (.activeEnergyBurned, "Aktive Kalorien", .kilocalorie(), "kcal", 0, "flame.fill"),
            (.basalEnergyBurned, "Ruhe-Kalorien", .kilocalorie(), "kcal", 0, "flame"),
            (.distanceWalkingRunning, "Distanz", .meterUnit(with: .kilo), "km", 2, "figure.walk"),
            (.distanceCycling, "Distanz (Rad)", .meterUnit(with: .kilo), "km", 2, "bicycle"),
            (.distanceSwimming, "Distanz (Schwimmen)", .meter(), "m", 0, "figure.pool.swim"),
            (.distanceDownhillSnowSports, "Distanz (Ski)", .meterUnit(with: .kilo), "km", 2, "figure.skiing.downhill"),
            (.stepCount, "Schritte", .count(), "", 0, "shoeprints.fill"),
            (.flightsClimbed, "Etagen", .count(), "", 0, "figure.stairs"),
            (.swimmingStrokeCount, "Schwimmzüge", .count(), "", 0, "figure.pool.swim"),
        ]
        for (id, label, unit, sym, digits, icon) in specs {
            if let q = workout.statistics(for: HKQuantityType(id))?.sumQuantity(),
               q.is(compatibleWith: unit) {
                out.append(WorkoutStat(label: label,
                                       value: format(q.doubleValue(for: unit), sym, digits),
                                       systemImage: icon))
            }
        }

        let distanceKm = workoutDistanceKm(from: workout)
        if let distanceKm, distanceKm > 0, workout.duration > 0 {
            let speed = distanceKm / (workout.duration / 3600)
            if isCycling(workout.workoutActivityType) {
                out.append(WorkoutStat(label: "Ø Geschwindigkeit", value: format(speed, "km/h", 1), systemImage: "speedometer"))
            } else if isRunningOrWalking(workout.workoutActivityType) {
                out.append(WorkoutStat(label: "Ø Pace", value: paceText(workout.duration / distanceKm), systemImage: "timer"))
            } else {
                out.append(WorkoutStat(label: "Ø Tempo", value: format(speed, "km/h", 1), systemImage: "speedometer"))
            }
        }
        if let fastest = splits.min(by: { $0.duration < $1.duration }) {
            if isCycling(workout.workoutActivityType) {
                out.append(WorkoutStat(label: "Schnellster km", value: format(fastest.averageSpeedKmh, "km/h", 1), systemImage: "bolt.fill"))
            } else {
                out.append(WorkoutStat(label: "Schnellster km", value: paceText(fastest.paceSecondsPerKm), systemImage: "bolt.fill"))
            }
        }

        if let heartRate {
            out.append(WorkoutStat(label: "Ø Puls", value: "\(Int(heartRate.average.rounded())) bpm", systemImage: "heart.fill"))
            out.append(WorkoutStat(label: "Max Puls", value: "\(Int(heartRate.maximum.rounded())) bpm", systemImage: "heart.fill"))
            out.append(WorkoutStat(label: "Min Puls", value: "\(Int(heartRate.minimum.rounded())) bpm", systemImage: "heart"))
        }
        return out
    }

    private static func heartRateSummary(from workout: HKWorkout) -> HeartRateSummary? {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        guard let hr = workout.statistics(for: HKQuantityType(.heartRate)),
              let avg = hr.averageQuantity()?.doubleValue(for: bpm) else {
            return nil
        }
        let minValue = hr.minimumQuantity()?.doubleValue(for: bpm) ?? avg
        let maxValue = hr.maximumQuantity()?.doubleValue(for: bpm) ?? avg
        return HeartRateSummary(average: avg,
                                minimum: minValue,
                                maximum: maxValue,
                                samples: [])
    }

    private static func combinedHeartRate(preferred: HeartRateSummary?,
                                          samples: HeartRateSummary?) -> HeartRateSummary? {
        guard let preferred else { return samples }
        return HeartRateSummary(average: preferred.average,
                                minimum: preferred.minimum,
                                maximum: preferred.maximum,
                                samples: samples?.samples ?? preferred.samples)
    }

    private static func workoutDistanceKm(from workout: HKWorkout) -> Double? {
        let distanceIDs: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning,
                                                       .distanceCycling,
                                                       .distanceSwimming]
        for id in distanceIDs {
            if let meters = workout.statistics(for: HKQuantityType(id))?
                .sumQuantity()?.doubleValue(for: .meter()),
               meters > 0 {
                return meters / 1000
            }
        }
        return nil
    }

    private static func isRunningOrWalking(_ type: HKWorkoutActivityType) -> Bool {
        switch type {
        case .running, .walking, .hiking:
            return true
        default:
            return false
        }
    }

    private static func isCycling(_ type: HKWorkoutActivityType) -> Bool {
        type == .cycling
    }

    private static func activityType(for sport: String) -> HKWorkoutActivityType {
        let lower = sport.lowercased()
        if lower.contains("lauf") || lower.contains("run") { return .running }
        if lower.contains("rad") || lower.contains("bike") || lower.contains("cycle") { return .cycling }
        if lower.contains("kraft") || lower.contains("strength") { return .traditionalStrengthTraining }
        if lower.contains("squash") { return .squash }
        if lower.contains("boulder") || lower.contains("kletter") || lower.contains("climb") { return .climbing }
        return .other
    }

    private static func distanceType(for sport: String) -> HKQuantityType? {
        let lower = sport.lowercased()
        if lower.contains("rad") || lower.contains("bike") || lower.contains("cycle") {
            return HKQuantityType(.distanceCycling)
        }
        if lower.contains("lauf") || lower.contains("run") || lower.contains("geh") || lower.contains("walk") {
            return HKQuantityType(.distanceWalkingRunning)
        }
        return nil
    }

    private static func isWritingEnabled(for distanceType: HKQuantityType) -> Bool {
        switch distanceType.identifier {
        case HKQuantityTypeIdentifier.distanceCycling.rawValue:
            return HealthDataSourceSettings.isWritingEnabled(
                forKey: HealthDataSourceSettings.writeCyclingDistanceKey
            )
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return HealthDataSourceSettings.isWritingEnabled(
                forKey: HealthDataSourceSettings.writeWalkingDistanceKey
            )
        default:
            return true
        }
    }

    private static func paceText(_ secondsPerKm: TimeInterval) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "-" }
        let total = Int(secondsPerKm.rounded())
        return "\(total / 60):" + String(format: "%02d /km", total % 60)
    }

    /// Runden je Kilometer – oder je Meile, wenn imperial eingestellt ist.
    ///
    /// Die Schrittweite aendert nur, wo eine Runde endet. Die Felder von
    /// `WorkoutSplit` bleiben metrisch definiert (`paceSecondsPerKm` sind immer
    /// Sekunden pro Kilometer), damit die Anzeigeschicht genau einmal umrechnet.
    /// Nicht privat: Die Ausleseschicht baut daraus dieselben Splits aus der
    /// Strecke, die in der Datenbank steht.
    static func splits(from route: [RoutePoint]) -> [WorkoutSplit] {
        guard route.count > 1 else { return [] }
        let stepMeters = WorkoutUnits.isImperial ? 1609.344 : 1000.0
        let stepKm = stepMeters / 1000

        var out: [WorkoutSplit] = []
        var lapStart = route[0]
        var previous = route[0]
        var accumulatedMeters = 0.0
        var nextMark = stepMeters

        for point in route.dropFirst() {
            let a = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let b = CLLocation(latitude: point.latitude, longitude: point.longitude)
            accumulatedMeters += a.distance(from: b)
            previous = point

            if accumulatedMeters >= nextMark,
               let startTime = lapStart.timestamp,
               let endTime = point.timestamp {
                let duration = max(endTime.timeIntervalSince(startTime), 1)
                out.append(WorkoutSplit(id: out.count + 1,
                                        distanceKm: nextMark / 1000,
                                        duration: duration,
                                        averageSpeedKmh: stepKm / (duration / 3600),
                                        paceSecondsPerKm: duration / stepKm,
                                        start: startTime,
                                        end: endTime))
                lapStart = point
                nextMark += stepMeters
            }
        }
        return out
    }

    private static func format(_ value: Double, _ symbol: String, _ digits: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = digits
        let s = nf.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
        return symbol.isEmpty ? s : "\(s) \(symbol)"
    }

    /// Liest die GPS-Route eines Workouts als Liste von Koordinaten.
    private func fetchRoute(for workout: HKWorkout) async throws -> [RoutePoint] {
        let store = healthStore
        let predicate = HKQuery.predicateForObjects(from: workout)

        // 1) Routen-Sample(s) des Workouts laden.
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }
        log.info("Routen-Samples gefunden: \(routes.count, privacy: .public)")
        guard let route = routes.first else { return [] }

        // 2) Die einzelnen Orte der Route streamen.
        return try await withCheckedThrowingContinuation { continuation in
            var points: [RoutePoint] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                if let locations {
                    points.append(contentsOf: locations.map {
                        RoutePoint(latitude: $0.coordinate.latitude,
                                   longitude: $0.coordinate.longitude,
                                   elevation: $0.verticalAccuracy >= 0 ? $0.altitude : nil,
                                   timestamp: $0.timestamp)
                    })
                }
                if done {
                    continuation.resume(returning: points)
                }
            }
            store.execute(query)
        }
    }
}
