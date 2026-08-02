//
//  HealthpitPreloadService.swift
//  Healthpit
//
//  Fuellt lokale Caches frueh, damit Detailseiten nicht erst beim Oeffnen
//  teure HealthKit-/Bridge-Abfragen starten muessen.
//

import Foundation

actor HealthpitPreloadService {
    static let shared = HealthpitPreloadService()

    private let health = HealthKitManager.shared
    private var isRunning = false

    private init() {}

    func refreshEssentialCaches() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        try? await health.requestAuthorization()

        async let dashboardMetrics: Void = refreshDashboardMetrics()
        async let sleepDay = try? health.fetchSleep(in: .day)
        async let sleepWeek = try? health.fetchSleep(in: .week)
        async let sleepMonth = try? health.fetchSleep(in: .month)
        async let hevy = try? BridgeFitnessService.shared.fetchHevySummary()
        async let imports: Int? = try? BridgeSyncService.shared.downloadImportedWorkouts()
        async let localSummaries: [LocalWorkout] = LocalWorkoutStore.shared.loadSummaries()

        if let sessions = await sleepDay {
            await SleepCacheStore.shared.save(sessions, range: .day)
        }
        if let sessions = await sleepWeek {
            await SleepCacheStore.shared.save(sessions, range: .week)
        }
        if let sessions = await sleepMonth {
            await SleepCacheStore.shared.save(sessions, range: .month)
        }
        if let summary = await hevy {
            await HevyFitnessCacheStore.shared.save(summary)
        }
        _ = await dashboardMetrics
        _ = await imports
        _ = await localSummaries
    }

    /// Lokaler Abgleich für Pull-to-refresh: nur Apple Health lesen und lokale
    /// Caches aktualisieren, ohne Bridge-/Serverkontakt.
    func refreshLocalAppleHealthCaches() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        try? await health.requestAuthorization()

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
            if let result = try? await health.latestValueWithDate(for: metric) {
                values[metric.id] = result
            }
        }
        await DashboardMetricCacheStore.shared.save(metricValues: values)
    }

    private func refreshSleepCaches() async {
        async let sleepDay = try? health.fetchSleep(in: .day)
        async let sleepWeek = try? health.fetchSleep(in: .week)
        async let sleepMonth = try? health.fetchSleep(in: .month)

        if let sessions = await sleepDay {
            await SleepCacheStore.shared.save(sessions, range: .day)
        }
        if let sessions = await sleepWeek {
            await SleepCacheStore.shared.save(sessions, range: .week)
        }
        if let sessions = await sleepMonth {
            await SleepCacheStore.shared.save(sessions, range: .month)
        }
    }

    private func refreshAppleHealthWorkoutCaches(referenceDate: Date = .now) async {
        async let day = try? health.fetchWorkouts(in: .day, referenceDate: referenceDate)
        async let week = try? health.fetchWorkouts(in: .week, referenceDate: referenceDate)
        async let month = try? health.fetchWorkouts(in: .month, referenceDate: referenceDate)
        async let year = try? health.fetchWorkouts(in: .year, referenceDate: referenceDate)

        if let workouts = await day {
            await HealthWorkoutCacheStore.shared.save(workouts, range: .day, referenceDate: referenceDate)
        }
        if let workouts = await week {
            await HealthWorkoutCacheStore.shared.save(workouts, range: .week, referenceDate: referenceDate)
        }
        if let workouts = await month {
            await HealthWorkoutCacheStore.shared.save(workouts, range: .month, referenceDate: referenceDate)
        }
        if let workouts = await year {
            await HealthWorkoutCacheStore.shared.save(workouts, range: .year, referenceDate: referenceDate)
            await HealthWorkoutCacheStore.shared.mergeAllTime(workouts)
        }
    }
}
