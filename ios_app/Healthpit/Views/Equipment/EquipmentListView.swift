//
//  EquipmentListView.swift
//  Healthpit
//
//  Ausrüstung: was im Einsatz ist, wie weit es gelaufen ist und wann es
//  Wartung oder Austausch braucht.
//
//  Die Laufleistung wird nicht gespeichert, sondern aus den Trainings
//  gerechnet. Ein zweiter Zähler daneben wäre die erste Zahl, die
//  auseinanderläuft, sobald ein Training nachgetragen oder gelöscht wird.
//

import SwiftUI

struct EquipmentListView: View {
    @State private var items: [Equipment] = []
    @State private var workouts: [UnifiedWorkout] = []
    @State private var overrides: [String: String?] = [:]
    @State private var editing: Equipment?
    @State private var isLoading = true

    private let tint = Color.brown

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Ausrüstung"))
                        .font(.title2.bold())
                    Text(L10n.string("Schuhe, Rad und was sonst Kilometer sammelt."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                if inUse.isEmpty && retired.isEmpty {
                    Section {
                        Text(L10n.string("Noch nichts hinterlegt. Mit „+“ ein Stück anlegen."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if !inUse.isEmpty {
                    Section(L10n.string("Im Einsatz")) {
                        ForEach(inUse) { row($0) }
                    }
                }
                if !retired.isEmpty {
                    Section(L10n.string("Ausgemustert")) {
                        ForEach(retired) { row($0) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(L10n.string("Ausrüstung"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = Equipment() } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L10n.string("Ausrüstung hinzufügen"))
            }
        }
        .sheet(item: $editing) { item in
            EquipmentEditor(equipment: item) { saved in
                Task {
                    await EquipmentRegistry.save(saved)
                    await reload()
                }
            }
        }
        .task { await reload() }
    }

    private var inUse: [Equipment] { items.filter { !$0.isRetired } }
    private var retired: [Equipment] { items.filter(\.isRetired) }

    private func row(_ item: Equipment) -> some View {
        let usage = EquipmentRegistry.usage(of: item,
                                            workouts: workouts,
                                            allEquipment: items,
                                            overrides: overrides)
        // In die Detailansicht, nicht direkt in den Editor: dort haengen die
        // Teile, und die sind der Grund, warum man ein Stueck aufmacht.
        return NavigationLink {
            EquipmentDetailView(equipment: item, usage: usage) {
                Task { await reload() }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: item.kind.systemImage)
                        .foregroundStyle(tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subline(item, usage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if item.kind.tracksDistance, usage.distanceKm > 0 {
                        Text(WorkoutUnits.distance(km: usage.distanceKm, fractionDigits: 0))
                            .font(.caption.bold())
                            .foregroundStyle(tint)
                    }
                }

                // Fortschritt nur, wo ein Ziel gesetzt ist.
                if let progress = usage.replacementProgress(item) {
                    progressRow(L10n.string("Austausch"), progress, warnAt: 0.9)
                }
                if let progress = usage.serviceProgress(item) {
                    progressRow(L10n.string("Wartung"), progress, warnAt: 1.0)
                }
            }
            .padding(.vertical, 3)
        }
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    await EquipmentRegistry.delete(item)
                    await reload()
                }
            } label: {
                Label(L10n.string("Löschen"), systemImage: "trash")
            }
        }
    }

    private func progressRow(_ title: String, _ progress: Double, warnAt: Double) -> some View {
        let overdue = progress >= warnAt
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((progress * 100).rounded())) %")
                    .font(.caption2.bold())
                    .foregroundStyle(overdue ? .red : .secondary)
            }
            ProgressView(value: min(progress, 1))
                .tint(overdue ? .red : tint)
        }
    }

    private func subline(_ item: Equipment, _ usage: EquipmentUsage) -> String {
        var parts = [L10n.string(item.kind.displayKey)]
        if item.isRetired, let retiredAt = item.retiredAt {
            parts.append(L10n.format("bis %@", retiredAt.formatted(.dateTime.day().month().year())))
        } else {
            parts.append(L10n.format("seit %@", item.inUseFrom.formatted(.dateTime.day().month().year())))
        }
        if usage.workoutCount > 0 {
            parts.append(L10n.format("%lld Trainings", Int64(usage.workoutCount)))
        }
        if !item.isAutomatic {
            parts.append(L10n.string("nur manuell"))
        }
        return parts.joined(separator: " · ")
    }

    private func reload() async {
        items = await EquipmentRegistry.load()
        // Dieselbe Zusammenfuehrung wie die Trainingsliste: fuer die
        // Laufleistung zaehlen auch die selbst erfassten Trainings.
        workouts = await HealthQuery.shared.unifiedWorkouts()
        overrides = await loadOverrides()
        isLoading = false
    }

    private func loadOverrides() async -> [String: String?] {
        guard let store = try? await HealthPitData.shared.store(),
              let map = try? await store.equipmentOverrides() else {
            return [:]
        }
        return map
    }
}
