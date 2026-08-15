//
//  WorkoutRecords.swift
//  Healthpit
//
//  Gemeinsame Rekordlogik fuer Workoutliste, Detailansicht und Rekordseite.
//

import Foundation
import SwiftUI

struct WorkoutRecord: Identifiable, Sendable {
    let id: String
    let sport: String
    let title: String
    let subtitle: String
    let value: String
    let symbol: String
    let tint: Color
    let workoutID: String
    let date: Date
    let priority: Int

    /// Rekorde werden sprachneutral mit deutschen Schluesseln gespeichert.
    /// Dadurch wechseln auch bereits gecachte Rekorde sofort die Anzeigesprache.
    var localizedSport: String { L10n.stringResolvingStoredTranslation(sport) }
    var localizedTitle: String { L10n.string(title) }

    var localizedSubtitle: String {
        guard !id.contains("-exercise-") else { return subtitle }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var localizedValue: String {
        if value.hasSuffix(" Min"),
           let minutes = Int64(value.dropLast(4)) {
            return L10n.format("%lld Min", minutes)
        }

        if value.hasSuffix(" h") {
            let components = value.dropLast(2).split(separator: ":")
            if components.count == 2,
               let hours = Int64(components[0]),
               let minutes = Int64(components[1]) {
                return L10n.format("%lld Std %lld Min", hours, minutes)
            }
        }

        return value
    }
}

enum WorkoutRecordAnalyzer {
    static func records(for workouts: [UnifiedWorkout]) -> [WorkoutRecord] {
        var records: [WorkoutRecord] = []
        let grouped = Dictionary(grouping: workouts) { normalizeSport($0.sportName) }

        for (sport, items) in grouped {
            if let longest = items.filter({ $0.duration > 0 }).max(by: { $0.duration < $1.duration }) {
                records.append(record(type: "duration",
                                      sport: sport,
                                      title: "Längste Dauer",
                                      value: durationText(longest.duration),
                                      item: longest,
                                      symbol: "clock.fill",
                                      tint: .blue))
            }

            if let distance = items.compactMap({ item -> (UnifiedWorkout, Double)? in
                guard let km = item.distanceKm, km > 0.2 else { return nil }
                return (item, km)
            }).max(by: { $0.1 < $1.1 }) {
                records.append(record(type: "distance",
                                      sport: sport,
                                      title: "Längste Distanz",
                                      value: String(format: "%.2f km", distance.1),
                                      item: distance.0,
                                      symbol: "point.topleft.down.curvedto.point.bottomright.up",
                                      tint: .red))
            }

            if let calories = items.compactMap({ item -> (UnifiedWorkout, Double)? in
                guard let kcal = item.energyKcal, kcal > 0 else { return nil }
                return (item, kcal)
            }).max(by: { $0.1 < $1.1 }) {
                records.append(record(type: "energy",
                                      sport: sport,
                                      title: "Meiste Kalorien",
                                      value: "\(Int(calories.1.rounded())) kcal",
                                      item: calories.0,
                                      symbol: "flame.fill",
                                      tint: .orange))
            }

            if isRunningSport(sport) {
                records.append(contentsOf: fastestDistanceRecords(items: items, sport: sport, targetKm: 5))
                records.append(contentsOf: fastestDistanceRecords(items: items, sport: sport, targetKm: 10))
            }

            if sport == "Krafttraining" {
                records.append(contentsOf: strengthRecords(items: items, sport: sport))
            }
        }

        return records.sorted {
            if $0.date == $1.date { return $0.priority < $1.priority }
            return $0.date > $1.date
        }
    }

