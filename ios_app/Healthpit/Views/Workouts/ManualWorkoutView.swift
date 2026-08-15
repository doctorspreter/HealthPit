//
//  ManualWorkoutView.swift
//  Healthpit
//
//  Manuelle Trainingserfassung.
//

import SwiftUI
import CoreLocation
import Charts
import MapKit
import UniformTypeIdentifiers

struct ManualWorkoutView: View {
    let onSave: (LocalWorkout) -> Void
    private let draft: LocalWorkout?
    @Environment(\.dismiss) private var dismiss

    @State private var sport: String
    @State private var title: String
    @State private var start: Date
    @State private var durationMinutes: Double
    @State private var distanceKm: String
    @State private var energyKcal: String
    @State private var averageHeartRate: String
    @State private var maxHeartRate: String
    @State private var notes: String
    @State private var exportToAppleHealth = true
    @State private var message: String?
    @State private var isSaving = false
    @State private var repeatRule: WorkoutRepeatRule = .none
    @State private var repeatEnd = Date()
    /// Solange der Anwender das Enddatum nicht selbst gesetzt hat, zieht es mit
    /// der Rhythmusauswahl mit.
    @State private var repeatEndTouched = false
    @AppStorage(HealthDataSourceSettings.writeWorkoutsKey) private var appleHealthWorkoutWritingEnabled = true

    /// Der gespeicherte Wert bleibt bewusst deutsch: er wandert als `sport` in
    /// die Bridge und nach Home Assistant. Wuerde er mit der App-Sprache
    /// wechseln, entstuenden dort fuer dieselbe Sportart neue Entitaeten.
    /// Uebersetzt wird deshalb nur die Beschriftung.
    private let sports = ["Bouldern", "Squash", "Krafttraining", "Laufen", "Gehen", "Radfahren", "Sonstiges"]

