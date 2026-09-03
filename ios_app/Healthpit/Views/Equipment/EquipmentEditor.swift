//
//  EquipmentEditor.swift
//  Healthpit
//
//  Ein Ausrüstungsstück anlegen oder ändern.
//

import SwiftUI

struct EquipmentEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Equipment
    @State private var isRetired: Bool
    @State private var retiredDate: Date
    @State private var hasReplacementTarget: Bool
    @State private var replacementKm: Double
    @State private var hasServiceInterval: Bool
    @State private var serviceKm: Double
    @State private var hasAgeLimit: Bool
    @State private var ageDays: Int

    private let onSave: (Equipment) -> Void

    init(equipment: Equipment, onSave: @escaping (Equipment) -> Void) {
        _draft = State(initialValue: equipment)
        _isRetired = State(initialValue: equipment.retiredAt != nil)
        _retiredDate = State(initialValue: equipment.retiredAt ?? Date())
        let target = equipment.replaceAfterKm ?? equipment.kind.suggestedReplacementKm
        _hasReplacementTarget = State(initialValue: equipment.replaceAfterKm != nil)
        _replacementKm = State(initialValue: target ?? 800)
        _hasServiceInterval = State(initialValue: equipment.serviceEveryKm != nil)
        _serviceKm = State(initialValue: equipment.serviceEveryKm ?? 500)
        _hasAgeLimit = State(initialValue: equipment.replaceAfterDays != nil)
        _ageDays = State(initialValue: equipment.replaceAfterDays ?? 1095)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.string("Art"), selection: $draft.kind) {
                        ForEach(EquipmentKind.allCases) { kind in
                            Text(L10n.string(kind.displayKey)).tag(kind)
                        }
                    }
                    .onChange(of: draft.kind) { _, kind in
                        // Ein frischer Vorschlag, solange niemand selbst
                        // etwas eingetragen hat.
                        if !hasReplacementTarget, let suggested = kind.suggestedReplacementKm {
                            replacementKm = suggested
                        }
                    }
                    TextField(L10n.string("Name"), text: $draft.name)
                }

                Section {
                    DatePicker(L10n.string("Im Einsatz seit"),
                               selection: $draft.inUseFrom,
                               in: ...Date(),
                               displayedComponents: [.date])
                    Toggle(L10n.string("Ausgemustert"), isOn: $isRetired.animation())
                    if isRetired {
                        DatePicker(L10n.string("Ausgemustert am"),
                                   selection: $retiredDate,
                                   in: draft.inUseFrom...Date(),
                                   displayedComponents: [.date])
                    }
                } footer: {
                    Text(L10n.string("Trainings vor diesem Datum zählen nicht auf dieses Stück."))
                }

                Section {
                    Toggle(L10n.string("Passenden Trainings automatisch zuordnen"),
                           isOn: $draft.isAutomatic)
                } footer: {
                    Text(draft.isAutomatic
                         ? automaticFooter
                         : L10n.string("Dieses Stück wird nur den Trainings zugeordnet, bei denen du es selbst auswählst."))
                }

                Section(L10n.string("Austausch und Wartung")) {
                    if draft.kind.tracksDistance {
                        Toggle(L10n.string("Austausch nach Strecke"),
                               isOn: $hasReplacementTarget.animation())
                        if hasReplacementTarget {
                            stepperRow(value: $replacementKm, step: 50)
                        }
                    }
                    // Auch ohne Kilometer altert Material: Schaum in Schuhen
                    // wird hart, ob man sie laeuft oder nicht.
                    Toggle(L10n.string("Austausch nach Zeit"), isOn: $hasAgeLimit.animation())
                    if hasAgeLimit {
                        Stepper(value: $ageDays, in: 30...3650, step: 30) {
                            HStack {
                                Text(L10n.string("Nach"))
                                Spacer()
                                Text(ageDays % 365 == 0
                                     ? L10n.format("%lld Jahre", Int64(ageDays / 365))
                                     : L10n.format("%lld Tage", Int64(ageDays)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if draft.kind.tracksDistance {
                        Toggle(L10n.string("Wartung im Abstand"),
                               isOn: $hasServiceInterval.animation())
                        if hasServiceInterval {
                            stepperRow(value: $serviceKm, step: 50)
                            Button(L10n.string("Wartung jetzt eintragen")) {
                                draft.lastServiceAt = Date()
                                // Der Zaehler laeuft ab der Gesamtstrecke
                                // weiter; die steht in der Liste und wird
                                // dort aus den Trainings gerechnet.
                            }
                            .font(.footnote)
                        }
                    }
                }

                Section(L10n.string("Notiz")) {
                    TextField(L10n.string("Notiz"), text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(L10n.string("Ausrüstung"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Sichern")) {
                        var item = draft
                        item.retiredAt = isRetired ? retiredDate : nil
                        item.replaceAfterKm = hasReplacementTarget ? replacementKm : nil
                        item.replaceAfterDays = hasAgeLimit ? ageDays : nil
                        item.serviceEveryKm = hasServiceInterval ? serviceKm : nil
                        onSave(item)
                        dismiss()
                    }
                }
            }
        }
    }

    private var automaticFooter: String {
        let sports = draft.kind.automaticSportTypes
        guard !sports.isEmpty else {
            return L10n.string("Für diese Art gibt es keine passende Sportart – wähle sie beim Training selbst aus.")
        }
        let names = sports
            .map { SportTypeDisplay.activityType(for: $0).displayName }
            .sorted()
            .joined(separator: ", ")
        return L10n.format("Fällt automatisch bei: %@", names)
    }

    private func stepperRow(value: Binding<Double>, step: Double) -> some View {
        Stepper(value: value, in: 50...20000, step: step) {
            HStack {
                Text(L10n.string("Strecke"))
                Spacer()
                Text(WorkoutUnits.distance(km: value.wrappedValue, fractionDigits: 0))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
