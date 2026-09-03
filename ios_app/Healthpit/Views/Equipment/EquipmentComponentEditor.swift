//
//  EquipmentComponentEditor.swift
//  Healthpit
//
//  Ein Teil anlegen oder ändern.
//
//  Strecke und Zeit lassen sich beide setzen, einzeln oder zusammen. Sind
//  beide gesetzt, gilt, was zuerst eintritt — Laufschuhe nach 800 km oder
//  nach drei Jahren, je nachdem, was früher kommt.
//

import SwiftUI

struct EquipmentComponentEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EquipmentComponent
    @State private var hasKm: Bool
    @State private var km: Double
    @State private var hasTime: Bool
    @State private var days: Int

    private let equipment: Equipment
    private let currentDistanceKm: Double
    private let onSave: (EquipmentComponent) -> Void

    init(component: EquipmentComponent,
         equipment: Equipment,
         currentDistanceKm: Double,
         onSave: @escaping (EquipmentComponent) -> Void) {
        _draft = State(initialValue: component)
        _hasKm = State(initialValue: component.intervalKm != nil)
        _km = State(initialValue: component.intervalKm ?? component.kind.suggestedKm ?? 1000)
        _hasTime = State(initialValue: component.intervalDays != nil)
        _days = State(initialValue: component.intervalDays ?? component.kind.suggestedDays ?? 365)
        self.equipment = equipment
        self.currentDistanceKm = currentDistanceKm
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.string("Teil"), selection: $draft.kind) {
                        ForEach(ComponentKind.allCases) { kind in
                            Text(L10n.string(kind.displayKey)).tag(kind)
                        }
                    }
                    .onChange(of: draft.kind) { _, kind in
                        draft.action = kind.defaultAction
                        if let suggested = kind.suggestedKm { km = suggested; hasKm = true }
                        else { hasKm = false }
                        if let suggested = kind.suggestedDays { days = suggested; hasTime = true }
                        else { hasTime = false }
                    }
                    if draft.kind == .custom {
                        TextField(L10n.string("Name"), text: $draft.name)
                    }
                    Picker(L10n.string("Was passiert"), selection: $draft.action) {
                        ForEach(ComponentAction.allCases) { action in
                            Text(L10n.string(action.displayKey)).tag(action)
                        }
                    }
                }

                Section {
                    Toggle(L10n.string("Nach Strecke"), isOn: $hasKm.animation())
                    if hasKm {
                        Stepper(value: $km, in: 50...30000, step: 50) {
                            HStack {
                                Text(L10n.string("Alle"))
                                Spacer()
                                Text(WorkoutUnits.distance(km: km, fractionDigits: 0))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Toggle(L10n.string("Nach Zeit"), isOn: $hasTime.animation())
                    if hasTime {
                        Stepper(value: $days, in: 7...3650, step: 7) {
                            HStack {
                                Text(L10n.string("Alle"))
                                Spacer()
                                Text(zeitText).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text(hasKm && hasTime
                         ? L10n.string("Fällig ist, was zuerst eintritt.")
                         : L10n.string("Mindestens eines von beidem, sonst wird nie etwas fällig."))
                }

                Section(L10n.string("Zuletzt erledigt")) {
                    if let lastDoneAt = draft.lastDoneAt {
                        LabeledContent(L10n.string("Datum"),
                                       value: lastDoneAt.formatted(.dateTime.day().month().year()))
                        LabeledContent(L10n.string("Stand"),
                                       value: WorkoutUnits.distance(km: draft.lastDoneKm, fractionDigits: 0))
                    } else {
                        Text(L10n.format("Noch nie – gerechnet wird ab %@",
                                         equipment.inUseFrom.formatted(.dateTime.day().month().year())))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button(L10n.string("Jetzt als erledigt eintragen")) {
                        draft.lastDoneAt = Date()
                        draft.lastDoneKm = currentDistanceKm
                    }
                    .font(.footnote)
                }

                Section(L10n.string("Notiz")) {
                    TextField(L10n.string("Notiz"), text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(L10n.string("Teil"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Sichern")) {
                        var component = draft
                        component.intervalKm = hasKm ? km : nil
                        component.intervalDays = hasTime ? days : nil
                        onSave(component)
                        dismiss()
                    }
                    .disabled(!hasKm && !hasTime)
                }
            }
        }
    }

    private var zeitText: String {
        if days % 365 == 0 { return L10n.format("%lld Jahre", Int64(days / 365)) }
        if days % 30 == 0 { return L10n.format("%lld Monate", Int64(days / 30)) }
        return L10n.format("%lld Tage", Int64(days))
    }
}
