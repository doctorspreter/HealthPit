//
//  EquipmentPicker.swift
//  Healthpit
//
//  Die Ausrüstung eines einzelnen Trainings.
//
//  Drei Zustände, und der erste ist der wichtige: „Automatisch" heißt, dass
//  hier nichts festgeschrieben wird. Verschiebt man später das Kaufdatum der
//  Schuhe, wandert dieses Training mit. Erst eine ausdrückliche Wahl — auch
//  die Wahl „keine" — schreibt eine Abweichung fest.
//

import SwiftUI

struct EquipmentPicker: View {
    let workout: UnifiedWorkout

    @State private var items: [Equipment] = []
    @State private var overrides: [String: String?] = [:]
    @State private var isLoading = true

    /// `nil` = automatisch, `.some(nil)` = ausdrücklich keine.
    private var override: String?? {
        overrides.index(forKey: workout.id).map { overrides[$0].value }
    }

    private var automatic: Equipment? {
        EquipmentRegistry.equipment(for: workout, in: items, overrides: [:])
    }

    private var selected: Equipment? {
        EquipmentRegistry.equipment(for: workout, in: items, overrides: overrides)
    }

    var body: some View {
        Group {
            // Ohne hinterlegte Ausruestung gibt es nichts zu waehlen, und dann
            // gehoert auch keine Ueberschrift auf den Bildschirm.
            if items.isEmpty {
                EmptyView()
            } else {
                Section(L10n.string("Ausrüstung")) {
                    Picker(L10n.string("Ausrüstung"), selection: selectionBinding) {
                        Text(automaticTitle).tag(Selection.automatic)
                        Text(L10n.string("Keine")).tag(Selection.none)
                        ForEach(items.filter { !$0.isRetired || $0.id == selected?.id }) { item in
                            Text(item.displayName).tag(Selection.item(item.id))
                        }
                    }
                }
            }
        }
        .task { await reload() }
    }

    private enum Selection: Hashable {
        case automatic
        case none
        case item(String)
    }

    private var automaticTitle: String {
        guard let automatic else { return L10n.string("Automatisch (keine)") }
        return L10n.format("Automatisch (%@)", automatic.displayName)
    }

    private var selectionBinding: Binding<Selection> {
        Binding(
            get: {
                guard let override else { return .automatic }
                guard let id = override else { return .none }
                return .item(id)
            },
            set: { choice in
                Task {
                    switch choice {
                    case .automatic:
                        await EquipmentRegistry.clearOverride(workoutID: workout.id)
                    case .none:
                        await EquipmentRegistry.setOverride(workoutID: workout.id, equipmentID: nil)
                    case .item(let id):
                        await EquipmentRegistry.setOverride(workoutID: workout.id, equipmentID: id)
                    }
                    await reload()
                }
            }
        )
    }

    private func reload() async {
        items = await EquipmentRegistry.load()
        if let store = try? await HealthPitData.shared.store(),
           let map = try? await store.equipmentOverrides() {
            overrides = map
        }
        isLoading = false
    }
}
