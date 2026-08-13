//
//  HealthPitApp.swift
//  Healthpit
//
//  Created by Peter Weber on 19.06.26.
//

import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthDataSourceSettings.registerDefaults()
        if UserDefaults.standard.object(forKey: BridgeSettings.syncEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: BridgeSettings.syncEnabledKey)
        }
        if UserDefaults.standard.double(forKey: BridgeSettings.syncIntervalKey) <= 0 {
            UserDefaults.standard.set(3600, forKey: BridgeSettings.syncIntervalKey)
        }
        BackgroundSyncScheduler.register()
        BackgroundSyncScheduler.schedule()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundSyncScheduler.schedule()
    }
}

@main
struct HealthPitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage(MeasurementSystemSetting.storageKey) private var measurementSystemRawValue = MeasurementSystemSetting.automatic.rawValue
    @State private var undatedImport: WorkoutFileImport?
    @State private var availableWorkouts: [UnifiedWorkout] = []

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Sprache und Maßeinheiten stecken in synchron gelesenen
                // Einstellungen, nicht in beobachtbarem Zustand – beim Wechsel
                // muss die Oberfläche daher komplett neu aufgebaut werden.
                .id("\(appLanguageRawValue)-\(measurementSystemRawValue)")
                .environment(\.locale, AppLanguage.from(appLanguageRawValue).locale)
                .sheet(item: $undatedImport) { imported in
                    UndatedWorkoutImportView(imported: imported,
                                             workouts: availableWorkouts) { workout in
                        Task {
                            await LocalWorkoutStore.shared.save(workout)
                            _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
                        }
                    }
                }
                .onOpenURL { url in
                    Task {
                        await importSharedWorkoutFile(url)
                    }
                }
        }
    }

    private func importSharedWorkoutFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let imported = try? WorkoutFileImporter.analyze(from: url) else { return }
        if imported.containsDate {
            await LocalWorkoutStore.shared.save(imported.workout)
            _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
            return
        }

        async let local = LocalWorkoutStore.shared.loadSummaries()
        let cachedHealth = await HealthWorkoutCacheStore.shared.loadAllTime()
        let fetchedHealth = try? await HealthKitManager.shared.fetchAllWorkouts()
        let health: [WorkoutSummary]
        if let fetchedHealth, !fetchedHealth.isEmpty {
            health = fetchedHealth.filter(\.isEligibleForLocalHealthCache)
            await HealthWorkoutCacheStore.shared.saveAllTime(health)
        } else {
            health = cachedHealth
        }
        availableWorkouts = UnifiedWorkoutBuilder.build(health: health, local: await local)
        undatedImport = imported
    }
}
