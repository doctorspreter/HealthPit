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

        // Aus der Datenbank: Dort liegt jedes Training einmal, ein
        // Zusammenfuehren zweier Bestaende entfaellt.
        let defaults = UserDefaults.standard
        let hiddenHealth = Set((defaults.string(forKey: BridgeSettings.hiddenHealthWorkoutIDsKey) ?? "")
            .split(separator: ",").map(String.init))
        let items = await HealthQuery.shared.unifiedWorkouts().filter { workout in
            guard let uuid = workout.health?.uuid.uuidString else { return true }
            return !hiddenHealth.contains(uuid)
        }
        await WorkoutRecordCacheStore.shared.save(WorkoutRecordAnalyzer.records(for: items))
    }
}
