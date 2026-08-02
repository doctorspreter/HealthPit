//
//  WorkoutDetail.swift
//  Healthpit
//
//  Detaildaten zu einem einzelnen Workout: alle verfügbaren Kennzahlen
//  (Distanz, Kalorien, Puls Ø/Max/Min, Schritte …) plus die GPS-Route.
//

import Foundation

/// Eine einzelne Kennzahl eines Workouts (Label + fertig formatierter Wert).
struct WorkoutStat: Identifiable, Hashable, Sendable {
    let id = UUID()
    let label: String
    let value: String
    let systemImage: String

    var localizedLabel: String { L10n.string(label) }
}

/// Ein Routenpunkt (Sendable-Ersatz für CLLocationCoordinate2D, das nicht
/// Sendable ist – wird in der View in CLLocationCoordinate2D umgewandelt).
struct RoutePoint: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let timestamp: Date?
}

struct WorkoutSplit: Identifiable, Hashable, Sendable {
    let id: Int
    let distanceKm: Double
    let duration: TimeInterval
    let averageSpeedKmh: Double
    let paceSecondsPerKm: TimeInterval
    let start: Date?
    let end: Date?
}

struct HeartRatePoint: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date: Date
    let bpm: Double
}

struct HeartRateSummary: Hashable, Sendable {
    let average: Double
    let minimum: Double
    let maximum: Double
    let samples: [HeartRatePoint]
}

/// Gesamtes Detailpaket für die Workout-Detailansicht.
struct WorkoutDetail: Sendable {
    let stats: [WorkoutStat]
    let route: [RoutePoint]
    let splits: [WorkoutSplit]
    let heartRate: HeartRateSummary?
}

extension String {
    var normalizedWorkoutStatLabel: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "Ø", with: "ø")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
