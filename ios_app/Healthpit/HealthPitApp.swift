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
    @State private var bootstrap = HealthPitBootstrap.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Sprache und Maßeinheiten stecken in synchron gelesenen
                // Einstellungen, nicht in beobachtbarem Zustand – beim Wechsel
                // muss die Oberfläche daher komplett neu aufgebaut werden.
                .id("\(appLanguageRawValue)-\(measurementSystemRawValue)")
                // Datum und Zahlen folgen bewusst der Systemsprache, nicht der
                // App-Sprache: Sonst stand im Schlafbildschirm „Fr. 14. Aug.“
                // über „Aug 14, 2026“ – der Datumswähler richtete sich nach der
                // App, die formatierten Datumsangaben nach dem System. Die
                // Texte der App übersetzt L10n, das bleibt davon unberührt.
                // Datenbank öffnen, Altbestand übernehmen, Apple Health lesen.
                // Alles, was die App anzeigt, kommt danach von dort.
                .task { await bootstrap.run() }
                .overlay {
                    if case let .importing(progress) = bootstrap.phase {
                        FirstImportOverlay(progress: progress)
                    } else if case .converting = bootstrap.phase {
                        FirstImportOverlay(progress: IngestProgress(
                            step: L10n.string("Vorhandene Daten werden übernommen …"),
                            fraction: nil
                        ))
                    }
                }
                .sheet(item: $undatedImport) { imported in
                    UndatedWorkoutImportView(imported: imported,
                                             workouts: availableWorkouts) { workout in
                        Task {
                            await ManualWorkoutWriter.save(workout)
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
            await ManualWorkoutWriter.save(imported.workout)
            _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
            return
        }

        // Ohne Datum im Dateinamen: Der Anwender ordnet die Datei einem
        // vorhandenen Training zu. Die Auswahl kommt aus der Datenbank.
        availableWorkouts = await HealthQuery.shared.unifiedWorkouts()
        undatedImport = imported
    }
}
