//
//  BackgroundSyncScheduler.swift
//  Healthpit
//
//  Plant gelegentliche Bridge-Synchronisierungen im Hintergrund.
//

import BackgroundTasks
import Foundation
import UIKit

enum BackgroundSyncScheduler {
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BridgeSettings.backgroundTaskIdentifier,
                                        using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task)
        }
    }

    static func schedule() {
        let defaults = UserDefaults.standard
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BridgeSettings.backgroundTaskIdentifier)
        guard defaults.bool(forKey: BridgeSettings.syncEnabledKey) else { return }

        let request = BGAppRefreshTaskRequest(identifier: BridgeSettings.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: syncInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("Bridge background sync scheduling failed: \(error.localizedDescription)")
        }
    }

    static var syncInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: BridgeSettings.syncIntervalKey)
        return stored > 0 ? stored : 3600
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()

        let sync = Task {
            do {
                try await BridgeSyncService.shared.syncNow()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            sync.cancel()
        }
    }
}
