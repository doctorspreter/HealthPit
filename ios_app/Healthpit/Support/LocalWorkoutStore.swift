//
//  LocalWorkoutStore.swift
//  Healthpit
//
//  Persistiert importierte/manuelle Workouts lokal auf dem iPhone.
//

import Foundation

actor LocalWorkoutStore {
    static let shared = LocalWorkoutStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL
    private let summaryFileURL: URL
    private var summaryMemoryCache: [LocalWorkout]?

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appending(path: "LocalWorkouts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: "workouts.json")
        summaryFileURL = folder.appending(path: "workout_summaries.json")
    }

    func load() -> [LocalWorkout] {
        guard let data = try? Data(contentsOf: fileURL),
              let workouts = try? decoder.decode([LocalWorkout].self, from: data) else {
            return []
        }
        return deduplicated(workouts).sorted { $0.start > $1.start }
    }

    func loadSummaries() -> [LocalWorkout] {
        if let summaryMemoryCache {
            return summaryMemoryCache
        }
        if let data = try? Data(contentsOf: summaryFileURL),
           let workouts = try? decoder.decode([LocalWorkout].self, from: data) {
            let summaries = deduplicated(workouts).sorted { $0.start > $1.start }
            summaryMemoryCache = summaries
            return summaries
        }
        let full = load()
        persistSummaries(full)
        return summaryMemoryCache ?? []
    }

    func fullWorkout(id: UUID) -> LocalWorkout? {
        load().first { $0.id == id }
    }

    func save(_ workout: LocalWorkout) {
        var workouts = load()
        workouts.removeAll { $0.id == workout.id }
        workouts.append(workout)
        persist(deduplicated(workouts))
    }

    func saveMany(_ incoming: [LocalWorkout]) {
        var workouts = load()
        let ids = Set(incoming.map(\.id))
        workouts.removeAll { ids.contains($0.id) }
        workouts.append(contentsOf: incoming)
        persist(deduplicated(workouts))
    }

    func delete(id: UUID) {
        var workouts = load()
        workouts.removeAll { $0.id == id }
        persist(workouts)
    }

    func deleteAll() {
        persist([])
    }

    func delete(source: LocalWorkout.Source) {
        persist(load().filter { $0.source != source })
    }

    private func persist(_ workouts: [LocalWorkout]) {
        if let data = try? encoder.encode(workouts) {
            try? data.write(to: fileURL, options: [.atomic])
        }
        persistSummaries(workouts)
    }

    private func persistSummaries(_ workouts: [LocalWorkout]) {
        let summaries = workouts.map(summary).sorted { $0.start > $1.start }
        summaryMemoryCache = summaries
        if let data = try? encoder.encode(summaries) {
            try? data.write(to: summaryFileURL, options: [.atomic])
        }
    }

    private func summary(_ workout: LocalWorkout) -> LocalWorkout {
        var copy = workout
        copy.route = []
        return copy
    }

    private func deduplicated(_ workouts: [LocalWorkout]) -> [LocalWorkout] {
        var byKey: [String: LocalWorkout] = [:]
        for workout in workouts {
            let key = duplicateKey(for: workout)
            if let existing = byKey[key] {
                byKey[key] = better(existing, workout)
            } else {
                byKey[key] = workout
            }
        }
        return Array(byKey.values)
    }

    private func duplicateKey(for workout: LocalWorkout) -> String {
        switch workout.source {
        case .appleHealth:
            return "\(workout.source.rawValue)|\(workout.id.uuidString)"
        case .manual, .gpx, .tcx, .gympit:
            return [
                workout.source.rawValue,
                normalized(workout.sport),
                normalized(workout.title),
                minuteKey(for: workout.start),
                minuteKey(for: workout.end)
            ].joined(separator: "|")
        }
    }

    private func better(_ lhs: LocalWorkout, _ rhs: LocalWorkout) -> LocalWorkout {
        let lhsScore = qualityScore(lhs)
        let rhsScore = qualityScore(rhs)
        if lhsScore == rhsScore {
            return rhs
        }
        return lhsScore >= rhsScore ? lhs : rhs
    }

    private func qualityScore(_ workout: LocalWorkout) -> Double {
        var score = workout.duration
        // A GymPit bridge copy contains the strength-training details that
        // Apple Health cannot represent. Prefer it decisively when an older
        // or duplicate copy has the same timing and summary values.
        score += Double(workout.exercises.count) * 10_000
        score += Double(workout.exercises.flatMap(\.sets).count) * 1_000
        if let distance = workout.distanceKm { score += distance * 100 }
        score += Double(workout.route.count)
        if workout.averageHeartRate != nil { score += 500 }
        if workout.maxHeartRate != nil { score += 250 }
        if !workout.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 50 }
        if workout.weather != nil { score += 25 }
        if workout.injury?.isEmpty == false { score += 25 }
        return score
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func minuteKey(for date: Date) -> String {
        String(Int((date.timeIntervalSince1970 / 60).rounded()))
    }
}
