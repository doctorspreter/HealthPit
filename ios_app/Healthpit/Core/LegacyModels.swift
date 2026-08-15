//
//  LegacyModels.swift
//  HealthPitCore
//
//  Spiegel der heutigen HealthPit-Datenstrukturen, so wie sie auf der Platte
//  liegen: `LocalWorkouts/workouts.json` und die JSON-Bloecke in der Tabelle
//  `cache_entries`.
//
//  Bewusst eigene Typen statt der App-Modelle: Die Migration muss das lesen
//  koennen, was frueher geschrieben wurde – auch dann noch, wenn die
//  App-Modelle sich weiterentwickeln. Und sie muss ohne HealthKit testbar
//  bleiben.
//

import Foundation

enum LegacyDecoder {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// `LocalWorkout` aus `Application Support/LocalWorkouts/workouts.json`.
///
/// Auch `Encodable`, damit die Migration den Originaldatensatz unveraendert
/// als `raw_payload` mitnehmen kann.
struct LegacyLocalWorkout: Codable {
    var id: UUID
    /// `manual`, `apple_health`, `gpx`, `tcx`, `gympit` – aeltere Dateien
    /// koennen `garmin` enthalten.
    var source: String
    var sport: String
    var title: String
    var start: Date
    var end: Date
    var distanceKm: Double?
    var energyKcal: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var notes: String?
    var weather: LegacyWeather?
    var injury: LegacyInjury?
    var route: [LegacyRoutePoint]?
    var exercises: [LegacyExercise]?

    struct LegacyWeather: Codable {
        var condition: String?
        var temperatureCelsius: Double?
        var humidityPercent: Double?
    }

    struct LegacyInjury: Codable {
        var location: String?
        var painType: String?
        var severity: Int?
    }

    struct LegacyRoutePoint: Codable {
        var latitude: Double
        var longitude: Double
        var elevation: Double?
        var timestamp: Date?
        var heartRate: Double?
    }

    struct LegacyExercise: Codable {
        var id: String?
        var catalogID: String?
        var name: String?
        var category: String?
        var start: Date?
        var end: Date?
        var durationSeconds: Double?
        var notes: String?
        var sets: [LegacySet]?

        enum CodingKeys: String, CodingKey {
            case id, name, category, start, end, notes, sets
            case catalogID = "catalog_id"
            case durationSeconds = "duration_seconds"
        }
    }

    struct LegacySet: Codable {
        var id: String?
        var index: Int?
        var type: String?
        var reps: Double?
        var weightKg: Double?
        var rpe: Double?
        var volumeKg: Double?
        var isPersonalRecord: Bool?

        enum CodingKeys: String, CodingKey {
            case id, index, type, reps, rpe
            case weightKg = "weight_kg"
            case volumeKg = "volume_kg"
            case isPersonalRecord = "is_personal_record"
        }
    }
}

/// `WorkoutSummary` aus den `health_workouts.*`-Cacheeintraegen.
struct LegacyWorkoutSummary: Decodable {
    var id: UUID
    /// UUID des HKWorkout.
    var uuid: UUID
    var externalWorkoutID: String?
    var activityName: String
    var symbol: String?
    var sourceName: String?
    var start: Date
    var end: Date
    var duration: Double
    var energyKcal: Double?
    var distanceKm: Double?
}

/// `SleepSession` aus den `sleep_sessions.*`-Cacheeintraegen.
struct LegacySleepSession: Decodable {
    var id: UUID
    var start: Date
    var end: Date
    var inBed: Double
    var segments: [LegacySleepSegment]
}

struct LegacySleepSegment: Decodable {
    var id: UUID
    /// `deep`, `core`, `rem`, `awake`.
    var stage: String
    var start: Date
    var end: Date
}

/// `DashboardMetricCacheEntry` aus `dashboard.metric.values`.
struct LegacyDashboardMetricEntry: Decodable {
    /// Bisheriger Metrikschluessel = HealthKit-Identifier.
    var metricID: String
    var value: Double
    var updatedAt: Date
    var measuredAt: Date?
}
