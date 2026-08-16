//
//  HealthQuery.swift
//  Healthpit
//
//  Die Ausleseschicht: Bildschirme fragen hier, nirgends sonst.
//
//  Geliefert werden die Modelltypen, die die App ohnehin darstellt
//  (`DailyStatistic`, `SleepSession`, `LatestMetricValue`). Dadurch aendert
//  sich in den Ansichten nur, woher die Werte kommen – nicht, wie sie
//  aussehen. Der Weg dorthin ist neu, das Ergebnis vertraut.
//
//  Zwei Regeln:
//
//  1. Gelesen wird aus der Datenbank. Kein Griff nach HealthKit, kein
//     Zwischenspeicher daneben. Was hier nicht steht, ist nicht da – und das
//     ist eine Aussage, die man pruefen kann.
//  2. Liegt derselbe Wert von mehreren Quellen vor, entscheidet die
//     Quellenfreigabe, welche gilt. Zusammengerechnet wird nichts: Zwei
//     Aufzeichnungen derselben Nacht sind zwei Aufzeichnungen, keine
//     doppelte Nacht.
//

import Foundation

@MainActor
final class HealthQuery {
    static let shared = HealthQuery()

    private init() {}

    private func store() async throws -> HealthPitStore {
        try await HealthPitData.shared.store()
    }

    // MARK: - Kennzahlen

    /// Der zuletzt gemessene Wert einer Metrik.
    func latestValue(for metric: HealthMetric) async -> LatestMetricValue? {
        guard let metricID = Self.metricID(for: metric),
              let store = try? await store(),
              let observations = try? await store.observations(metricID: metricID,
                                                               from: nil, to: nil) else {
            return nil
        }
        let allowed = await filtered(observations, metricID: metricID, store: store)
        guard let latest = allowed.max(by: { $0.startTime < $1.startTime }),
              let value = latest.valueNumeric else { return nil }
        return LatestMetricValue(value: Self.display(value, of: latest, for: metric),
                                 date: latest.endTime)
    }

    /// Tageswerte einer Metrik als Datenpunkte fuer Diagramme.
    func dailyValues(for metric: HealthMetric,
                     in interval: DateInterval) async -> [DailyStatistic] {
        guard let metricID = Self.metricID(for: metric),
              let store = try? await store(),
              let observations = try? await store.observations(metricID: metricID,
                                                               from: interval.start,
                                                               to: interval.end) else {
            return []
        }
        let allowed = await filtered(observations, metricID: metricID, store: store)
            .filter { $0.periodType == .day }

        // Je Tag genau ein Punkt. Liegen mehrere Quellen vor, gilt die mit den
        // meisten Beobachtungen dahinter – nicht deren Summe.
        var byDay: [Date: HealthObservation] = [:]
        let calendar = Calendar.healthApp
        for observation in allowed {
            let day = calendar.startOfDay(for: observation.startTime)
            if let existing = byDay[day], existing.updatedAt >= observation.updatedAt { continue }
            byDay[day] = observation
        }

        return byDay.compactMap { day, observation -> DailyStatistic? in
            guard let value = observation.valueNumeric else { return nil }
            return DailyStatistic(date: day, value: Self.display(value, of: observation, for: metric))
        }
        .sorted { $0.date < $1.date }
    }

    /// Die Kennzahlen der Startseite: je Metrik der zuletzt gemessene Wert.
    func headlineValues(for metrics: [HealthMetric]) async -> [String: DashboardMetricCacheEntry] {
        var result: [String: DashboardMetricCacheEntry] = [:]
        for metric in metrics {
            guard let latest = await latestValue(for: metric) else { continue }
            result[metric.id] = DashboardMetricCacheEntry(metricID: metric.id,
                                                          value: latest.value,
                                                          updatedAt: Date(),
                                                          measuredAt: latest.date)
        }
        return result
    }

    // MARK: - Trainings

    /// Trainings eines Zeitraums, neueste zuerst.
    func workouts(in interval: DateInterval? = nil) async -> [WorkoutSummary] {
        guard let store = try? await store(),
              let stored = try? await store.workouts(from: interval?.start, to: interval?.end) else {
            return []
        }
        var summaries: [WorkoutSummary] = []
        for workout in stored {
            let values = (try? await store.observations(workoutID: workout.workoutID)) ?? []
            summaries.append(Self.summary(workout, values: values))
        }
        return summaries.sorted { $0.start > $1.start }
    }

    /// Trainings fuer die Liste – ein Eintrag je Zeile der Datenbank.
    ///
    /// Frueher fuehrten die Listen zwei Bestaende zusammen: Apple Health und
    /// die eigene Datei. Dafuer brauchte es eine Heuristik, die raten musste,
    /// ob zwei Eintraege dasselbe Training sind. In der Datenbank ist das
    /// bereits entschieden – eine GymPit-Einheit, die zusaetzlich ueber Apple
    /// Health hereinkam, ist dort eine Zeile, nicht zwei.
    func unifiedWorkouts(in interval: DateInterval? = nil) async -> [UnifiedWorkout] {
        guard let store = try? await store(),
              let stored = try? await store.workouts(from: interval?.start, to: interval?.end) else {
            return []
        }
        var result: [UnifiedWorkout] = []
        for workout in stored {
            let values = (try? await store.observations(workoutID: workout.workoutID)) ?? []
            result.append(UnifiedWorkout(id: workout.workoutID.rawValue,
                                         health: Self.summary(workout, values: values),
                                         local: ManualWorkoutWriter.local(from: workout)))
        }
        return result.sorted { $0.startDate > $1.startDate }
    }

