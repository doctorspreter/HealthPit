//
//  DashboardMetricCacheStore.swift
//  Healthpit
//
//  Kleiner Cache fuer die Startseiten-Kennzahlen, damit Kacheln beim Oeffnen
//  nicht gleichzeitig HealthKit-Abfragen starten.
//

import Foundation

struct DashboardMetricCacheEntry: Codable, Sendable {
    let metricID: String
    let value: Double
    let updatedAt: Date
    /// Tatsächliches Messdatum der Probe (nil = heutiger Summenwert ohne Datum).
    var measuredAt: Date?
}

actor DashboardMetricCacheStore {
    static let shared = DashboardMetricCacheStore()

    private let key = "dashboard.metric.values"

    private init() {}

    func load(metricIDs: [String]) async -> [String: Double] {
        let entries = await loadEntries()
        let wanted = Set(metricIDs)
        return entries.reduce(into: [:]) { result, entry in
            guard wanted.contains(entry.metricID) else { return }
            result[entry.metricID] = entry.value
        }
    }

    /// Wie `load`, liefert aber die vollen Einträge inkl. Messdatum.
    func loadEntries(metricIDs: [String]) async -> [String: DashboardMetricCacheEntry] {
        let entries = await loadEntries()
        let wanted = Set(metricIDs)
        return entries.reduce(into: [:]) { result, entry in
            guard wanted.contains(entry.metricID) else { return }
            result[entry.metricID] = entry
        }
    }

    func save(values: [String: Double], updatedAt: Date = .now) async {
        guard !values.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: await loadEntries().map { ($0.metricID, $0) })
        for (metricID, value) in values {
            byID[metricID] = DashboardMetricCacheEntry(metricID: metricID,
                                                       value: value,
                                                       updatedAt: updatedAt,
                                                       measuredAt: byID[metricID]?.measuredAt)
        }
        await HealthPitDatabase.shared.save(Array(byID.values), key: key)
    }

    /// Speichert Werte zusammen mit ihrem Messdatum (für seltene Messwerte wie Gewicht).
    func save(metricValues: [String: (value: Double, measuredAt: Date?)], updatedAt: Date = .now) async {
        guard !metricValues.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: await loadEntries().map { ($0.metricID, $0) })
        for (metricID, entry) in metricValues {
            byID[metricID] = DashboardMetricCacheEntry(metricID: metricID,
                                                       value: entry.value,
                                                       updatedAt: updatedAt,
                                                       measuredAt: entry.measuredAt)
        }
        await HealthPitDatabase.shared.save(Array(byID.values), key: key)
    }

    private func loadEntries() async -> [DashboardMetricCacheEntry] {
        await HealthPitDatabase.shared.load([DashboardMetricCacheEntry].self, key: key) ?? []
    }
}
