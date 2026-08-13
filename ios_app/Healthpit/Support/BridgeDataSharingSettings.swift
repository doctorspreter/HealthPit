//
//  BridgeDataSharingSettings.swift
//  Healthpit
//
//  Lokale Auswahl der Datentypen, die Healthpit an Home Assistant uebertraegt.
//

import Foundation

struct BridgeDataTypeDescriptor: Identifiable, Hashable, Sendable {
    static let workoutsID = "healthpit.sharing.workouts"

    let id: String
    let title: String
    let systemImage: String
    let category: HealthCategory

    /// Alles, was uebertragen werden kann — einschliesslich der Ziele, die der
    /// Nutzer selbst angelegt hat. Deshalb berechnet und nicht konstant.
    nonisolated static var all: [BridgeDataTypeDescriptor] {
        fixed + ActivityGoalStore.goals().map { goal in
            // Zielwert und Erfuellungsgrad haengen zusammen und werden ueber
            // einen Schalter gesteuert.
            BridgeDataTypeDescriptor(
                id: ActivityGoalStore.syncID(for: goal),
                title: ActivityGoalStore.syncTitle(for: goal),
                systemImage: goal.symbol,
                category: goal.metric?.category ?? .activity
            )
        }
    }

    nonisolated private static let fixed: [BridgeDataTypeDescriptor] = {
        let metrics = HealthMetric.all.map {
            BridgeDataTypeDescriptor(
                id: $0.id,
                title: $0.title,
                systemImage: $0.systemImage,
                category: $0.category
            )
        }

        return metrics + [
            BridgeDataTypeDescriptor(
                id: workoutsID,
                title: "Workouts",
                systemImage: "figure.run",
                category: .workouts
            ),
            BridgeDataTypeDescriptor(
                id: "sleep_duration",
                title: "Schlafdauer",
                systemImage: "bed.double.fill",
                category: .sleep
            ),
            BridgeDataTypeDescriptor(
                id: "sleep_time_in_bed",
                title: "Zeit im Bett",
                systemImage: "bed.double",
                category: .sleep
            ),
            BridgeDataTypeDescriptor(
                id: "sleep_efficiency",
                title: "Schlafeffizienz",
                systemImage: "gauge.with.dots.needle.50percent",
                category: .sleep
            ),
            BridgeDataTypeDescriptor(
                id: "sleep_deep_duration",
                title: "Tiefschlaf",
                systemImage: "moon.zzz.fill",
                category: .sleep
            ),
            BridgeDataTypeDescriptor(
                id: "sleep_core_duration",
                title: "Core-Schlaf",
                systemImage: "moon.fill",
                category: .sleep
            ),
            BridgeDataTypeDescriptor(
                id: "sleep_rem_duration",
                title: "REM-Schlaf",
                systemImage: "sparkles",
                category: .sleep
            ),
            BridgeDataTypeDescriptor(
                id: "sleep_awake_duration",
                title: "Wachzeit",
                systemImage: "sun.max.fill",
                category: .sleep
            ),
            BridgeDataTypeDescriptor(
                id: "cycle_current_day",
                title: "Zyklustag",
                systemImage: "calendar",
                category: .cycle
            ),
            BridgeDataTypeDescriptor(
                id: "cycle_average_length",
                title: "Ø Zykluslänge",
                systemImage: "calendar.badge.clock",
                category: .cycle
            ),
            BridgeDataTypeDescriptor(
                id: "cycle_average_period_length",
                title: "Ø Periodendauer",
                systemImage: "drop.circle",
                category: .cycle
            ),
            BridgeDataTypeDescriptor(
                id: "cycle_bleeding_days",
                title: "Blutungstage",
                systemImage: "drop.fill",
                category: .cycle
            ),
        ]
    }()
}

enum BridgeDataSharingSettings {
    nonisolated static let disabledDataTypesKey = "bridgeSharing.disabledDataTypes"

    nonisolated static func isEnabled(
        _ dataTypeID: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        !disabledIDs(defaults: defaults).contains(dataTypeID)
    }

    nonisolated static func setEnabled(
        _ enabled: Bool,
        for dataTypeID: String,
        defaults: UserDefaults = .standard
    ) {
        var disabled = disabledIDs(defaults: defaults)
        if enabled {
            disabled.remove(dataTypeID)
        } else {
            disabled.insert(dataTypeID)
        }
        defaults.set(disabled.sorted(), forKey: disabledDataTypesKey)
    }

    nonisolated static func setEnabledIDs(
        _ enabledIDs: Set<String>,
        defaults: UserDefaults = .standard
    ) {
        let allIDs = Set(BridgeDataTypeDescriptor.all.map(\.id))
        defaults.set(allIDs.subtracting(enabledIDs).sorted(), forKey: disabledDataTypesKey)
    }

    nonisolated private static func disabledIDs(defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: disabledDataTypesKey) ?? [])
    }
}
