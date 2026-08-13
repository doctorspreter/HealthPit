//
//  DashboardHeroSettings.swift
//  Healthpit
//
//  Welche drei Werte in der Kachel "Dein Tag auf einen Blick" stehen.
//  Bewusst genau drei: mehr passt nicht nebeneinander, ohne dass die Zahlen
//  unlesbar klein werden.
//

import Foundation
import HealthKit

enum DashboardHeroSettings {
    nonisolated static let storageKey = "dashboardHeroMetricIDs"
    nonisolated static let didChangeNotification = Notification.Name("HealthPitDashboardHeroDidChange")

    /// Anzahl der Zeilen in der Kachel.
    nonisolated static let slotCount = 3

    nonisolated static var defaultMetricIDs: [String] {
        [
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.restingHeartRate.rawValue,
        ]
    }

    nonisolated static func metricIDs(defaults: UserDefaults = .standard) -> [String] {
        let stored = defaults.stringArray(forKey: storageKey) ?? []
        // Aufgefuellt statt verworfen: eine unvollstaendige oder veraltete
        // Auswahl soll die Kachel nicht leer lassen.
        var result = stored.filter { HealthMetric.metric(id: $0) != nil }
        for fallback in defaultMetricIDs where result.count < slotCount {
            if !result.contains(fallback) { result.append(fallback) }
        }
        return Array(result.prefix(slotCount))
    }

    nonisolated static func metrics(defaults: UserDefaults = .standard) -> [HealthMetric] {
        metricIDs(defaults: defaults).compactMap { HealthMetric.metric(id: $0) }
    }

    nonisolated static func setMetricID(_ id: String,
                                        at index: Int,
                                        defaults: UserDefaults = .standard) {
        var ids = metricIDs(defaults: defaults)
        guard ids.indices.contains(index) else { return }
        ids[index] = id
        defaults.set(ids, forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    nonisolated static func resetToDefaults(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
