//
//  StoredWorkout.swift
//  HealthPitCore
//
//  Ein Workout ist mehr als ein Messwert: es klammert viele Observations
//  zusammen. Deshalb eine eigene Entitaet mit eigener ID – die Messwerte
//  zeigen ueber `workout_id` darauf.
//

import Foundation

struct StoredWorkout: Hashable, Sendable, Codable, Identifiable {
    var id: WorkoutID { workoutID }

    let workoutID: WorkoutID
    var userID: String
    /// Neutraler Sportart-Code (`RUNNING`, `CYCLING`, `STRENGTH_TRAINING` …).
    /// Der Adapter uebersetzt die Bezeichnung des Anbieters.
    var sportType: String
    var title: String?
    var notes: String?

    var startTime: Date
    var endTime: Date
    var timezone: String?

    var originProvider: ProviderCode
    var ingestProvider: ProviderCode
    var sourceRecordID: String?
    var sourceAppID: String?
    var sourceDeviceID: String?
    var sourceDeviceModel: String?

    var version: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var metadata: [String: String]
    var rawPayload: String?

    init(workoutID: WorkoutID = .generate(),
         userID: String = HealthPitUser.local,
         sportType: String,
         title: String? = nil,
         notes: String? = nil,
         startTime: Date,
         endTime: Date,
         timezone: String? = TimeZone.current.identifier,
         originProvider: ProviderCode,
         ingestProvider: ProviderCode,
         sourceRecordID: String? = nil,
         sourceAppID: String? = nil,
         sourceDeviceID: String? = nil,
         sourceDeviceModel: String? = nil,
         version: Int = 1,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         deletedAt: Date? = nil,
         metadata: [String: String] = [:],
         rawPayload: String? = nil) {
        self.workoutID = workoutID
        self.userID = userID
        self.sportType = sportType
        self.title = title
        self.notes = notes
        self.startTime = startTime
        self.endTime = endTime
        self.timezone = timezone
        self.originProvider = originProvider
        self.ingestProvider = ingestProvider
        self.sourceRecordID = sourceRecordID
        self.sourceAppID = sourceAppID
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceModel = sourceDeviceModel
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.metadata = metadata
        self.rawPayload = rawPayload
    }

    var duration: TimeInterval { max(endTime.timeIntervalSince(startTime), 0) }
    var isDeleted: Bool { deletedAt != nil }

    var contentHash: String {
        ContentHash.of([
            sportType,
            title ?? "-",
            String(format: "%.3f", startTime.timeIntervalSince1970),
            String(format: "%.3f", endTime.timeIntervalSince1970),
            originProvider.rawValue,
            sourceRecordID ?? "-",
            sourceDeviceID ?? "-",
            deletedAt == nil ? "live" : "deleted"
        ].joined(separator: "|"))
    }
}
