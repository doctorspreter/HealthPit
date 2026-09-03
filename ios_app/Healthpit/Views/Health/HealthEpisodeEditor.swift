//
//  HealthEpisodeEditor.swift
//  Healthpit
//
//  Einen Tagebucheintrag anlegen oder ändern.
//
//  Die Auswahllisten für Begleiterscheinungen und Auslöser hängen am
//  Beschwerdebild. Wechselt es, bleibt nur stehen, was zum neuen Bild noch
//  passt — sonst schleppte eine Panikattacke eine Aura mit sich herum, weil
//  vorher Migräne ausgewählt war.
//

import SwiftUI

struct HealthEpisodeEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: HealthEpisode
    @State private var hasEnded: Bool
    @State private var endDate: Date

    private let onSave: (HealthEpisode) -> Void

    init(episode: HealthEpisode, onSave: @escaping (HealthEpisode) -> Void) {
        _draft = State(initialValue: episode)
        _hasEnded = State(initialValue: episode.endedAt != nil)
        _endDate = State(initialValue: episode.endedAt ?? episode.startedAt)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.string("Beschwerde"), selection: $draft.condition) {
                        ForEach(HealthCondition.allCases) { condition in
                            Text(L10n.string(condition.displayKey)).tag(condition)
                        }
                    }
                    .onChange(of: draft.condition) { _, _ in pruneToCondition() }

                    if !draft.condition.subtypes.isEmpty {
                        Picker(L10n.string("Ausprägung"), selection: $draft.subtype) {
                            Text(L10n.string("Ohne Angabe")).tag(EpisodeSubtype?.none)
                            ForEach(draft.condition.subtypes) { subtype in
                                Text(L10n.string(subtype.displayKey)).tag(EpisodeSubtype?.some(subtype))
                            }
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.string("Stärke"))
                            Spacer()
                            Text(draft.severity == 0
                                 ? L10n.string("Ohne Angabe")
                                 : "\(draft.severity)/10")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(draft.severity) },
                            set: { draft.severity = Int($0.rounded()) }
                        ), in: 0...10, step: 1)
                    }
                }

                Section {
                    DatePicker(L10n.string("Beginn"),
                               selection: $draft.startedAt,
                               in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                    Toggle(L10n.string("Vorbei"), isOn: $hasEnded.animation())
                    if hasEnded {
                        DatePicker(L10n.string("Ende"),
                                   selection: $endDate,
                                   in: draft.startedAt...Date(),
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                } footer: {
                    Text(hasEnded
                         ? L10n.string("Aus Beginn und Ende ergibt sich die Dauer.")
                         : L10n.string("Ohne Ende gilt die Episode als laufend."))
                }

                if !draft.condition.symptoms.isEmpty {
                    Section(L10n.string("Begleiterscheinungen")) {
                        ForEach(draft.condition.symptoms) { symptom in
                            toggleRow(L10n.string(symptom.displayKey),
                                      isOn: draft.symptoms.contains(symptom)) { on in
                                if on { draft.symptoms.insert(symptom) }
                                else { draft.symptoms.remove(symptom) }
                            }
                        }
                    }
                }

                if !draft.condition.triggers.isEmpty {
                    Section(L10n.string("Mögliche Auslöser")) {
                        ForEach(draft.condition.triggers) { trigger in
                            toggleRow(L10n.string(trigger.displayKey),
                                      isOn: draft.triggers.contains(trigger)) { on in
                                if on { draft.triggers.insert(trigger) }
                                else { draft.triggers.remove(trigger) }
                            }
                        }
                    }
                }

                Section(L10n.string("Medikament")) {
                    TextField(L10n.string("Name und Dosis"), text: $draft.medication)
                    if !draft.medication.isEmpty {
                        Picker(L10n.string("Hat es geholfen?"), selection: $draft.medicationHelped) {
                            Text(L10n.string("Ohne Angabe")).tag(Bool?.none)
                            Text(L10n.string("Ja")).tag(Bool?.some(true))
                            Text(L10n.string("Nein")).tag(Bool?.some(false))
                        }
                    }
                }

                Section(L10n.string("Notiz")) {
                    TextField(L10n.string("Notiz"), text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(L10n.string("Eintrag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Sichern")) {
                        var episode = draft
                        episode.endedAt = hasEnded ? endDate : nil
                        if episode.medication.isEmpty { episode.medicationHelped = nil }
                        onSave(episode)
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleRow(_ title: String,
                           isOn: Bool,
                           set: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: set))
            .font(.subheadline)
    }

    /// Nach einem Wechsel des Beschwerdebilds nur behalten, was dort vorkommt.
    private func pruneToCondition() {
        let allowedSymptoms = Set(draft.condition.symptoms)
        let allowedTriggers = Set(draft.condition.triggers)
        draft.symptoms.formIntersection(allowedSymptoms)
        draft.triggers.formIntersection(allowedTriggers)
        if let subtype = draft.subtype, !draft.condition.subtypes.contains(subtype) {
            draft.subtype = nil
        }
    }
}
