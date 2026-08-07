//
//  WorkoutRecordCacheStore.swift
//  Healthpit
//
//  Persistenter Cache fuer berechnete Rekorde. Die Rekordseite darf beim
//  Oeffnen nur diesen Snapshot lesen, nicht die gesamte Workout-Historie.
//

import Foundation
import SwiftUI

private struct CachedWorkoutRecord: Codable {
    let id: String
    let sport: String
    let title: String
    let subtitle: String
    let value: String
    let symbol: String
    let tintName: String
    let workoutID: String
    let date: Date
    let priority: Int

    init(_ record: WorkoutRecord) {
        id = record.id
        sport = record.sport
        title = record.title
        subtitle = record.subtitle
        value = record.value
        symbol = record.symbol
        tintName = Self.tintName(for: record)
        workoutID = record.workoutID
        date = record.date
        priority = record.priority
    }

    var record: WorkoutRecord {
        WorkoutRecord(id: id,
                      sport: sport,
                      title: title,
                      subtitle: subtitle,
                      value: value,
                      symbol: symbol,
                      tint: Self.tint(for: tintName),
                      workoutID: workoutID,
                      date: date,
                      priority: priority)
    }

    private static func tintName(for record: WorkoutRecord) -> String {
        switch record.symbol {
        case "clock.fill", "list.number": return "blue"
        case "flame.fill": return "orange"
        case "scalemass.fill", "dumbbell.fill": return "green"
        default:
            return record.priority == 0 || record.priority == 1 ? "red" : "orange"
        }
    }

    private static func tint(for name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        default: return .orange
        }
    }
}

actor WorkoutRecordCacheStore {
    static let shared = WorkoutRecordCacheStore()

    private let key = "workout.records.snapshot"

    private init() {}

    func load() async -> [WorkoutRecord] {
        let cached = await HealthPitDatabase.shared.load([CachedWorkoutRecord].self, key: key) ?? []
        return cached.map(\.record).sorted {
            if $0.date == $1.date { return $0.priority < $1.priority }
            return $0.date > $1.date
        }
    }

    func save(_ records: [WorkoutRecord]) async {
        await HealthPitDatabase.shared.save(records.map(CachedWorkoutRecord.init), key: key)
    }
}
