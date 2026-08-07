//
//  SleepCacheStore.swift
//  Healthpit
//
//  Persistenter Cache fuer Schlafansichten.
//

import Foundation

actor SleepCacheStore {
    static let shared = SleepCacheStore()

    private init() {}

    func load(range: TimeRange, referenceDate: Date = .now) async -> [SleepSession] {
        let sessions = await HealthPitDatabase.shared.load([SleepSession].self, key: key(for: range, referenceDate: referenceDate)) ?? []
        return sessions.sorted { $0.end > $1.end }
    }

    func save(_ sessions: [SleepSession], range: TimeRange, referenceDate: Date = .now) async {
        await HealthPitDatabase.shared.save(sessions.sorted { $0.end > $1.end }, key: key(for: range, referenceDate: referenceDate))
    }

    private func key(for range: TimeRange, referenceDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let anchor = range.anchorDate(referenceDate: referenceDate, calendar: .healthApp)
        return "sleep_sessions.\(range.rawValue).\(formatter.string(from: anchor))"
    }
}