    /// Ein gespeichertes Training in der Form, die die Listen darstellen.
    static func summary(_ workout: StoredWorkout, values: [HealthObservation]) -> WorkoutSummary {
        func value(_ metricID: MetricID, in unit: UnitCode) -> Double? {
            guard let observation = values.first(where: { $0.metricID == metricID }),
                  let raw = observation.valueNumeric,
                  let stored = observation.unit else { return nil }
            return (try? UnitConverter.convert(raw, from: stored, to: unit)) ?? raw
        }

        let type = SportTypeDisplay.describe(workout.sportType)
        return WorkoutSummary(id: UUID(uuidString: workout.workoutID.rawValue) ?? UUID(),
                              uuid: UUID(uuidString: workout.sourceRecordID ?? "") ?? UUID(),
                              externalWorkoutID: workout.metadata["origin_external_id"],
                              activityName: type.name,
                              sportType: workout.sportType,
                              symbol: type.symbol,
                              sourceName: workout.sourceAppID,
                              start: workout.startTime,
                              end: workout.endTime,
                              duration: workout.duration,
                              energyKcal: value("NRG_ACTIVE", in: .kilocalorie),
                              distanceKm: value("WRK_DISTANCE", in: .kilometer),
                              weather: nil,
                              injury: nil)
    }

    // MARK: - Schlaf

    /// Die Naechte eines Zeitraums, je Nacht die aussagekraeftigste Quelle.
    ///
    /// Zeichnen Uhr und Telefon dieselbe Nacht auf, gilt die Aufzeichnung mit
    /// dem meisten Schlaf – das Telefon meldet oft nur „im Bett“ und wuerde
    /// die Nacht sonst leer erscheinen lassen.
    func nights(in interval: DateInterval) async -> [SleepSession] {
        guard let store = try? await store(),
              let stages = try? await store.observations(metricID: "SLP_STAGE",
                                                         from: interval.start.addingTimeInterval(-SleepNightBuilder.lookBack),
                                                         to: interval.end),
              let durations = try? await store.observations(metricID: "SLP_TIME_IN_BED",
                                                            from: interval.start.addingTimeInterval(-SleepNightBuilder.lookBack),
                                                            to: interval.end) else {
            return []
        }

        let allowedStages = await filtered(stages, metricID: "SLP_STAGE", store: store)
        let inBedBySession = Dictionary(durations.map { ($0.sessionID ?? "", $0.valueNumeric ?? 0) },
                                        uniquingKeysWith: { max($0, $1) })

        // Nach Aufzeichnung gruppieren: Die Session-ID traegt Quelle und
        // Beginn, sie unterscheidet Uhr und Telefon zuverlaessig.
        var bySession: [String: [HealthObservation]] = [:]
        for stage in allowedStages {
            bySession[stage.sessionID ?? stage.observationID.rawValue, default: []].append(stage)
        }

        var sessions: [SleepSession] = []
        for (sessionID, observations) in bySession {
            let segments = observations.compactMap { observation -> SleepSegment? in
                guard let code = observation.valueCode, let stage = Self.stage(code) else { return nil }
                return SleepSegment(stage: stage, start: observation.startTime, end: observation.endTime)
            }
            guard !segments.isEmpty else { continue }
            let start = segments.map(\.start).min() ?? interval.start
            let end = segments.map(\.end).max() ?? interval.end
            guard end >= interval.start, end <= interval.end else { continue }
            sessions.append(SleepSession(start: start,
                                         end: end,
                                         inBed: inBedBySession[sessionID] ?? 0,
                                         segments: segments.sorted { $0.start < $1.start }))
        }

        // Je Nacht die beste Aufzeichnung behalten.
        var byNight: [Date: SleepSession] = [:]
        let calendar = Calendar.healthApp
        for session in sessions {
            let night = calendar.startOfDay(for: session.end)
            if let existing = byNight[night], existing.asleep >= session.asleep { continue }
            byNight[night] = session
        }
        return byNight.values.sorted { $0.end > $1.end }
    }

    // MARK: - Quellenfreigabe

    /// Wirft weg, was der Anwender fuer diese Metrik abgeschaltet hat.
    private func filtered(_ observations: [HealthObservation],
                          metricID: MetricID,
                          store: HealthPitStore) async -> [HealthObservation] {
        guard let policies = try? await store.sourcePolicies(), !policies.isEmpty else {
            return observations
        }
        let disabled = policies.filter { !$0.enabled && $0.metricID == metricID }
        guard !disabled.isEmpty else { return observations }

        return observations.filter { observation in
            !disabled.contains { policy in
                policy.provider == observation.originProvider
                    && (policy.sourceAppID == nil || policy.sourceAppID == observation.sourceAppID)
            }
        }
    }

    // MARK: - Uebersetzung

    /// Welche Metrik der Datenbank steckt hinter dieser Kachel?
    static func metricID(for metric: HealthMetric) -> MetricID? {
        AppleHealthMapping.byIdentifier[metric.id]?.metricID
    }

    /// Der gespeicherte Wert steht in der kanonischen Einheit, die Anzeige
    /// erwartet ihre eigene – Meter zu Kilometer, Anteil zu Prozent.
    static func display(_ value: Double,
                        of observation: HealthObservation,
                        for metric: HealthMetric) -> Double {
        guard let entry = AppleHealthMapping.byIdentifier[metric.id],
              let stored = observation.unit else { return value }
        return (try? UnitConverter.convert(value, from: stored, to: entry.sourceUnit)) ?? value
    }

    static func stage(_ code: String) -> SleepStage? {
        switch code {
        case "DEEP":  return .deep
        case "CORE":  return .core
        case "REM":   return .rem
        case "AWAKE": return .awake
        default:      return nil
        }
    }
}
