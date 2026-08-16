//
//  HealthPitPreloadService.swift
//  Healthpit
//
//  Fuellt lokale Caches frueh, damit Detailseiten nicht erst beim Oeffnen
//  teure Abfragen starten muessen.
//
//  Gelesen wird aus der Datenbank, nicht aus HealthKit. Sonst stuenden in den
//  Caches andere Zahlen als auf den Bildschirmen: HealthKit liefert Prozente
//  als Bruch, kennt keine abgeschalteten Quellen und dieselbe Einheit aus drei
//  Apps dreimal.
//

import Foundation

actor HealthPitPreloadService {
    static let shared = HealthPitPreloadService()

    private let health = HealthKitManager.shared
    private var isRunning = false

    private init() {}

    func refreshEssentialCaches() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        await health.prepareForBackgroundWork()

        async let dashboardMetrics: Void = refreshDashboardMetrics()
        async let sleepCaches: Void = refreshSleepCaches()
        async let imports: Int? = try? BridgeSyncService.shared.downloadImportedWorkouts()

        _ = await sleepCaches
        _ = await dashboardMetrics
        _ = await imports
        // Do not warm this cache before the bridge download has completed.
        // Otherwise the first workout screen can observe the old GymPit copy
        // without its exercises and keep showing it for the whole view life.
        _ = await LocalWorkoutStore.shared.loadSummaries()
    }

    /// Lokaler Abgleich für Pull-to-refresh: nur Apple Health lesen und lokale
    /// Caches aktualisieren, ohne Bridge-/Serverkontakt.
    func refreshLocalAppleHealthCaches() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        await health.prepareForBackgroundWork()

        async let dashboardMetrics: Void = refreshDashboardMetrics()
        async let sleepCaches: Void = refreshSleepCaches()
        async let workoutCaches: Void = refreshAppleHealthWorkoutCaches()

        _ = await dashboardMetrics
        _ = await sleepCaches
        _ = await workoutCaches
    }

    private func refreshDashboardMetrics() async {
        let metrics = [
            HealthCategory.activity,
            .heart,
            .body,
            .nutrition,
            .vitals
        ].flatMap(HealthMetric.headline(for:))

        var values: [String: (value: Double, measuredAt: Date?)] = [:]
        for metric in metrics {
            if let latest = await HealthQuery.shared.latestValue(for: metric) {
                values[metric.id] = (latest.value, latest.date)
            }
        }
        await DashboardMetricCacheStore.shared.save(metricValues: values)
    }

    private func refreshSleepCaches() async {
        for range in [TimeRange.day, .week, .month] {
            let sessions = await HealthQuery.shared.nights(in: range.dateInterval(referenceDate: .now))
            await SleepCacheStore.shared.save(sessions, range: range)
        }
    }

    private func refreshAppleHealthWorkoutCaches(referenceDate: Date = .now) async {
        for range in [TimeRange.day, .week, .month, .year] {
            let workouts = await HealthQuery.shared.workouts(
                in: range.dateInterval(referenceDate: referenceDate)
            )
            await HealthWorkoutCacheStore.shared.save(workouts,
                                                      range: range,
                                                      referenceDate: referenceDate)
            if range == .year {
                await HealthWorkoutCacheStore.shared.mergeAllTime(workouts)
            }
        }
    }
}
