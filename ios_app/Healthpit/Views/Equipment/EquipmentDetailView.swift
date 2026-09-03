//
//  EquipmentDetailView.swift
//  Healthpit
//
//  Ein Ausrüstungsstück mit seinen Teilen.
//
//  Oben, was das Stück hinter sich hat, darunter jedes Teil mit seinem
//  eigenen Stand. Fällig ist rot, und ein Tippen auf „Erledigt" setzt das
//  Teil auf den aktuellen Kilometerstand und das heutige Datum zurück —
//  genau das macht man, wenn man die Kette gewechselt hat.
//

import SwiftUI

struct EquipmentDetailView: View {
    let equipment: Equipment
    let usage: EquipmentUsage
    var onChange: () -> Void = {}

    @State private var components: [EquipmentComponent] = []
    @State private var editingComponent: EquipmentComponent?
    @State private var editingEquipment: Equipment?
    @State private var isLoading = true

    private let tint = Color.brown

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(equipment.displayName)
                        .font(.title2.bold())
                    Text(subline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if let progress = usage.replacementProgress(equipment) {
                    progressRow(L10n.string("Austausch"), progress, detail: replacementDetail)
                }
            }

            Section(L10n.string("Bisher")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .leading)],
                          alignment: .leading, spacing: 14) {
                    if equipment.kind.tracksDistance {
                        stat(L10n.string("Strecke"),
                             WorkoutUnits.distance(km: usage.distanceKm, fractionDigits: 0))
                    }
                    stat(L10n.string("Trainings"), "\(usage.workoutCount)")
                    stat(L10n.string("Im Einsatz"), ageText)
                    if let last = usage.lastUsed {
                        stat(L10n.string("Zuletzt"), last.formatted(.dateTime.day().month().year()))
                    }
                }
                .padding(.vertical, 2)
            }

            Section {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if components.isEmpty {
                    Text(L10n.string("Noch keine Teile hinterlegt. Vorschläge unten, oder mit „+“ ein eigenes."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(components) { component in
                        componentRow(component)
                    }
                }
            } header: {
                Text(L10n.string("Teile"))
            }

            if !suggestions.isEmpty {
                Section(L10n.string("Vorschläge")) {
                    ForEach(suggestions, id: \.self) { kind in
                        Button {
                            add(kind)
                        } label: {
                            Label(L10n.string(kind.displayKey), systemImage: kind.systemImage)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(equipment.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editingComponent = EquipmentComponent(equipmentID: equipment.id, kind: .custom)
                    } label: {
                        Label(L10n.string("Teil hinzufügen"), systemImage: "plus")
                    }
                    Button {
                        editingEquipment = equipment
                    } label: {
                        Label(L10n.string("Bearbeiten"), systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editingComponent) { component in
            EquipmentComponentEditor(component: component,
                                     equipment: equipment,
                                     currentDistanceKm: usage.distanceKm) { saved in
                Task { await save(saved) }
            }
        }
        .sheet(item: $editingEquipment) { item in
            EquipmentEditor(equipment: item) { saved in
                Task {
                    await EquipmentRegistry.save(saved)
                    onChange()
                }
            }
        }
        .task { await reload() }
    }

    // MARK: Bausteine

    private var subline: String {
        var parts = [L10n.string(equipment.kind.displayKey)]
        parts.append(L10n.format("seit %@",
                                 equipment.inUseFrom.formatted(.dateTime.day().month().year())))
        if equipment.isRetired { parts.append(L10n.string("Ausgemustert")) }
        return parts.joined(separator: " · ")
    }

    private var ageText: String {
        let days = Calendar.healthApp
            .dateComponents([.day], from: equipment.inUseFrom, to: Date()).day ?? 0
        if days >= 365 {
            return L10n.format("%.1f Jahre", Double(days) / 365.0)
        }
        return L10n.format("%lld Tage", Int64(max(days, 0)))
    }

    /// Sagt, welche der beiden Grenzen die Anzeige treibt.
    private var replacementDetail: String? {
        let hasKm = (equipment.replaceAfterKm ?? 0) > 0
        let hasDays = (equipment.replaceAfterDays ?? 0) > 0
        guard hasKm, hasDays else { return nil }
        let byDistance = usage.distanceKm / (equipment.replaceAfterKm ?? 1)
        let age = Date().timeIntervalSince(equipment.inUseFrom) / 86_400
        let byTime = age / Double(equipment.replaceAfterDays ?? 1)
        return L10n.string(byDistance >= byTime ? "nach Strecke" : "nach Zeit")
    }

    private var suggestions: [ComponentKind] {
        let vorhanden = Set(components.map(\.kind))
        return ComponentKind.suggestions(for: equipment.kind).filter { !vorhanden.contains($0) }
    }

    private func componentRow(_ component: EquipmentComponent) -> some View {
        let progress = component.progress(distanceKm: usage.distanceKm,
                                          since: equipment.inUseFrom)
        let overdue = (progress ?? 0) >= 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: component.kind.systemImage)
                    .foregroundStyle(overdue ? .red : tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(componentSubline(component))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(L10n.string("Erledigt")) {
                    Task { await markDone(component) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
            if let progress {
                ProgressView(value: min(progress, 1))
                    .tint(overdue ? .red : tint)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { editingComponent = component }
        .swipeActions {
            Button(role: .destructive) {
                Task { await delete(component) }
            } label: {
                Label(L10n.string("Löschen"), systemImage: "trash")
            }
        }
    }

    private func componentSubline(_ component: EquipmentComponent) -> String {
        var parts = [L10n.string(component.action.displayKey)]
        if let km = component.intervalKm, km > 0 {
            parts.append(WorkoutUnits.distance(km: km, fractionDigits: 0))
        }
        if let days = component.intervalDays, days > 0 {
            parts.append(days % 365 == 0
                         ? L10n.format("%lld Jahre", Int64(days / 365))
                         : L10n.format("%lld Tage", Int64(days)))
        }
        if let reason = component.limitingReason(distanceKm: usage.distanceKm,
                                                 since: equipment.inUseFrom) {
            parts.append(L10n.string(reason))
        }
        return parts.joined(separator: " · ")
    }

    private func progressRow(_ title: String, _ progress: Double, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let detail {
                    Text("· \(detail)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int((progress * 100).rounded())) %")
                    .font(.caption.bold())
                    .foregroundStyle(progress >= 0.9 ? .red : .secondary)
            }
            ProgressView(value: min(progress, 1))
                .tint(progress >= 0.9 ? .red : tint)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Aktionen

    private func add(_ kind: ComponentKind) {
        editingComponent = EquipmentComponent(equipmentID: equipment.id, kind: kind)
    }

    private func markDone(_ component: EquipmentComponent) async {
        var updated = component
        updated.lastDoneKm = usage.distanceKm
        updated.lastDoneAt = Date()
        await save(updated)
    }

    private func save(_ component: EquipmentComponent) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.upsertEquipmentComponent(component)
        await reload()
        onChange()
    }

    private func delete(_ component: EquipmentComponent) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.deleteEquipmentComponent(id: component.id)
        await reload()
        onChange()
    }

    private func reload() async {
        guard let store = try? await HealthPitData.shared.store(),
              let all = try? await store.equipmentComponents() else {
            isLoading = false
            return
        }
        components = all.filter { $0.equipmentID == equipment.id }
        isLoading = false
    }
}
