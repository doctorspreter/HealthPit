//
//  WorkoutDetailIngest.swift
//  Healthpit
//
//  Strecke und Pulskurve eines Trainings — in die Datenbank, wie alles andere.
//
//  Bisher las die Detailansicht sie bei jedem Oeffnen unmittelbar aus
//  HealthKit. Meine Begruendung dafuer war, Rohserien mit tausenden Punkten
//  gehoerten nicht in die Datenbank. Das war keine Begruendung, sondern eine
//  Behauptung: Der Katalog fuehrt `WRK_ROUTE` seit dem Umbau, genau dafuer.
//
//  Was wirklich dagegen sprach, ist die Menge — jede Sekunde ein Punkt, ueber
//  Jahre. Also nicht alles auf einmal, sondern beim ersten Oeffnen: Wer ein
//  Training ansieht, hat es danach vollstaendig in der Datenbank. Was niemand
//  ansieht, kostet auch nichts.
//

import Foundation

/// Die Strecke, wie sie in der Datenbank steht.
struct StoredRoutePoint: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let timestamp: Date?
}

/// Ein Punkt der Pulskurve.
struct StoredHeartRatePoint: Codable, Sendable {
    let date: Date
    let bpm: Double
}

enum WorkoutDetailIngest {

    static let routeMetric: MetricID = "WRK_ROUTE"
    static let heartRateMetric: MetricID = "WRK_HEART_RATE_SERIES"

    /// Was zu einem Training bereits in der Datenbank steht.
    ///
    /// `nil` heisst „noch nie geholt". Eine leere Strecke ist etwas anderes:
    /// Ein Krafttraining hat keine, und danach noch einmal HealthKit zu fragen
    /// waere jedes Mal vergeblich.
    static func stored(for workoutID: WorkoutID,
                       in store: HealthPitStore) async -> (route: [RoutePoint],
                                                           heartRate: [HeartRatePoint])? {
        guard let observations = try? await store.observations(workoutID: workoutID) else { return nil }
        guard let routeValue = observations.first(where: { $0.metricID == routeMetric }) else {
            return nil
        }
        let route = decode([StoredRoutePoint].self, from: routeValue.valueText) ?? []
        let series = observations.first(where: { $0.metricID == heartRateMetric })
        let heartRate = decode([StoredHeartRatePoint].self, from: series?.valueText) ?? []
        return (route.map { RoutePoint(latitude: $0.latitude,
                                       longitude: $0.longitude,
                                       elevation: $0.elevation,
                                       timestamp: $0.timestamp) },
                heartRate.map { HeartRatePoint(date: $0.date, bpm: $0.bpm) })
    }

    /// Legt Strecke und Pulskurve ab.
    static func save(route: [RoutePoint],
                     heartRate: [HeartRatePoint],
                     for workout: StoredWorkout,
                     in store: HealthPitStore) async {
        var incoming: [IncomingObservation] = []
        if let text = encode(route.map {
            StoredRoutePoint(latitude: $0.latitude,
                             longitude: $0.longitude,
                             elevation: $0.elevation,
                             timestamp: $0.timestamp)
        }) {
            incoming.append(observation(routeMetric, text: text, workout: workout,
                                        sourceMetric: "workout.route"))
        }
        if !heartRate.isEmpty,
           let text = encode(heartRate.map { StoredHeartRatePoint(date: $0.date, bpm: $0.bpm) }) {
            incoming.append(observation(heartRateMetric, text: text, workout: workout,
                                        sourceMetric: "workout.heart_rate_series"))
        }
        guard !incoming.isEmpty else { return }
        _ = try? await ImportPipeline(store: store).import(incoming, from: .appleHealth)
    }

    /// Aus Strecke und Pulskurve wieder ein Detail bauen.
    ///
    /// Die Kennzahlen kommen aus dem Training selbst, nicht mehr aus den
    /// Statistiken des HealthKit-Objekts: Dauer, Strecke und Energie stehen in
    /// der Datenbank, alles Weitere ist eine Rechnung darueber.
    static func detail(route: [RoutePoint],
                       heartRate: [HeartRatePoint],
                       summary: WorkoutSummary) -> WorkoutDetail {
        let splits = HealthKitManager.splits(from: route)
        var pulse: HeartRateSummary?
        if !heartRate.isEmpty {
            let values = heartRate.map(\.bpm)
            pulse = HeartRateSummary(average: values.reduce(0, +) / Double(values.count),
                                     minimum: values.min() ?? 0,
                                     maximum: values.max() ?? 0,
                                     samples: heartRate)
        }
        return WorkoutDetail(stats: stats(for: summary, heartRate: pulse),
                             route: route,
                             splits: splits,
                             heartRate: pulse)
    }

    private static func stats(for summary: WorkoutSummary,
                              heartRate: HeartRateSummary?) -> [WorkoutStat] {
        var out: [WorkoutStat] = [
            WorkoutStat(label: "Dauer",
                        value: formatWorkoutDuration(summary.duration),
                        systemImage: "clock")
        ]
        if let distance = summary.distanceKm, distance > 0 {
            out.append(WorkoutStat(label: "Distanz",
                                   value: String(format: "%.2f km", distance),
                                   systemImage: "figure.walk"))
            if summary.duration > 0 {
                let speed = distance / (summary.duration / 3600)
                out.append(WorkoutStat(label: "Ø Tempo",
                                       value: String(format: "%.1f km/h", speed),
                                       systemImage: "speedometer"))
            }
        }
        if let energy = summary.energyKcal, energy > 0 {
            out.append(WorkoutStat(label: "Aktive Kalorien",
                                   value: String(format: "%.0f kcal", energy),
                                   systemImage: "flame.fill"))
        }
        if let heartRate {
            out.append(WorkoutStat(label: "Ø Puls",
                                   value: String(format: "%.0f bpm", heartRate.average),
                                   systemImage: "heart.fill"))
            out.append(WorkoutStat(label: "Max. Puls",
                                   value: String(format: "%.0f bpm", heartRate.maximum),
                                   systemImage: "heart.circle"))
        }
        return out
    }

    private static func observation(_ metricID: MetricID,
                                    text: String,
                                    workout: StoredWorkout,
                                    sourceMetric: String) -> IncomingObservation {
        IncomingObservation(sourceMetric: sourceMetric,
                            metricID: metricID,
                            valueText: text,
                            startTime: workout.startTime,
                            endTime: workout.endTime,
                            aggregation: .raw,
                            periodType: .workout,
                            originProvider: workout.originProvider,
                            workoutID: workout.workoutID,
                            metadata: ["source": "apple_health"])
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from text: String?) -> T? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
