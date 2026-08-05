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
        let local = await LocalWorkoutStore.shared.loadSummaries()

        let defaults = UserDefaults.standard
        let hiddenHealth = Set((defaults.string(forKey: BridgeSettings.hiddenHealthWorkoutIDsKey) ?? "").split(separator: ",").map(String.init))

        let items = UnifiedWorkoutBuilder.build(
            health: health.filter { !hiddenHealth.contains($0.uuid.uuidString) },
            local: local
        )
        await WorkoutRecordCacheStore.shared.save(WorkoutRecordAnalyzer.records(for: items))
    }
}
