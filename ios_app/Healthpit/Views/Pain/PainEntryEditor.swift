//
//  PainEntryEditor.swift
//  Healthpit
//
//  Anlegen und Bearbeiten einer Beschwerde.
//
//  Auch ein aus dem Training uebernommener Eintrag laesst sich hier
//  bearbeiten: Er wird dabei in die Tabelle geschrieben und ersetzt von da an
//  die abgeleitete Fassung. So kann man einer im Training notierten Zerrung
//  hier ein Ende geben.
//

import SwiftUI

struct PainEntryEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PainEntry
    @State private var hasEnded: Bool
    @State private var endDate: Date

    private let onSave: (PainEntry) -> Void
    private let wasFromWorkout: Bool

    init(entry: PainEntry, onSave: @escaping (PainEntry) -> Void) {
        _draft = State(initialValue: entry)
        _hasEnded = State(initialValue: entry.endedAt != nil)
        _endDate = State(initialValue: entry.endedAt ?? entry.startedAt)
        self.onSave = onSave
        wasFromWorkout = entry.isFromWorkout
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.string("Art"), selection: $draft.kind) {
                        ForEach(PainEntryKind.allCases) { kind in
                            Text(L10n.string(kind.displayKey)).tag(kind)
                        }
                    }
                    Picker(L10n.string("Körperregion"), selection: $draft.region) {
                        ForEach(BodyRegion.allCases) { region in
                            Text(L10n.string(region.displayKey)).tag(region)
                        }
                    }
                    Picker(L10n.string("Schmerzart"), selection: $draft.quality) {
                        Text(L10n.string("Ohne Angabe")).tag(PainQuality?.none)
                        ForEach(PainQuality.allCases) { quality in
                            Text(L10n.string(quality.displayKey)).tag(PainQuality?.some(quality))
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
                        // Ganzzahlig: Zwischenwerte einer Schmerzskala sind
                        // nicht abzulesen und niemand meint 6,4.
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
                               displayedComponents: [.date])
                    Toggle(L10n.string("Beendet"), isOn: $hasEnded.animation())
                    if hasEnded {
                        DatePicker(L10n.string("Ende"),
                                   selection: $endDate,
                                   in: draft.startedAt...Date(),
                                   displayedComponents: [.date])
                    }
                } footer: {
                    Text(hasEnded
                         ? L10n.string("Der Kalender färbt jeden Tag von Beginn bis Ende ein.")
                         : L10n.string("Ohne Ende gilt die Beschwerde als laufend."))
                }

                Section(L10n.string("Notiz")) {
                    TextField(L10n.string("Notiz"), text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if wasFromWorkout {
                    Section {
                        Label(L10n.string("Dieser Eintrag stammt aus einem Training. Speichern übernimmt ihn hierher."),
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.string("Beschwerde"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Sichern")) {
                        var entry = draft
                        entry.endedAt = hasEnded ? endDate : nil
                        onSave(entry)
                        dismiss()
                    }
                }
            }
        }
    }
}