    init(draft: LocalWorkout? = nil, onSave: @escaping (LocalWorkout) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _sport = State(initialValue: draft?.sport ?? "Bouldern")
        _title = State(initialValue: draft?.title ?? "")
        _start = State(initialValue: draft?.start ?? Date())
        let importedMinutes = draft.map { $0.duration / 60 } ?? 0
        _durationMinutes = State(initialValue: importedMinutes > 0 ? importedMinutes : 60)
        _distanceKm = State(initialValue: draft?.distanceKm.map {
            String(format: "%.2f", WorkoutUnits.distanceValue(km: $0))
        } ?? "")
        _energyKcal = State(initialValue: draft?.energyKcal.map { String(Int($0.rounded())) } ?? "")
        _averageHeartRate = State(initialValue: draft?.averageHeartRate.map { String(Int($0.rounded())) } ?? "")
        _maxHeartRate = State(initialValue: draft?.maxHeartRate.map { String(Int($0.rounded())) } ?? "")
        _notes = State(initialValue: draft?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("Training")) {
                    Picker(L10n.string("Sportart"), selection: $sport) {
                        ForEach(selectableSports, id: \.self) { Text(L10n.string($0)).tag($0) }
                    }
                    TextField(L10n.string("Titel optional"), text: $title)
                    DatePicker(L10n.string("Start"), selection: $start)
                    Stepper("\(Int(durationMinutes)) Minuten", value: $durationMinutes, in: 1...600, step: 5)
                }

                Section(L10n.string("Daten")) {
                    TextField(L10n.string("Distanz") + " \(WorkoutUnits.distanceSymbol)", text: $distanceKm)
                        .keyboardType(.decimalPad)
                    TextField(L10n.string("Kalorien"), text: $energyKcal)
                        .keyboardType(.decimalPad)
                    TextField(L10n.string("Ø Puls"), text: $averageHeartRate)
                        .keyboardType(.decimalPad)
                    TextField(L10n.string("Max Puls"), text: $maxHeartRate)
                        .keyboardType(.decimalPad)
                    TextField(L10n.string("Notizen"), text: $notes, axis: .vertical)
                }

                if draft == nil {
                    Section(L10n.string("Wiederholung")) {
                        Picker(L10n.string("Rhythmus"), selection: $repeatRule) {
                            ForEach(WorkoutRepeatRule.allCases) { rule in
                                Text(rule.title).tag(rule)
                            }
                        }
                        if repeatRule != .none {
                            DatePicker(L10n.string("Bis"), selection: $repeatEnd, in: start..., displayedComponents: .date)
                            Text(repeatSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle(L10n.string("Zu Apple Health hinzufügen"), isOn: $exportToAppleHealth)
                        .disabled(!appleHealthWorkoutWritingEnabled)
                    if !appleHealthWorkoutWritingEnabled {
                        Text(L10n.string("Der Export ist unter Einstellungen > Datenquellen > Apple Health deaktiviert."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                if !appleHealthWorkoutWritingEnabled {
                    exportToAppleHealth = false
                }
                repeatEnd = repeatRule.defaultEnd(from: start)
            }
            .onChange(of: repeatRule) { _, newValue in
                if !repeatEndTouched {
                    repeatEnd = newValue.defaultEnd(from: start)
                }
            }
            .onChange(of: start) { _, newValue in
                if !repeatEndTouched {
                    repeatEnd = repeatRule.defaultEnd(from: newValue)
                } else if repeatEnd < newValue {
                    repeatEnd = newValue
                }
            }
            .onChange(of: repeatEnd) { _, _ in
                repeatEndTouched = true
            }
            .navigationTitle(L10n.string("Training"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(L10n.string("Speichern"))
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    /// Die Termine, die dieses Formular gerade anlegen wuerde.
    private var selectableSports: [String] {
        ([sport] + sports).reduce(into: []) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }

    private var repeatDates: [Date] {
        repeatRule.occurrences(from: start, until: repeatEnd)
    }

    private var repeatSummary: String {
        let count = repeatDates.count
        if count >= WorkoutRepeatRule.maximumOccurrences {
            return L10n.format("%lld Trainings — mehr legt HealthPit auf einmal nicht an.", Int64(count))
        }
        return count == 1
            ? L10n.string("1 Training")
            : L10n.format("%lld Trainings", Int64(count))
    }

    private func workout(startingAt date: Date) -> LocalWorkout {
        LocalWorkout(id: draft?.id ?? UUID(),
                     source: draft?.source ?? .manual,
                     sport: sport,
                     title: title.isEmpty ? sport : title,
                     start: date,
                     end: date.addingTimeInterval(durationMinutes * 60),
                     // Eingabe steht in der angezeigten Einheit,
                     // gespeichert wird immer in Kilometern.
                     distanceKm: Double(distanceKm.replacingOccurrences(of: ",", with: "."))
                         .map(WorkoutUnits.kilometers(fromDisplayDistance:)),
                     energyKcal: Double(energyKcal.replacingOccurrences(of: ",", with: ".")),
                     averageHeartRate: Double(averageHeartRate.replacingOccurrences(of: ",", with: ".")),
                     maxHeartRate: Double(maxHeartRate.replacingOccurrences(of: ",", with: ".")),
                     notes: notes,
                     weather: draft?.weather,
                     injury: draft?.injury,
                     route: draft?.route ?? [],
                     exercises: draft?.exercises ?? [])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let workouts = repeatDates.map(workout(startingAt:))
        for item in workouts {
            onSave(item)
        }

        if exportToAppleHealth {
            var failed = 0
            var lastError: Error?
            for item in workouts {
                do {
                    try await HealthKitManager.shared.saveToAppleHealth(item)
                } catch {
                    // Ein einzelner fehlgeschlagener Export darf die uebrigen
                    // Termine nicht verschlucken; lokal liegen sie ohnehin schon.
                    failed += 1
                    lastError = error
                }
            }
            if failed > 0 {
                message = L10n.format("Lokal gespeichert, %lld Apple-Health-Exporte fehlgeschlagen:", Int64(failed))
                    + " \(lastError?.localizedDescription ?? "")"
                return
            }
        }
        dismiss()
    }
}

struct LocalWorkoutDetailView: View {
    let workout: LocalWorkout
    var records: [WorkoutRecord] = []
    var healthWorkout: WorkoutSummary?
    @State private var fallbackHeartRate: HeartRateSummary?
    @State private var healthDetail: WorkoutDetail?
    @State private var isLoadingHeartRate = false
    @State private var isExportingToAppleHealth = false
    @State private var appleHealthMessage: String?
    @State private var showingSplitTable = false
    @State private var injuryLocation = ""
    @State private var injuryPainType = ""
    @State private var injurySeverity = 0
    @State private var isSavingInjury = false
    @State private var showingRouteImporter = false
    @State private var isImportingRoute = false
    @State private var routeImportMessage: String?
    @State private var savedWorkoutOverride: LocalWorkout?
    @AppStorage(HealthDataSourceSettings.writeWorkoutsKey) private var appleHealthWorkoutWritingEnabled = true
    private let statColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let injuryLocations = ["", "Knie links", "Knie rechts", "Schulter links", "Schulter rechts", "Rücken", "Hüfte", "Fuß", "Handgelenk", "Ellbogen", "Sonstiges"]
    private let painTypes = ["", "leichtes Ziehen", "stechend", "dumpf", "Druck", "Brennen", "Instabil", "Sonstiges"]

    private var sourceDisplayName: String {
        if let sourceName = healthWorkout?.sourceName, !sourceName.isEmpty {
            return "Apple Health · \(sourceName)"
        }
        return workout.source.displayName
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.title)
                        .font(.headline)
                    Text(workout.start, format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(sourceDisplayName, systemImage: "tray.full")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if healthWorkout == nil {
                Section {
                    Button {
                        Task { await exportToAppleHealth() }
                    } label: {
                        HStack {
                            if isExportingToAppleHealth {
                                ProgressView()
                            }
                            Label(L10n.string("Zu Apple Health hinzufügen"), systemImage: "heart.badge.plus")
                        }
                    }
                    .disabled(isExportingToAppleHealth || !appleHealthWorkoutWritingEnabled)

                    if !appleHealthWorkoutWritingEnabled {
                        Text(L10n.string("Der Export ist in den Datenquellen-Einstellungen deaktiviert."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let appleHealthMessage {
                        Text(appleHealthMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.string("Karte")) {
                if routeMapPoints.count > 1 {
                    WorkoutRouteMapView(points: routeMapPoints, splits: splits, isCycling: isCycling)
                }
                Button {
                    showingRouteImporter = true
                } label: {
                    if isImportingRoute {
                        ProgressView()
                    } else {
                        Label(effectiveRoute.isEmpty ? "Karte hinzufügen" : "Karte ersetzen",
                              systemImage: "map.badge.plus")
                    }
                }
                .disabled(isImportingRoute)

                if let routeImportMessage {
                    Text(routeImportMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !records.isEmpty {
                Section(L10n.string("Rekorde")) {
                    ForEach(records) { record in
                        Label {
                            HStack {
                                Text(record.localizedTitle)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(record.localizedValue)
                                        .foregroundStyle(.secondary)
                                    Text(record.localizedSubtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "trophy.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }
            if !workout.exercises.isEmpty {
                Section(L10n.string("Übungen")) {
                    ForEach(workout.exercises) { exercise in
                        NavigationLink {
                            StrengthExerciseDetailView(exercise: StrengthExerciseAnalyzer.row(for: exercise,
                                                                                              workout: workout))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(exercise.name)
                                    .font(.headline)
                                Text(L10n.format(
                                    "%lld Sätze · %@",
                                    Int64(exercise.sets.count),
                                    formatKg(exercise.sets.map { $0.volumeKg ?? (($0.weightKg ?? 0) * ($0.reps ?? 0)) }.reduce(0, +))
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            Section {
                LazyVGrid(columns: statColumns, spacing: 12) {
                    stat("Dauer", durationText(workout.duration))
                    stat("Distanz", effectiveWorkout.distanceKm.map { WorkoutUnits.distance(km: $0, fractionDigits: 2) } ?? "-")
                    stat("Kalorien", effectiveWorkout.energyKcal.map { "\(Int($0.rounded())) kcal" } ?? "-")
                    stat("Ø Puls", effectiveHeartRate.map { "\(Int($0.average.rounded())) bpm" } ?? "-")
                }
            }
            if let tempo = tempoText {
                Section(L10n.string("Tempo")) {
                    Label(tempo, systemImage: isCycling ? "speedometer" : "timer")
                }
            }
            if !mergedHealthStats.isEmpty {
                Section(L10n.string("Weitere Trainingswerte")) {
                    ForEach(mergedHealthStats) { stat in
                        Label {
                            HStack {
                                Text(stat.localizedLabel)
                                Spacer()
                                Text(stat.value).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: stat.systemImage)
                        }
                    }
                }
            }
            if let weather = workout.weather, !weather.summary.isEmpty {
                Section(L10n.string("Wetter")) {
                    Label(weather.summary, systemImage: "cloud.sun.fill")
                }
            }
            if !splits.isEmpty {
                Section(L10n.string("Trainingsverlauf")) {
                    WorkoutSampleTimelineChartView(samples: timelineSamples,
                                                   heartRate: effectiveHeartRate,
                                                   isCycling: isCycling)

                    DisclosureGroup(WorkoutUnits.isImperial ? L10n.string("Meilen anzeigen") : L10n.string("Kilometer anzeigen"),
                                    isExpanded: $showingSplitTable) {
                        ForEach(splits) { split in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(WorkoutUnits.distanceSymbol) \(split.id)")
                                        .font(.subheadline.bold())
                                    Text(splitDurationText(split.duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(isCycling ? speedText(split.averageSpeedKmh) : paceText(split.paceSecondsPerKm))
                                        .font(.subheadline.bold())
                                    Text(splitHeartRate(split).map { "Ø \(Int($0.rounded())) bpm" } ?? "Puls -")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if hasTimelineData {
                Section(L10n.string("Messwerte")) {
                    WorkoutSampleTimelineChartView(samples: timelineSamples,
                                                   heartRate: effectiveHeartRate,
                                                   isCycling: isCycling)
                }
            }
            if let heartRate = effectiveHeartRate {
                Section(L10n.string("Puls")) {
                    HStack(spacing: 12) {
                        stat("Min", "\(Int(heartRate.minimum.rounded())) bpm")
                        stat("Ø", "\(Int(heartRate.average.rounded())) bpm")
                        stat("Max", "\(Int(heartRate.maximum.rounded())) bpm")
                    }
                }
            } else if isLoadingHeartRate {
                Section(L10n.string("Puls")) {
                    ProgressView()
                }
            }
            if !workout.notes.isEmpty {
                Section(L10n.string("Notizen")) {
                    Text(workout.notes)
                }
            }
            Section(L10n.string("Verletzung")) {
                Picker(L10n.string("Ort"), selection: $injuryLocation) {
                    ForEach(injuryLocations, id: \.self) { Text($0.isEmpty ? L10n.string("Keine") : L10n.string($0)).tag($0) }
                }
                Picker(L10n.string("Schmerzart"), selection: $injuryPainType) {
                    ForEach(painTypes, id: \.self) { Text($0.isEmpty ? L10n.string("Keine") : L10n.string($0)).tag($0) }
                }
                Picker(L10n.string("Stärke"), selection: $injurySeverity) {
                    ForEach(0...10, id: \.self) { Text($0 == 0 ? "Keine" : "\($0) von 10").tag($0) }
                }
                Button {
                    Task { await saveInjury() }
                } label: {
                    if isSavingInjury {
                        ProgressView()
                    } else {
                        Label(L10n.string("Verletzung speichern"), systemImage: "bandage.fill")
                    }
                }
                .disabled(isSavingInjury)
            }
            if !effectiveRoute.isEmpty {
                Section(L10n.string("Quellen")) {
                    Text("\(effectiveRoute.count) Routenpunkte gespeichert.")
                }
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadHealthDetail()
            await loadFallbackHeartRate()
            SyncRefreshStatusStore.markLocalRefresh()
        }
        .task(id: workout.id) {
            injuryLocation = workout.injury?.location ?? ""
            injuryPainType = workout.injury?.painType ?? ""
            injurySeverity = workout.injury?.severity ?? 0
            await loadFallbackHeartRate()
            await loadHealthDetail()
        }
        .fileImporter(isPresented: $showingRouteImporter,
                      allowedContentTypes: [.xml, UTType(filenameExtension: "gpx") ?? .xml],
                      allowsMultipleSelection: false) { result in
            Task { await importRoute(result) }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.headline)
            Text(L10n.string(title)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        formatWorkoutDuration(seconds)
    }

    private var tempoText: String? {
        guard let km = effectiveWorkout.distanceKm, km > 0, effectiveWorkout.duration > 0 else { return nil }
        if isCycling {
            return speedText(km / (effectiveWorkout.duration / 3600))
        }
        return paceText(effectiveWorkout.duration / km)
    }

    private var isCycling: Bool {
        workout.sport.localizedCaseInsensitiveContains("rad")
            || workout.sport.localizedCaseInsensitiveContains("bike")
            || workout.sport.localizedCaseInsensitiveContains("cycle")
    }

    private var routeMapPoints: [WorkoutRouteMapPoint] {
        effectiveRoute.map {
            WorkoutRouteMapPoint(latitude: $0.latitude,
                                 longitude: $0.longitude,
                                 timestamp: $0.timestamp)
        }
    }

    private var effectiveWorkout: LocalWorkout {
        savedWorkoutOverride ?? workout
    }

    private var effectiveRoute: [LocalRoutePoint] {
        if !effectiveWorkout.route.isEmpty {
            return effectiveWorkout.route
        }
        return (healthDetail?.route ?? []).map {
            LocalRoutePoint(latitude: $0.latitude,
                            longitude: $0.longitude,
                            elevation: $0.elevation,
                            timestamp: $0.timestamp,
                            heartRate: nil)
        }
    }

    private func importRoute(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                routeImportMessage = error.localizedDescription
            }
            return
        }

        isImportingRoute = true
        routeImportMessage = nil
        defer { isImportingRoute = false }

        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        do {
            let imported = try WorkoutFileImporter.analyze(from: url)
            guard imported.workout.route.count > 1 else {
                routeImportMessage = L10n.string("Die Datei enthält keine verwendbare Strecke.")
                return
            }

            let base = effectiveWorkout
            var updated: LocalWorkout
            if let healthWorkout,
               base.source == .appleHealth,
               base.id == healthWorkout.uuid {
                updated = LocalWorkout(id: UUID(),
                                       source: imported.workout.source,
                                       sport: base.sport,
                                       title: base.title,
                                       start: base.start,
                                       end: base.end,
                                       distanceKm: base.distanceKm,
                                       energyKcal: base.energyKcal,
                                       averageHeartRate: base.averageHeartRate,
                                       maxHeartRate: base.maxHeartRate,
                                       notes: base.notes,
                                       weather: base.weather,
                                       injury: base.injury,
                                       route: [],
                                       exercises: base.exercises)
            } else {
                updated = base
            }

            updated.route = route(imported.workout.route, alignedTo: updated.start)
            updated.distanceKm = imported.workout.distanceKm ?? updated.distanceKm
            updated.energyKcal = imported.workout.energyKcal ?? updated.energyKcal
            updated.averageHeartRate = imported.workout.averageHeartRate ?? updated.averageHeartRate
            updated.maxHeartRate = imported.workout.maxHeartRate ?? updated.maxHeartRate

            await ManualWorkoutWriter.save(updated)
            savedWorkoutOverride = updated
            _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
            routeImportMessage = L10n.string("Karte wurde zum Training hinzugefügt.")
        } catch {
            routeImportMessage = error.localizedDescription
        }
    }

    private func route(_ points: [LocalRoutePoint], alignedTo targetStart: Date) -> [LocalRoutePoint] {
        guard let sourceStart = points.compactMap(\.timestamp).min() else { return points }
        let offset = targetStart.timeIntervalSince(sourceStart)
        return points.map { point in
            var shifted = point
            shifted.timestamp = point.timestamp?.addingTimeInterval(offset)
            return shifted
        }
    }

    private var timelineSamples: [WorkoutTimelineSample] {
        effectiveRoute.map {
            WorkoutTimelineSample(timestamp: $0.timestamp,
                                  latitude: $0.latitude,
                                  longitude: $0.longitude,
                                  elevation: $0.elevation,
                                  heartRate: $0.heartRate)
        }
    }

    private var hasTimelineData: Bool {
        !timelineSamples.isEmpty || effectiveHeartRate?.samples.isEmpty == false
    }

    private var importedHeartRate: HeartRateSummary? {
        let points = effectiveRoute.compactMap { point -> HeartRatePoint? in
            guard let date = point.timestamp,
                  let bpm = point.heartRate,
                  bpm > 0,
                  bpm.isFinite else {
                return nil
            }
            return HeartRatePoint(date: date, bpm: bpm)
        }
        if !points.isEmpty {
            let values = points.map(\.bpm)
            return HeartRateSummary(average: values.reduce(0, +) / Double(values.count),
                                    minimum: values.min() ?? 0,
                                    maximum: values.max() ?? 0,
                                    samples: points)
        }
        if let average = effectiveWorkout.averageHeartRate {
            return HeartRateSummary(average: average,
                                    minimum: average,
                                    maximum: effectiveWorkout.maxHeartRate ?? average,
                                    samples: [])
        }
        if let max = effectiveWorkout.maxHeartRate {
            return HeartRateSummary(average: max, minimum: max, maximum: max, samples: [])
        }
        return nil
    }

    private var effectiveHeartRate: HeartRateSummary? {
        if let importedHeartRate, importedHeartRate.samples.isEmpty == false {
            return importedHeartRate
        }
        if let healthHeartRate = healthDetail?.heartRate {
            return healthHeartRate
        }
        guard let importedHeartRate else { return fallbackHeartRate }
        return HeartRateSummary(average: importedHeartRate.average,
                                minimum: importedHeartRate.minimum,
                                maximum: importedHeartRate.maximum,
                                samples: fallbackHeartRate?.samples ?? importedHeartRate.samples)
    }

    private var mergedHealthStats: [WorkoutStat] {
        guard let stats = healthDetail?.stats else { return [] }
        var duplicateLabels: Set<String> = [
            "dauer",
            "distanz",
            "kalorien",
            "aktive kalorien",
            "ø puls",
            "max puls",
            "min puls",
        ]
        if tempoText != nil {
            duplicateLabels.formUnion(["ø geschwindigkeit", "ø pace", "ø tempo"])
        }
        return stats.filter { stat in
            let label = stat.label.normalizedWorkoutStatLabel
            if duplicateLabels.contains(label) { return false }
            if label.hasPrefix("distanz") { return false }
            if label.contains("kalorien") { return false }
            if label.contains("puls") { return false }
            return true
        }
    }

    private var elevationGainBySplit: [Int: Double] {
        Dictionary(uniqueKeysWithValues: splits.compactMap { split in
            guard let gain = elevationGain(for: split), gain > 0 else { return nil }
            return (split.id, gain)
        })
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.005))
        return MKCoordinateRegion(center: center, span: span)
    }

    private func loadFallbackHeartRate() async {
        guard importedHeartRate?.samples.isEmpty != false else { return }
        isLoadingHeartRate = true
        defer { isLoadingHeartRate = false }
        fallbackHeartRate = try? await HealthKitManager.shared.heartRateSummary(start: workout.start, end: workout.end)
    }

    private func loadHealthDetail() async {
        guard let healthWorkout else { return }
        healthDetail = try? await HealthKitManager.shared.workoutDetail(for: healthWorkout.uuid)
    }

    private func exportToAppleHealth() async {
        isExportingToAppleHealth = true
        appleHealthMessage = nil
        defer { isExportingToAppleHealth = false }
        do {
            try await HealthKitManager.shared.saveToAppleHealth(effectiveWorkout)
            appleHealthMessage = L10n.string("Training wurde an Apple Health übergeben.")
        } catch {
            appleHealthMessage = error.localizedDescription
        }
    }

    private func saveInjury() async {
        isSavingInjury = true
        defer { isSavingInjury = false }
        var updated = effectiveWorkout
        let injury = WorkoutInjury(location: injuryLocation,
                                   painType: injuryPainType,
                                   severity: injurySeverity)
        updated.injury = injury.isEmpty ? nil : injury
        await ManualWorkoutWriter.save(updated)
        savedWorkoutOverride = updated
        _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
    }

    private var splits: [WorkoutSplit] {
        if effectiveWorkout.route.isEmpty, let healthSplits = healthDetail?.splits, !healthSplits.isEmpty {
            return healthSplits
        }
        let route = effectiveRoute
        guard route.count > 1 else { return [] }
        var out: [WorkoutSplit] = []
        var kmStart = route[0]
        var previous = route[0]
        var accumulatedMeters = 0.0
        var nextKm = 1000.0

        for point in route.dropFirst() {
            let a = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let b = CLLocation(latitude: point.latitude, longitude: point.longitude)
            accumulatedMeters += a.distance(from: b)
            previous = point

            if accumulatedMeters >= nextKm,
               let startTime = kmStart.timestamp,
               let endTime = point.timestamp {
                let duration = max(endTime.timeIntervalSince(startTime), 1)
                out.append(WorkoutSplit(id: out.count + 1,
                                        distanceKm: nextKm / 1000,
                                        duration: duration,
                                        averageSpeedKmh: 3600 / duration,
                                        paceSecondsPerKm: duration,
                                        start: startTime,
                                        end: endTime))
                kmStart = point
                nextKm += 1000
            }
        }
        return out
    }

    private func paceText(_ secondsPerKm: TimeInterval) -> String {
        WorkoutUnits.pace(secondsPerKilometer: Int(secondsPerKm.rounded()))
    }

    private func speedText(_ value: Double) -> String {
        WorkoutUnits.speed(kmh: value)
    }

    private func splitDurationText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private func splitHeartRate(_ split: WorkoutSplit) -> Double? {
        guard let start = split.start,
              let end = split.end,
              let samples = effectiveHeartRate?.samples,
              !samples.isEmpty else {
            return nil
        }
        let values = samples
            .filter { $0.date >= start && $0.date <= end }
            .map(\.bpm)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func elevationGain(for split: WorkoutSplit) -> Double? {
        guard let start = split.start, let end = split.end else { return nil }
        let points = effectiveRoute
            .filter { point in
                guard let timestamp = point.timestamp else { return false }
                return timestamp >= start && timestamp <= end && point.elevation != nil
            }
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        guard points.count > 1 else { return nil }
        var gain = 0.0
        var previous = points[0].elevation ?? 0
        for point in points.dropFirst() {
            guard let elevation = point.elevation else { continue }
            gain += max(elevation - previous, 0)
            previous = elevation
        }
        return gain
    }
}
