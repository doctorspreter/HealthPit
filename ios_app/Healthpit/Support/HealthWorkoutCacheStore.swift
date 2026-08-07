//
//  HealthWorkoutCacheStore.swift
//  Healthpit
//
//  Kleiner lokaler Cache fuer HealthKit-Workoutlisten.
//

import Foundation

actor HealthWorkoutCacheStore {
    static let shared = HealthWorkoutCacheStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let folderURL: URL
    private var allTimeMemoryCache: [WorkoutSummary]?
    private var allTimeCountMemoryCache: Int?

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        folderURL = base.appending(path: "HealthWorkoutCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    func load(range: TimeRange, referenceDate: Date = .now) async -> [WorkoutSummary] {
        if let workouts = await HealthPitDatabase.shared.load([WorkoutSummary].self, key: dbKey(for: range, referenceDate: referenceDate)) {
            return cacheable(workouts).sorted { $0.start > $1.start }
        }
        if let allTimeMemoryCache {
            let interval = range.dateInterval(referenceDate: referenceDate)
            let filtered = allTimeMemoryCache.filter { interval.contains($0.start) }
            await save(filtered, range: range, referenceDate: referenceDate)
            return filtered
        }
        if Calendar.healthApp.isDate(referenceDate, inSameDayAs: .now),
           let workouts = await HealthPitDatabase.shared.load([WorkoutSummary].self, key: legacyDBKey(for: range)) {
            return cacheable(workouts).sorted { $0.start > $1.start }
        }
        guard let data = try? Data(contentsOf: fileURL(for: range)),
              let workouts = try? decoder.decode([WorkoutSummary].self, from: data) else {
            return []
        }
        let sorted = cacheable(workouts).sorted { $0.start > $1.start }
        await HealthPitDatabase.shared.save(sorted, key: dbKey(for: range, referenceDate: referenceDate))
        return sorted
    }

    func save(_ workouts: [WorkoutSummary], range: TimeRange, referenceDate: Date = .now) async {
        let sorted = cacheable(workouts).sorted(by: { $0.start > $1.start })
        await HealthPitDatabase.shared.save(sorted, key: dbKey(for: range, referenceDate: referenceDate))
        if Calendar.healthApp.isDate(referenceDate, inSameDayAs: .now) {
            await HealthPitDatabase.shared.save(sorted, key: legacyDBKey(for: range))
        }
        guard let data = try? encoder.encode(sorted) else {
            return
        }
        try? data.write(to: fileURL(for: range), options: [.atomic])
    }

    func loadAllTime() async -> [WorkoutSummary] {
        if let allTimeMemoryCache {
            return allTimeMemoryCache
        }
        let workouts = await HealthPitDatabase.shared.load([WorkoutSummary].self, key: "health_workouts.all_time") ?? []
        let sorted = cacheable(workouts).sorted { $0.start > $1.start }
        allTimeMemoryCache = sorted
        return sorted
    }

    func countAllTime() async -> Int {
        if let allTimeCountMemoryCache {
            return allTimeCountMemoryCache
        }
        if let count = await HealthPitDatabase.shared.load(Int.self, key: "health_workouts.all_time_count") {
            allTimeCountMemoryCache = count
            return count
        }
        if let allTimeMemoryCache {
            allTimeCountMemoryCache = allTimeMemoryCache.count
            return allTimeMemoryCache.count
        }
        return 0
    }

    func latestWorkout() async -> WorkoutSummary? {
        if let allTimeMemoryCache {
            return allTimeMemoryCache.first
        }
        if let recent = await load(range: .year).first {
            return recent
        }
        return await loadAllTime().first
    }

    func saveAllTime(_ workouts: [WorkoutSummary]) async {
        let sorted = cacheable(workouts).sorted { $0.start > $1.start }
        allTimeMemoryCache = sorted
        allTimeCountMemoryCache = sorted.count
        await HealthPitDatabase.shared.save(sorted, key: "health_workouts.all_time")
        await HealthPitDatabase.shared.save(sorted.count, key: "health_workouts.all_time_count")
        await saveCurrentRangeCaches(from: sorted)
    }

    func mergeAllTime(_ incoming: [WorkoutSummary]) async {
        guard !incoming.isEmpty else { return }
        var byID: [UUID: WorkoutSummary] = [:]
        for workout in await loadAllTime() {
            byID[workout.uuid] = workout
        }
        for workout in incoming {
            byID[workout.uuid] = workout
        }
        await saveAllTime(Array(byID.values))
    }

    func clear() async {
        allTimeMemoryCache = nil
        allTimeCountMemoryCache = nil
        for range in TimeRange.allCases {
            try? FileManager.default.removeItem(at: fileURL(for: range))
        }
        await HealthPitDatabase.shared.removeAll()
    }

    private func cacheable(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        workouts.filter(\.isEligibleForLocalHealthCache)
    }

    private func fileURL(for range: TimeRange) -> URL {
        folderURL.appending(path: "\(range.rawValue).json")
    }

    private func dbKey(for range: TimeRange, referenceDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let anchor = TimeRangeKey.anchor(for: range, referenceDate: referenceDate)
        return "health_workouts.\(range.rawValue).\(formatter.string(from: anchor))"
    }

    private func legacyDBKey(for range: TimeRange) -> String {
        "health_workouts.\(range.rawValue)"
    }

    private func saveCurrentRangeCaches(from workouts: [WorkoutSummary], referenceDate: Date = .now) async {
        for range in TimeRange.allCases {
            let interval = range.dateInterval(referenceDate: referenceDate)
            let filtered = workouts.filter { interval.contains($0.start) }
            await save(filtered, range: range, referenceDate: referenceDate)
        }
    }
}

private enum TimeRangeKey {
    nonisolated static func anchor(for range: TimeRange, referenceDate: Date) -> Date {
        range.anchorDate(referenceDate: referenceDate, calendar: .healthApp)
    }
}
