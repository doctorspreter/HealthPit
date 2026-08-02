//
//  LocalWorkout.swift
//  Healthpit
//
//  Lokal auf dem iPhone gespeicherte importierte oder manuelle Trainings.
//

import Foundation

struct WorkoutWeather: Hashable, Codable, Sendable {
    var condition: String?
    var temperatureCelsius: Double?
    var humidityPercent: Double?

    nonisolated var summary: String {
        var parts: [String] = []
        if let condition, !condition.isEmpty { parts.append(L10n.string(condition)) }
        if let temperatureCelsius { parts.append("\(Int(temperatureCelsius.rounded())) °C") }
        if let humidityPercent { parts.append("\(Int(humidityPercent.rounded())) %") }
        return parts.joined(separator: " · ")
    }
}

struct WorkoutInjury: Hashable, Codable, Sendable {
    var location: String
    var painType: String
    var severity: Int

    nonisolated var summary: String {
        "\(L10n.string(location)) · \(L10n.string(painType)) · \(severity)/10"
    }

    nonisolated var isEmpty: Bool {
        location.isEmpty && painType.isEmpty && severity <= 0
    }
}

struct LocalWorkout: Identifiable, Codable, Sendable {
    enum Source: String, Codable, Sendable {
        case manual
        case appleHealth = "apple_health"
        case gpx
        case tcx
        case garmin
        case gympit

        nonisolated var displayName: String {
            switch self {
            case .manual: return L10n.string("Manuell")
            case .appleHealth: return L10n.string("Apple Health")
            case .gpx: return "GPX"
            case .tcx: return "TCX"
            case .garmin: return "Garmin"
            case .gympit: return "Gympit"
            }
        }
    }

    let id: UUID
    var source: Source
    var sport: String
    var title: String
    var start: Date
    var end: Date
    var distanceKm: Double?
    var energyKcal: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var notes: String
    var weather: WorkoutWeather?
    var injury: WorkoutInjury?
    var route: [LocalRoutePoint]
    var exercises: [LocalStrengthExercise]

    nonisolated var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }

    init(id: UUID,
         source: Source,
         sport: String,
         title: String,
         start: Date,
         end: Date,
         distanceKm: Double?,
         energyKcal: Double?,
         averageHeartRate: Double?,
         maxHeartRate: Double?,
         notes: String,
         weather: WorkoutWeather?,
         injury: WorkoutInjury?,
         route: [LocalRoutePoint],
         exercises: [LocalStrengthExercise] = []) {
        self.id = id
        self.source = source
        self.sport = sport
        self.title = title
        self.start = start
        self.end = end
        self.distanceKm = distanceKm
        self.energyKcal = energyKcal
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.notes = notes
        self.weather = weather
        self.injury = injury
        self.route = route
        self.exercises = exercises
    }

    enum CodingKeys: String, CodingKey {
        case id, source, sport, title, start, end, distanceKm, energyKcal
        case averageHeartRate, maxHeartRate, notes, weather, injury, route, exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decode(Source.self, forKey: .source)
        sport = try container.decode(String.self, forKey: .sport)
        title = try container.decode(String.self, forKey: .title)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm)
        energyKcal = try container.decodeIfPresent(Double.self, forKey: .energyKcal)
        averageHeartRate = try container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        maxHeartRate = try container.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        notes = try container.decode(String.self, forKey: .notes)
        weather = try container.decodeIfPresent(WorkoutWeather.self, forKey: .weather)
        injury = try container.decodeIfPresent(WorkoutInjury.self, forKey: .injury)
        route = try container.decodeIfPresent([LocalRoutePoint].self, forKey: .route) ?? []
        exercises = try container.decodeIfPresent([LocalStrengthExercise].self, forKey: .exercises) ?? []
    }
}

struct LocalRoutePoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var timestamp: Date?
    var heartRate: Double?
}

struct LocalStrengthExercise: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var catalogID: String
    var name: String
    var category: String
    var start: Date?
    var end: Date?
    var durationSeconds: Double?
    var notes: String
    var deviceSettings: [String: String]
    var sets: [LocalStrengthSet]

    enum CodingKeys: String, CodingKey {
        case id
        case catalogID = "catalog_id"
        case name
        case category
        case start
        case end
        case durationSeconds = "duration_seconds"
        case notes
        case deviceSettings = "device_settings"
        case sets
    }
}

struct LocalStrengthSet: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var index: Int
    var type: String
    var reps: Double?
    var weightKg: Double?
    var rpe: Double?
    var volumeKg: Double?
    var isPersonalRecord: Bool

    enum CodingKeys: String, CodingKey {
        case id, index, type, reps, rpe
        case weightKg = "weight_kg"
        case volumeKg = "volume_kg"
        case isPersonalRecord = "is_personal_record"
    }
}
