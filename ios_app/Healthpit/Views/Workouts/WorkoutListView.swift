//
//  WorkoutListView.swift
//  Healthpit
//
//  Gemeinsame Workout-Liste aus Apple Health und lokalen Importen.
//

import Charts
import SwiftUI
import UniformTypeIdentifiers

struct WorkoutListView: View {
    private let health = HealthKitManager.shared

    private let importTypes: [UTType] = [
        .xml,
        UTType(filenameExtension: "gpx") ?? .xml,
        UTType(filenameExtension: "tcx") ?? .xml,
    ]

    @State private var range: TimeRange = .month
    @State private var healthWorkouts: [WorkoutSummary] = []
    @State private var allTimeHealthWorkouts: [WorkoutSummary] = []
    @State private var localWorkouts: [LocalWorkout] = []
    @State private var items: [UnifiedWorkout] = []
    @State private var allTimeItems: [UnifiedWorkout] = []
    @State private var referenceDate = Date()
    @State private var isLoading = false
    @State private var showingImporter = false
    @State private var showingManualWorkout = false
    @State private var undatedImport: WorkoutFileImport?
    @State private var queuedUndatedImports: [WorkoutFileImport] = []
    @State private var itemPendingDeletion: UnifiedWorkout?
    @State private var showingDeleteConfirmation = false
    @State private var showingSyncStatus = false
    @State private var hasLoadedData = false

