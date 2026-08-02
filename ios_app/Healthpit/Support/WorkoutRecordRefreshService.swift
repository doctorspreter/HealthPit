//
//  WorkoutRecordRefreshService.swift
//  Healthpit
//
//  Berechnet Rekorde nach Datenänderungen und schreibt einen Snapshot. Das
//  Lesen der Rekordseite bleibt dadurch billig.
//

import Foundation

actor WorkoutRecordRefreshService {
    static let shared = WorkoutRecordRefreshService()

    private var isRunning = false

    private init() {}

    func refreshFromLocalCaches() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let health = await HealthWorkoutCacheStore.shared.loadAllTime()
        let hevy = await HevyFitnessCacheStore.shared.load()
        let local = await LocalWorkoutStore.shared.loadSummaries()

        let defaults = UserDefaults.standard
        let ignored = Set((defaults.string(forKey: "ignoredHevyWorkoutLinks") ?? "").split(separator: ",").map(String.init))
        let hiddenHealth = Set((defaults.string(forKey: BridgeSettings.hiddenHealthWorkoutIDsKey) ?? "").split(separator: ",").map(String.init))
        let hiddenHevy = Set((defaults.string(forKey: "hiddenHevyWorkoutIDs") ?? "").split(separator: ",").map(String.init))

        let items = UnifiedWorkoutBuilder.build(
            health: health.filter { !hiddenHealth.contains($0.uuid.uuidString) },
            hevy: (hevy?.recentWorkouts ?? []).filter { !hiddenHevy.contains($0.id) },
            local: local,
            ignoredLinks: ignored
        )
        await WorkoutRecordCacheStore.shared.save(WorkoutRecordAnalyzer.records(for: items))
    }
}
