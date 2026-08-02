//
//  HevyFitnessSummary.swift
//  Healthpit
//
//  Zusammenfassung der Krafttrainingsdaten aus der Bridge.
//

import Foundation

nonisolated struct HevyFitnessSummary: Codable, Sendable {
    let enabled: Bool
    let lastSync: String?
    let totalWorkouts: Int
    let totalSets: Int
    let totalVolumeKg: Double
    let recentWorkouts: [HevyWorkoutSummary]
    let exercises: [HevyExerciseSummary]

    enum CodingKeys: String, CodingKey {
        case enabled
        case lastSync = "last_sync"
        case totalWorkouts = "total_workouts"
        case totalSets = "total_sets"
        case totalVolumeKg = "total_volume_kg"
        case recentWorkouts = "recent_workouts"
        case exercises
    }
}

nonisolated struct HevyWorkoutSummary: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startTime: String
    let setCount: Int
    let exerciseCount: Int
    let volumeKg: Double
    let exercises: [HevyWorkoutExercise]

    enum CodingKeys: String, CodingKey {
        case id, title
        case startTime = "start_time"
        case setCount = "set_count"
        case exerciseCount = "exercise_count"
        case volumeKg = "volume_kg"
        case exercises
    }
}

nonisolated struct HevyWorkoutExercise: Codable, Identifiable, Sendable {
    let exerciseID: String
    let title: String
    let setCount: Int
    let bestWeightKg: Double?
    let lastWeightKg: Double?
    let volumeKg: Double
    let sets: [HevySetSummary]

    var id: String { exerciseID }

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case title
        case setCount = "set_count"
        case bestWeightKg = "best_weight_kg"
        case lastWeightKg = "last_weight_kg"
        case volumeKg = "volume_kg"
        case sets
    }
}

nonisolated struct HevySetSummary: Codable, Identifiable, Sendable {
    let setIndex: Int
    let setType: String?
    let weightKg: Double?
    let reps: Double?
    let rpe: Double?
    let distanceMeters: Double?
    let durationSeconds: Double?

    var id: Int { setIndex }

    enum CodingKeys: String, CodingKey {
        case setIndex = "set_index"
        case setType = "set_type"
        case weightKg = "weight_kg"
        case reps
        case rpe
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
    }
}

nonisolated struct HevyExerciseSummary: Codable, Identifiable, Sendable {
    let exerciseID: String
    let title: String
    let setCount: Int
    let workoutCount: Int
    let bestWeightKg: Double?
    let lastWeightKg: Double?
    let totalVolumeKg: Double
    let lastWorkoutAt: String?
    let trend: [HevyExerciseTrendPoint]

    var id: String { exerciseID }

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case title
        case setCount = "set_count"
        case workoutCount = "workout_count"
        case bestWeightKg = "best_weight_kg"
        case lastWeightKg = "last_weight_kg"
        case totalVolumeKg = "total_volume_kg"
        case lastWorkoutAt = "last_workout_at"
        case trend
    }
}

nonisolated struct HevyExerciseTrendPoint: Codable, Identifiable, Sendable {
    let day: String
    let weightKg: Double?
    let sets: Int
    let volumeKg: Double

    var id: String { day }

    enum CodingKeys: String, CodingKey {
        case day, sets
        case weightKg = "weight_kg"
        case volumeKg = "volume_kg"
    }
}