    var body: some View {
        List {
            Section {
                ProfessionalPageHero(
                    eyebrow: range.title,
                    title: "Training",
                    subtitle: "Einheiten, Belastung und Fortschritt in einer klaren Trainingsübersicht.",
                    symbol: "figure.run.circle.fill",
                    tint: .green,
                    value: items.isEmpty ? "–" : "\(items.count)",
                    detail: items.count == 1 ? "Einheit" : "Einheiten"
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if showingSyncStatus {
                SyncRefreshStatusView()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker(L10n.string("Zeitraum"), selection: $range) {
                    ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(5)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            WorkoutRangeOverview(range: range,
                                 referenceDate: $referenceDate,
                                 items: items,
                                 sportItems: allTimeItems)

            Section {
                NavigationLink {
                    WorkoutSportListView(items: allTimeItems) { item in
                        itemPendingDeletion = item
                        showingDeleteConfirmation = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.mixed.cardio")
                            .foregroundStyle(.green)
                            .frame(width: 36, height: 36)
                            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string("Sportarten")).font(.subheadline.weight(.semibold))
                            Text(L10n.string("Alle Einheiten nach Disziplin")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .professionalCard(tint: .green)
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 8, trailing: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if items.isEmpty {
                ContentUnavailableView(L10n.string("Keine Workouts"),
                                       systemImage: "figure.run",
                                       description: Text(L10n.string("Im gewählten Zeitraum sind keine Workouts vorhanden.")))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        UnifiedWorkoutDetailView(item: item,
                                                 records: [])
                    } label: {
                        UnifiedWorkoutRow(item: item, records: [])
                            .padding(14)
                            .professionalCard(tint: .green)
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) {
                            itemPendingDeletion = item
                            showingDeleteConfirmation = true
                        } label: {
                            Label(L10n.string("Löschen"), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .professionalPageBackground(tint: .green)
        .navigationTitle(L10n.string("Workouts"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingImporter = true
                    } label: {
                        Label(L10n.string("GPX/TCX importieren"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await refreshCurrentRange() }
                    } label: {
                        Label(L10n.string("Aktualisieren"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        showingManualWorkout = true
                    } label: {
                        Label(L10n.string("Training manuell"), systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingManualWorkout) {
            ManualWorkoutView { workout in
                Task {
                    await ManualWorkoutWriter.save(workout)
                    _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
                    await loadCached()
                }
            }
        }
        .sheet(item: $undatedImport, onDismiss: presentNextUndatedImport) { imported in
            UndatedWorkoutImportView(imported: imported,
                                     workouts: allTimeItems) { workout in
                Task {
                    await ManualWorkoutWriter.save(workout)
                    _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
                    await loadCached()
                }
            }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importTypes,
                      allowsMultipleSelection: true) { result in
            Task { await importFiles(result) }
        }
        .task {
            guard !hasLoadedData else { return }
            await loadCached()
            await refreshImportedWorkouts()
        }
        .refreshable {
            await refreshImportedWorkouts()
            await refreshLocalAppleHealthRange()
            SyncRefreshStatusStore.markLocalRefresh()
        }
        .onChange(of: range) { _, _ in
            showingSyncStatus = false
            filterItemsForSelectedRange()
        }
        .onChange(of: referenceDate) { _, _ in
            showingSyncStatus = false
            filterItemsForSelectedRange()
        }
        .onChange(of: showingManualWorkout) { _, isShowing in
            if isShowing { showingSyncStatus = false }
        }
        .onChange(of: showingImporter) { _, isShowing in
            if isShowing { showingSyncStatus = false }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4).onChanged { _ in
                showingSyncStatus = false
            }
        )
        .onDisappear { showingSyncStatus = false }
        .confirmationDialog(L10n.string("Workout entfernen?"),
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible,
                            presenting: itemPendingDeletion) { item in
            Button(L10n.string("Entfernen"), role: .destructive) {
                Task { await deleteWorkout(item) }
            }
            Button(L10n.string("Abbrechen"), role: .cancel) {}
        } message: { item in
            Text(deleteWarning(for: item))
        }
    }

    private func loadCached() async {
        isLoading = items.isEmpty
        await reloadFromDatabase()
        hasLoadedData = true
        isLoading = false
    }

    /// Alles aus der Datenbank. Dort liegt jedes Training genau einmal –
    /// selbst angelegte, aus Apple Health und ueber die Bridge importierte.
    private func reloadFromDatabase() async {
        // Ohne Filter: Was geloescht ist, gibt die Datenbank gar nicht heraus.
        allTimeItems = await HealthQuery.shared.unifiedWorkouts()
        filterItemsForSelectedRange()
    }

    private func refreshCurrentRange() async {
        isLoading = items.isEmpty
        async let syncCount: Int? = try? BridgeSyncService.shared.syncNow()

        _ = await syncCount
        // Erst Neues aus Apple Health in die Datenbank holen, dann von dort
        // lesen. Zwei Schritte, aber nur eine Wahrheit.
        _ = try? await HealthPitBootstrap.shared.refresh()
        await reloadFromDatabase()
        isLoading = false
        SyncRefreshStatusStore.markLocalRefresh()
        showingSyncStatus = true
    }

    /// Home Assistant carries the rich GymPit copy with exercises and sets.
    /// Apple Health only supplies the workout summary, so a local HealthKit
    /// refresh alone cannot make a strength workout complete.
    private func refreshImportedWorkouts() async {
        _ = try? await BridgeSyncService.shared.downloadImportedWorkouts()
        await reloadFromDatabase()
    }

    private func refreshLocalAppleHealthRange() async {
        isLoading = items.isEmpty
        _ = try? await HealthPitBootstrap.shared.refresh()
        await reloadFromDatabase()
        isLoading = false
    }

    private func rebuildItems(allTimeHealth: [WorkoutSummary]? = nil) {
        if let allTimeHealth {
            allTimeHealthWorkouts = allTimeHealth
        }
        let sourceHealth = allTimeHealthWorkouts.isEmpty ? healthWorkouts : allTimeHealthWorkouts
        allTimeItems = UnifiedWorkoutBuilder.build(health: sourceHealth,
                                                   local: localWorkouts)
        filterItemsForSelectedRange()
    }

    private func filterItemsForSelectedRange() {
        let interval = range.dateInterval(referenceDate: referenceDate)
        items = allTimeItems.filter { interval.contains($0.startDate) }
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result else { return }
        var savedDatedWorkout = false
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let imported = try? WorkoutFileImporter.analyze(from: url) {
                if imported.containsDate {
                    await ManualWorkoutWriter.save(imported.workout)
                    savedDatedWorkout = true
                } else {
                    queuedUndatedImports.append(imported)
                }
            }
        }
        if savedDatedWorkout {
            _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
        }
        await loadCached()
        if !queuedUndatedImports.isEmpty {
            await loadAllWorkoutCandidatesForImport()
        }
        presentNextUndatedImport()
    }

    private func loadAllWorkoutCandidatesForImport() async {
        await reloadFromDatabase()
    }

    private func presentNextUndatedImport() {
        guard undatedImport == nil, !queuedUndatedImports.isEmpty else { return }
        undatedImport = queuedUndatedImports.removeFirst()
    }

    private func deleteWorkout(_ item: UnifiedWorkout) async {
        // In der Datenbank, an einer Stelle. Weich geloescht, damit derselbe
        // Datensatz beim naechsten Import nicht wieder hereinkommt.
        if let workoutID = WorkoutID(item.id) {
            await ManualWorkoutWriter.delete(workoutID: workoutID)
        }
        if let local = item.local {
            await LocalWorkoutStore.shared.delete(id: local.id)
            _ = try? await BridgeSyncService.shared.deleteImportedWorkout(id: local.id)
        }
        if let health = item.health {
            _ = try? await BridgeSyncService.shared.deleteImportedWorkout(id: health.uuid)
        }
        await reloadFromDatabase()
    }

    private func deleteWarning(for item: UnifiedWorkout) -> String {
        var parts: [String] = []
        if item.local != nil {
            parts.append("Importierte oder manuelle Daten werden lokal und in der Bridge gelöscht.")
        }
        if item.health != nil {
            parts.append("Apple-Health-Daten werden in dieser App ausgeblendet; Apple Health selbst bleibt unverändert.")
        }
        return parts.joined(separator: " ")
    }

}

struct UnifiedWorkout: Identifiable {
    let id: String
    let health: WorkoutSummary?
    let local: LocalWorkout?
    let startDate: Date

    nonisolated init(id: String,
                     health: WorkoutSummary?,
                     local: LocalWorkout?) {
        self.id = id
        self.health = health
        self.local = local
        startDate = local?.start
            ?? health?.start
            ?? .distantPast
    }

    nonisolated var title: String {
        if let local { return L10n.string(local.sport) }
        return health?.activityName ?? L10n.string("Workout")
    }

    nonisolated var symbol: String {
        if let local {
            switch local.sport.lowercased() {
            case "bouldern": return "figure.climbing"
            case "squash": return "figure.tennis"
            default: return "figure.run"
            }
        }
        return health?.symbol ?? "figure.run"
    }

    nonisolated var isMerged: Bool { health != nil && local != nil }

    nonisolated var sportName: String { title }

    nonisolated var sourceSummary: String {
        var sources: [String] = []
        if let health {
            sources.append(health.sourceName.map { "Apple Health · \($0)" } ?? "Apple Health")
        }
        if let local {
            sources.append(local.source.displayName)
        }
        return sources.removingDuplicates().joined(separator: " + ")
    }

    nonisolated var duration: TimeInterval {
        local?.duration ?? health?.duration ?? 0
    }

    nonisolated var distanceKm: Double? {
        local?.distanceKm ?? health?.distanceKm
    }

    nonisolated var energyKcal: Double? {
        local?.energyKcal ?? health?.energyKcal
    }

    nonisolated var averageHeartRate: Double? {
        local?.averageHeartRate
    }

    nonisolated var weather: WorkoutWeather? {
        local?.weather ?? health?.weather
    }

    nonisolated var injury: WorkoutInjury? {
        local?.injury ?? health?.injury
    }

    nonisolated var volumeKg: Double? {
        let volume = strengthExercises
            .flatMap(\.sets)
            .map(\.volumeKg)
            .reduce(0, +)
        return volume > 0 ? volume : nil
    }

    nonisolated var setCount: Int? {
        let count = strengthExercises.flatMap(\.sets).count
        return count > 0 ? count : nil
    }

    nonisolated var strengthExercises: [UnifiedStrengthExercise] {
        (local?.exercises ?? []).map(UnifiedStrengthExercise.init)
    }

}

struct UnifiedStrengthExercise: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let start: Date?
    let end: Date?
    let durationSeconds: Double?
    let notes: String
    let settings: [String: String]
    let sets: [UnifiedStrengthSet]

    nonisolated init(_ exercise: LocalStrengthExercise) {
        let catalogID = exercise.catalogID.trimmingCharacters(in: .whitespacesAndNewlines)
        id = catalogID.isEmpty ? Self.normalizedExerciseID(exercise.name) : catalogID
        name = exercise.name
        category = exercise.category
        start = exercise.start
        end = exercise.end
        durationSeconds = exercise.durationSeconds
        notes = exercise.notes
        settings = exercise.deviceSettings
        sets = exercise.sets.map(UnifiedStrengthSet.init)
    }

    private nonisolated static func normalizedExerciseID(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { result, character in
                if character != "_" || result.last != "_" { result.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    nonisolated var setCount: Int { sets.count }
    nonisolated var volumeKg: Double { sets.map(\.volumeKg).reduce(0, +) }
    nonisolated var bestWeightKg: Double? {
        let best = sets.compactMap(\.weightKg).max()
        return best == 0 ? nil : best
    }
}

struct UnifiedStrengthSet: Identifiable, Hashable {
    let id: String
    let index: Int
    let type: String
    let reps: Double?
    let weightKg: Double?
    let rpe: Double?
    let volumeKg: Double
    let isPersonalRecord: Bool

    nonisolated init(_ set: LocalStrengthSet) {
        id = set.id
        index = set.index
        type = set.type
        reps = set.reps
        weightKg = set.weightKg
        rpe = set.rpe
        volumeKg = set.volumeKg ?? (set.weightKg ?? 0) * (set.reps ?? 0)
        isPersonalRecord = set.isPersonalRecord
    }
}

enum UnifiedWorkoutBuilder {
    nonisolated static func build(health: [WorkoutSummary],
                                  local: [LocalWorkout]) -> [UnifiedWorkout] {
        let health = deduplicatedHealth(health)
        let local = local.sorted { $0.start < $1.start }
        let healthByDay = Dictionary(grouping: health, by: { dayIndex(for: $0.start) })
        let gympitLocalByID = Dictionary(
            local.lazy.filter { $0.source == .gympit }.map { ($0.id, $0) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        var usedHealth = Set<UUID>()
        var usedLocal = Set<UUID>()
        var out: [UnifiedWorkout] = []

        for workout in health where !usedHealth.contains(workout.uuid) {
            let exactLocal = workout.externalWorkoutUUID.flatMap { gympitLocalByID[$0] }
            let localMatch = if let exactLocal, !usedLocal.contains(exactLocal.id) {
                exactLocal
            } else {
                closestLocal(to: workout.start, in: local, used: usedLocal)
            }
            if let localMatch { usedLocal.insert(localMatch.id) }
            out.append(UnifiedWorkout(id: "health-\(workout.uuid)",
                                      health: workout,
                                      local: localMatch))
        }

        for workout in local where !usedLocal.contains(workout.id) {
            let group = localCandidates(around: workout.start, tolerance: 10 * 60, in: local).filter { candidate in
                !usedLocal.contains(candidate.id) && isSameLocalWorkout(workout, candidate)
            }
            group.forEach { usedLocal.insert($0.id) }
            let best = group.max { qualityScore($0) < qualityScore($1) } ?? workout
            let id = group.map { $0.id.uuidString }.sorted().joined(separator: "-")
            out.append(UnifiedWorkout(id: "local-\(id)",
                                      health: nil,
                                      local: best))
        }

        return out.sorted { $0.startDate > $1.startDate }
    }

    private nonisolated static func deduplicatedHealth(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        var byKey: [String: WorkoutSummary] = [:]
        for workout in workouts {
            let key: String
            if let externalWorkoutID = workout.externalWorkoutID {
                let source = workout.sourceName?.lowercased() ?? ""
                key = "external|\(source)|\(externalWorkoutID.lowercased())"
            } else {
                key = [
                    workout.activityName.lowercased(),
                    String(Int(workout.start.timeIntervalSince1970.rounded())),
                    String(Int(workout.end.timeIntervalSince1970.rounded())),
                    String(Int(workout.duration.rounded())),
                    workout.distanceKm.map { String(format: "%.4f", $0) } ?? "",
                    workout.energyKcal.map { String(format: "%.2f", $0) } ?? ""
                ].joined(separator: "|")
            }
            if let existing = byKey[key] {
                let existingScore = (existing.distanceKm ?? 0) + (existing.energyKcal ?? 0)
                let candidateScore = (workout.distanceKm ?? 0) + (workout.energyKcal ?? 0)
                if candidateScore > existingScore {
                    byKey[key] = workout
                }
            } else {
                byKey[key] = workout
            }
        }
        return Array(byKey.values)
    }

    private nonisolated static func closestLocal(to date: Date,
                                                 in local: [LocalWorkout],
                                                 used: Set<UUID>) -> LocalWorkout? {
        localCandidates(around: date, tolerance: 90 * 60, in: local)
            .filter { !used.contains($0.id) }
            .min { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }

    private nonisolated static func healthCandidates(
        around date: Date,
        groupedByDay: [Int: [WorkoutSummary]]
    ) -> [WorkoutSummary] {
        let day = dayIndex(for: date)
        return (day - 1...day + 1).flatMap { groupedByDay[$0] ?? [] }
    }

    private nonisolated static func dayIndex(for date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / 86_400)
    }

    private nonisolated static func localCandidates(
        around date: Date,
        tolerance: TimeInterval,
        in sorted: [LocalWorkout]
    ) -> ArraySlice<LocalWorkout> {
        let lowerDate = date.addingTimeInterval(-tolerance)
        let upperDate = date.addingTimeInterval(tolerance)
        let lower = lowerBound(for: lowerDate, in: sorted)
        let upper = lowerBound(for: upperDate.addingTimeInterval(.ulpOfOne), in: sorted)
        return sorted[lower..<upper]
    }

    private nonisolated static func lowerBound(for date: Date, in sorted: [LocalWorkout]) -> Int {
        var lower = 0
        var upper = sorted.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if sorted[middle].start < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private nonisolated static func isSameLocalWorkout(_ lhs: LocalWorkout, _ rhs: LocalWorkout) -> Bool {
        if lhs.id == rhs.id { return true }
        if lhs.source == rhs.source { return false }
        if abs(lhs.start.timeIntervalSince(rhs.start)) > 10 * 60 { return false }

        let allowedDurationDiff = max(10 * 60, max(lhs.duration, rhs.duration) * 0.25)
        if lhs.duration > 0, rhs.duration > 0, abs(lhs.duration - rhs.duration) > allowedDurationDiff {
            return false
        }

        if let lhsDistance = lhs.distanceKm, let rhsDistance = rhs.distanceKm {
            let allowedDistanceDiff = max(0.5, max(lhsDistance, rhsDistance) * 0.2)
            if abs(lhsDistance - rhsDistance) > allowedDistanceDiff {
                return false
            }
        }

        return true
    }

    private nonisolated static func qualityScore(_ workout: LocalWorkout) -> Double {
        var score = workout.duration
        score += Double(workout.exercises.count) * 10_000
        score += Double(workout.exercises.flatMap(\.sets).count) * 1_000
        if let distance = workout.distanceKm { score += distance * 100 }
        score += Double(workout.route.count)
        if workout.averageHeartRate != nil { score += 500 }
        if workout.maxHeartRate != nil { score += 250 }
        if !workout.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 50 }
        if workout.weather != nil { score += 25 }
        if workout.injury?.isEmpty == false { score += 25 }
        return score
    }
}

struct UnifiedWorkoutRow: View {
    let item: UnifiedWorkout
    let records: [WorkoutRecord]

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.title2)
                .foregroundStyle(HealthCategory.workouts.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.headline)
                    if item.isMerged {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.startDate, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.sourceSummary.isEmpty {
                    Label(item.sourceSummary, systemImage: "tray.full")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let first = records.first {
                    Label(first.localizedTitle, systemImage: "trophy.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                if let weather = item.weather, !weather.summary.isEmpty {
                    Label(weather.summary, systemImage: "cloud.sun.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let injury = item.injury, !injury.isEmpty {
                    Label(injury.summary, systemImage: "bandage.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(primaryValue)
                    .font(.subheadline.bold())
                Text(secondaryValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var primaryValue: String {
        if let local = item.local { return formatWorkoutDuration(local.duration) }
        guard let health = item.health else { return "" }
        return formatWorkoutDuration(health.duration)
    }

    private var secondaryValue: String {
        if let local = item.local {
            var parts: [String] = []
            if let km = local.distanceKm { parts.append(WorkoutUnits.distance(km: km, fractionDigits: 2)) }
            if let kcal = local.energyKcal { parts.append("\(Int(kcal.rounded())) kcal") }
            if let hr = local.averageHeartRate { parts.append("Ø \(Int(hr)) bpm") }
            return parts.joined(separator: " · ")
        }
        guard let health = item.health else { return "" }
        var parts: [String] = []
        if let km = health.distanceKm, km > 0 { parts.append(WorkoutUnits.distance(km: km, fractionDigits: 2)) }
        if let kcal = health.energyKcal, kcal > 0 { parts.append("\(Int(kcal)) kcal") }
        return parts.joined(separator: " · ")
    }
}

struct UnifiedWorkoutDetailView: View {
    let item: UnifiedWorkout
    var records: [WorkoutRecord] = []
    @State private var healthDetail: WorkoutDetail?

    var body: some View {
        if let health = item.health {
            if let local = item.local {
                LocalWorkoutDetailLoaderView(summary: local, records: records, healthWorkout: health)
            } else {
                LocalWorkoutDetailView(workout: LocalWorkout(id: health.uuid,
                                                             source: .appleHealth,
                                                             sport: health.activityName,
                                                             title: health.activityName,
                                                             start: health.start,
                                                             end: health.end,
                                                             distanceKm: health.distanceKm,
                                                             energyKcal: health.energyKcal,
                                                             averageHeartRate: nil,
                                                             maxHeartRate: nil,
                                                             notes: "",
                                                             weather: health.weather,
                                                             injury: health.injury,
                                                             route: []),
                                       records: records,
                                       healthWorkout: health)
            }
        } else if let local = item.local {
            LocalWorkoutDetailLoaderView(summary: local, records: records)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.headline)
            Text(L10n.string(title)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mergedHealthStats: [WorkoutStat] {
        guard let stats = healthDetail?.stats else { return [] }
        let duplicateLabels: Set<String> = [
            "dauer",
            "distanz",
            "kalorien",
            "aktive kalorien",
            "ø puls",
            "max puls",
            "min puls",
        ]
        return stats.filter { stat in
            let label = stat.label.normalizedWorkoutStatLabel
            if duplicateLabels.contains(label) { return false }
            if label.hasPrefix("distanz") { return false }
            if label.contains("kalorien") { return false }
            if label.contains("puls") { return false }
            return true
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        formatWorkoutDuration(seconds)
    }

    private func tempoText(_ workout: LocalWorkout) -> String? {
        guard let km = workout.distanceKm, km > 0, workout.duration > 0 else { return nil }
        if isCycling(workout) {
            return WorkoutUnits.speed(kmh: km / (workout.duration / 3600))
        }
        return WorkoutUnits.pace(secondsPerKilometer: Int((workout.duration / km).rounded()))
    }

    private func isCycling(_ workout: LocalWorkout) -> Bool {
        workout.sport.localizedCaseInsensitiveContains("rad")
            || workout.sport.localizedCaseInsensitiveContains("bike")
            || workout.sport.localizedCaseInsensitiveContains("cycle")
    }
}

struct LocalWorkoutDetailLoaderView: View {
    let summary: LocalWorkout
    var records: [WorkoutRecord] = []
    var healthWorkout: WorkoutSummary?

    @State private var workout: LocalWorkout?

    var body: some View {
        LocalWorkoutDetailView(workout: workout ?? summary,
                               records: records,
                               healthWorkout: healthWorkout)
            .task {
                if workout == nil {
                    workout = await HealthQuery.shared.localWorkout(id: summary.id) ?? summary
                }
            }
    }
}

struct StrengthExerciseDetailView: View {
    let exercise: StrengthExerciseAggregate
    @State private var selectedChartDate: Date?
    @State private var chartZoomLevel = 1.0

    var body: some View {
        let points = weightPoints
        let highlightedPoint = selectedChartPoint(in: points)
        let chartDomain = strengthChartDomain(for: points)
        let showsPointSymbols = points.count <= 60
        return List {
            Section {
                if exercise.points.isEmpty {
                    ContentUnavailableView(L10n.string("Noch kein Verlauf"),
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text(L10n.string("Für diese Übung gibt es noch keine Trainingspunkte.")))
                } else {
                    Chart {
                        ForEach(points) { point in
                            if let weight = point.weightKg {
                                LineMark(x: .value("Training", point.date),
                                         y: .value("Bestgewicht", weight))
                                    .foregroundStyle(HealthCategory.workouts.tint)
                                    .interpolationMethod(showsPointSymbols ? .catmullRom : .linear)
                                if showsPointSymbols {
                                    PointMark(x: .value("Training", point.date),
                                              y: .value("Bestgewicht", weight))
                                        .foregroundStyle(HealthCategory.workouts.tint)
                                }

                                if point.id == highlightedPoint?.id {
                                    PointMark(x: .value("Ausgewählt", point.date),
                                              y: .value("Bestgewicht", weight))
                                        .foregroundStyle(HealthCategory.workouts.tint)
                                        .symbolSize(80)
                                }
                            }
                        }

                        if let highlightedPoint {
                            RuleMark(x: .value("Ausgewählt", highlightedPoint.date))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .frame(height: 230)
                    .chartXScale(domain: chartDomain)
                    .chartXVisibleDomain(length: strengthChartVisibleDuration(for: chartDomain))
                    .chartScrollableAxes(.horizontal)
                    .chartTapSelection(value: $selectedChartDate)
                    .chartPinchZoom($chartZoomLevel)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.day().month(), centered: false)
                                .font(.caption2)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text(compactChartAxisNumber(number))
                                        .font(.caption2)
                                } else if let number = value.as(Int.self) {
                                    Text(number.formatted())
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .modernChartSurface(tint: HealthCategory.workouts.tint)

                    if let selectedChartPoint = highlightedPoint, let weight = selectedChartPoint.weightKg {
                        ChartSelectedValue(
                            title: selectedChartPoint.date.formatted(.dateTime.weekday(.abbreviated).day().month().year()),
                            values: [(HealthCategory.workouts.tint, formatKg(weight))]
                        )
                    }

                    ChartGestureHint()

                    Label(L10n.string("Bestgewicht pro Training"), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack(spacing: 12) {
                    stat("Trainings", "\(exercise.workoutCount)")
                    stat("Sätze", "\(exercise.setCount)")
                    stat("Bestgewicht", exercise.bestWeightKg.map(formatKg) ?? "-")
                    stat("Volumen", formatKg(exercise.volumeKg))
                }
            }

            Section(L10n.string("Verlauf")) {
                ForEach(exercise.points.sorted { $0.date > $1.date }) { point in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.date, format: .dateTime.day().month().year())
                                .font(.subheadline.bold())
                            Text(L10n.format("%lld Sätze · %@ Volumen", Int64(point.setCount), formatKg(point.volumeKg)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(point.weightKg.map(formatKg) ?? "-")
                            .font(.subheadline.bold())
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weightPoints: [StrengthExercisePoint] {
        exercise.points.filter { ($0.weightKg ?? 0) > 0 }
    }

    private func selectedChartPoint(in points: [StrengthExercisePoint]) -> StrengthExercisePoint? {
        guard let selectedChartDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedChartDate))
                < abs($1.date.timeIntervalSince(selectedChartDate))
        }
    }

    private func strengthChartDomain(for points: [StrengthExercisePoint]) -> ClosedRange<Date> {
        let start = points.map(\.date).min() ?? Date()
        let last = points.map(\.date).max() ?? start
        let end = Calendar.healthApp.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        return start...end
    }

    private func strengthChartVisibleDuration(for domain: ClosedRange<Date>) -> TimeInterval {
        let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return min(total, max(86_400, total / chartZoomLevel))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(L10n.string(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StrengthExerciseAggregate: Identifiable {
    let id: String
    let name: String
    let workoutCount: Int
    let setCount: Int
    let volumeKg: Double
    let bestWeightKg: Double?
    let points: [StrengthExercisePoint]
}

struct StrengthExercisePoint: Identifiable {
    let id: String
    let date: Date
    let setCount: Int
    let volumeKg: Double
    let weightKg: Double?
}

enum StrengthExerciseAnalyzer {
    nonisolated static func rows(from items: [UnifiedWorkout]) -> [StrengthExerciseAggregate] {
        let grouped = Dictionary(grouping: points(items), by: \.id)
        return grouped.values.map(aggregate).sorted {
            if $0.workoutCount == $1.workoutCount { return $0.volumeKg > $1.volumeKg }
            return $0.workoutCount > $1.workoutCount
        }
    }

    nonisolated static func row(for exercise: UnifiedStrengthExercise, in items: [UnifiedWorkout]) -> StrengthExerciseAggregate {
        aggregate(points(items).filter { $0.id == exercise.id })
    }

    nonisolated static func row(for exercise: LocalStrengthExercise, workout: LocalWorkout) -> StrengthExerciseAggregate {
        let unified = UnifiedStrengthExercise(exercise)
        let point = StrengthExercisePoint(id: "\(exercise.id)-\(workout.start.timeIntervalSince1970)",
                                          date: workout.start,
                                          setCount: unified.setCount,
                                          volumeKg: unified.volumeKg,
                                          weightKg: unified.bestWeightKg)
        return StrengthExerciseAggregate(id: unified.id,
                                         name: unified.name,
                                         workoutCount: 1,
                                         setCount: unified.setCount,
                                         volumeKg: unified.volumeKg,
                                         bestWeightKg: unified.bestWeightKg,
                                         points: [point])
    }

    private nonisolated static func points(_ items: [UnifiedWorkout]) -> [ExerciseSourcePoint] {
        items.filter { normalizeStrengthSport($0.sportName) == "Krafttraining" }.flatMap { item in
            item.strengthExercises.map { exercise in
                let bestWeight = exercise.bestWeightKg
                return ExerciseSourcePoint(id: exercise.id,
                                           name: exercise.name,
                                           date: item.startDate,
                                           setCount: exercise.setCount,
                                           volumeKg: exercise.volumeKg,
                                           weightKg: bestWeight)
            }
        }
    }

    private nonisolated static func aggregate(_ values: [ExerciseSourcePoint]) -> StrengthExerciseAggregate {
        let sorted = values.sorted { $0.date < $1.date }
        let name = sorted.last?.name ?? "Übung"
        return StrengthExerciseAggregate(id: sorted.last?.id ?? UUID().uuidString,
                                         name: name,
                                         workoutCount: sorted.count,
                                         setCount: sorted.map(\.setCount).reduce(0, +),
                                         volumeKg: sorted.map(\.volumeKg).reduce(0, +),
                                         bestWeightKg: sorted.compactMap(\.weightKg).max(),
                                         points: sorted.map {
                                             StrengthExercisePoint(id: "\($0.id)-\($0.date.timeIntervalSince1970)",
                                                                   date: $0.date,
                                                                   setCount: $0.setCount,
                                                                   volumeKg: $0.volumeKg,
                                                                   weightKg: $0.weightKg)
                                         })
    }

    private struct ExerciseSourcePoint {
        let id: String
        let name: String
        let date: Date
        let setCount: Int
        let volumeKg: Double
        let weightKg: Double?
    }
}

nonisolated func normalizeStrengthSport(_ value: String) -> String {
    let lower = value.lowercased()
    if lower.contains("kraft") || lower.contains("strength") { return "Krafttraining" }
    return value.isEmpty ? "Workout" : value
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
