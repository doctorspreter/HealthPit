//
//  UndatedWorkoutImportView.swift
//  Healthpit
//
//  Ordnet eine GPX/TCX-Datei ohne Zeitstempel einem Training zu.
//

import SwiftUI

struct UndatedWorkoutImportView: View {
    let imported: WorkoutFileImport
    let workouts: [UnifiedWorkout]
    let onSave: (LocalWorkout) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isAttaching = false
    @State private var showingManualWorkout = false
    @State private var didCreateManualWorkout = false
    @State private var selectedSport: String

    private let commonSports = ["Bouldern", "Squash", "Krafttraining", "Laufen", "Gehen", "Radfahren", "Sonstiges"]

    init(imported: WorkoutFileImport,
         workouts: [UnifiedWorkout],
         onSave: @escaping (LocalWorkout) -> Void) {
        self.imported = imported
        self.workouts = workouts
        self.onSave = onSave
        _selectedSport = State(initialValue: imported.workout.sport)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.string("Aus der Datei erkannt")) {
                    LabeledContent(L10n.string("Datei"), value: imported.workout.title)
                    Picker(L10n.string("Sportart"), selection: $selectedSport) {
                        ForEach(selectableSports, id: \.self) { sport in
                            Text(L10n.string(sport)).tag(sport)
                        }
                    }
                    if let distance = imported.workout.distanceKm {
                        LabeledContent(L10n.string("Distanz"), value: WorkoutUnits.distance(km: distance, fractionDigits: 2))
                    }
                    LabeledContent(L10n.string("Streckenpunkte"), value: "\(imported.workout.route.count)")
                    if let heartRate = imported.workout.averageHeartRate {
                        LabeledContent(L10n.string("Ø Puls"), value: "\(Int(heartRate.rounded())) bpm")
                    }
                    Text(L10n.string("Die Datei enthält kein Datum. Wähle das passende Training oder lege ein neues mit den erkannten Daten an."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showingManualWorkout = true
                    } label: {
                        Label(L10n.string("Neues Training manuell erstellen"), systemImage: "plus.circle")
                    }
                }

                Section(L10n.string("Zu vorhandenem Training hinzufügen")) {
                    if filteredWorkouts.isEmpty {
                        ContentUnavailableView(L10n.string("Keine passenden Trainings"),
                                               systemImage: "figure.run",
                                               description: Text(L10n.string("Lege stattdessen ein neues Training an.")))
                    } else {
                        ForEach(filteredWorkouts) { item in
                            Button {
                                attach(to: item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.symbol)
                                        .foregroundStyle(HealthCategory.workouts.tint)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .foregroundStyle(.primary)
                                        Text(item.startDate,
                                             format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isAttaching {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isAttaching)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Training suchen")
            .navigationTitle(L10n.string("GPX ohne Datum"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("Abbrechen")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingManualWorkout, onDismiss: {
                if didCreateManualWorkout {
                    dismiss()
                }
            }) {
                ManualWorkoutView(draft: preparedWorkout) { workout in
                    onSave(workout)
                    didCreateManualWorkout = true
                }
            }
        }
    }

    private var filteredWorkouts: [UnifiedWorkout] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return workouts
        }
        let query = searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return workouts.filter { item in
            item.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query)
                || item.startDate.formatted(date: .numeric, time: .omitted).contains(query)
        }
    }

    private var selectableSports: [String] {
        ([imported.workout.sport] + commonSports).reduce(into: []) { result, sport in
            if !result.contains(sport) { result.append(sport) }
        }
    }

    private var preparedWorkout: LocalWorkout {
        var workout = imported.workout
        workout.sport = selectedSport
        return workout
    }

    private func attach(to item: UnifiedWorkout) {
        isAttaching = true
        Task {
            let workout = await mergedWorkout(for: item)
            onSave(workout)
            dismiss()
        }
    }

    private func mergedWorkout(for item: UnifiedWorkout) async -> LocalWorkout {
        if let localSummary = item.local {
            var workout = await LocalWorkoutStore.shared.fullWorkout(id: localSummary.id) ?? localSummary
            workout.route = imported.workout.route
            workout.distanceKm = imported.workout.distanceKm ?? workout.distanceKm
            workout.energyKcal = imported.workout.energyKcal ?? workout.energyKcal
            workout.averageHeartRate = imported.workout.averageHeartRate ?? workout.averageHeartRate
            workout.maxHeartRate = imported.workout.maxHeartRate ?? workout.maxHeartRate
            return workout
        }

        if let health = item.health {
            return LocalWorkout(id: UUID(),
                                source: imported.workout.source,
                                sport: health.activityName,
                                title: health.activityName,
                                start: health.start,
                                end: health.end,
                                distanceKm: imported.workout.distanceKm ?? health.distanceKm,
                                energyKcal: imported.workout.energyKcal ?? health.energyKcal,
                                averageHeartRate: imported.workout.averageHeartRate,
                                maxHeartRate: imported.workout.maxHeartRate,
                                notes: "",
                                weather: health.weather,
                                injury: health.injury,
                                route: imported.workout.route)
        }

        // `UnifiedWorkout` enthaelt immer mindestens eine Quelle. Der Fallback
        // haelt die Funktion trotzdem total und wird nicht als undatierter
        // Datensatz gespeichert, weil die Auswahl nur aus `workouts` stammt.
        return imported.workout
    }
}
