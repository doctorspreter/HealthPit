//
//  HealthPitPreloadService.swift
//  Healthpit
//
//  Was beim Start einmal angestossen wird.
//
//  Hier wurden lokale Zwischenspeicher gefuellt, damit Detailseiten beim
//  Oeffnen nicht auf HealthKit warten mussten. Seit die Bildschirme aus der
//  Datenbank lesen, wurden diese Dateien nur noch geschrieben und von niemandem
//  gelesen — eine zweite Kopie desselben Bestands, bei jedem Abgleich neu.
//
//  Geblieben ist, was wirklich von aussen kommt: die Trainings, die Home
//  Assistant zurueckschickt, und die Rekorde, die aus der Datenbank gerechnet
//  werden.
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

        _ = try? await BridgeSyncService.shared.downloadImportedWorkouts()
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

        // Nichts mehr vorzuladen: Die Bildschirme lesen die Datenbank, und die
        // liegt auf demselben Geraet. Ein Zwischenspeicher davor waere eine
        // zweite Kopie desselben Bestands.
        await WorkoutRecordRefreshService.shared.refreshFromLocalCaches()
    }

}
