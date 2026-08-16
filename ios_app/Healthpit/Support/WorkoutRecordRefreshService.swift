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
        let items = await HealthQuery.shared.unifiedWorkouts()
        await WorkoutRecordCacheStore.shared.save(WorkoutRecordAnalyzer.records(for: items))
    }
}