    private static func strengthRecords(items: [UnifiedWorkout], sport: String) -> [WorkoutRecord] {
        var out: [WorkoutRecord] = []
        if let volume = items.compactMap({ item -> (UnifiedWorkout, Double)? in
            guard let kg = item.volumeKg, kg > 0 else { return nil }
            return (item, kg)
        }).max(by: { $0.1 < $1.1 }) {
            out.append(record(type: "volume",
                              sport: sport,
                              title: "Meistes Volumen",
                              value: formatKg(volume.1),
                              item: volume.0,
                              symbol: "scalemass.fill",
                              tint: .green))
        }

        if let sets = items.compactMap({ item -> (UnifiedWorkout, Int)? in
            guard let count = item.setCount, count > 0 else { return nil }
            return (item, count)
        }).max(by: { $0.1 < $1.1 }) {
            out.append(record(type: "sets",
                              sport: sport,
                              title: "Meiste Sätze",
                              value: "\(sets.1)",
                              item: sets.0,
                              symbol: "list.number",
                              tint: .blue))
        }

        let exerciseCandidates = items.flatMap { item in
            item.strengthExercises.compactMap { exercise -> (UnifiedWorkout, UnifiedStrengthExercise, Double)? in
                guard let kg = exercise.bestWeightKg, kg > 0 else { return nil }
                return (item, exercise, kg)
            }
        }
        let byExercise = Dictionary(grouping: exerciseCandidates) { $0.1.id }
        for (_, values) in byExercise {
            guard let best = values.max(by: { $0.2 < $1.2 }) else { continue }
            out.append(WorkoutRecord(id: "\(best.0.id)-exercise-\(best.1.id)",
                                     sport: sport,
                                     title: "Bestgewicht",
                                     subtitle: best.1.name,
                                     value: formatKg(best.2),
                                     symbol: "dumbbell.fill",
                                     tint: .green,
                                     workoutID: best.0.id,
                                     date: best.0.startDate,
                                     priority: 6))
        }

        return out
    }

    private static func fastestDistanceRecords(items: [UnifiedWorkout], sport: String, targetKm: Double) -> [WorkoutRecord] {
        let tolerance = targetKm == 10 ? 0.5 : 0.25
        guard let best = items.compactMap({ item -> (UnifiedWorkout, Double)? in
            guard let km = item.distanceKm,
                  km >= targetKm - tolerance,
                  km <= targetKm + tolerance,
                  item.duration > 0 else {
                return nil
            }
            return (item, item.duration)
        }).min(by: { $0.1 < $1.1 }) else {
            return []
        }

        return [record(type: "fastest_\(Int(targetKm))k",
                       sport: sport,
                       title: "Schnellste \(Int(targetKm)) km",
                       value: durationText(best.1),
                       item: best.0,
                       symbol: "timer",
                       tint: .red)]
    }

    private static func record(type: String,
                               sport: String,
                               title: String,
                               value: String,
                               item: UnifiedWorkout,
                               symbol: String,
                               tint: Color) -> WorkoutRecord {
        WorkoutRecord(id: "\(item.id)-\(type)",
                      sport: sport,
                      title: title,
                      subtitle: item.startDate.formatted(.dateTime.day().month().year()),
                      value: value,
                      symbol: symbol,
                      tint: tint,
                      workoutID: item.id,
                      date: item.startDate,
                      priority: priority(for: type))
    }

    private static func priority(for type: String) -> Int {
        if type.hasPrefix("fastest") { return 0 }
        switch type {
        case "distance": return 1
        case "duration": return 2
        case "energy": return 3
        case "volume": return 4
        case "sets": return 5
        default: return 9
        }
    }

    private static func normalizeSport(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("kraft") || lower.contains("strength") { return "Krafttraining" }
        if lower.contains("lauf") || lower.contains("run") { return "Laufen" }
        if lower.contains("rad") || lower.contains("cycle") || lower.contains("bike") { return "Radfahren" }
        if lower.contains("squash") { return "Squash" }
        if lower.contains("boulder") || lower.contains("kletter") || lower.contains("climb") { return "Bouldern" }
        return value.isEmpty ? "Workout" : value
    }

    private static func isRunningSport(_ sport: String) -> Bool {
        sport == "Laufen"
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60):" + String(format: "%02d h", minutes % 60)
        }
        return "\(minutes) Min"
    }
}
