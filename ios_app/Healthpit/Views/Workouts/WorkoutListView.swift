//
//  WorkoutListView.swift
//  Healthpit
//
//  Gemeinsame Workout-Liste aus Apple Health und Hevy.
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
    @State private var hevySummary: HevyFitnessSummary?
    @State private var localWorkouts: [LocalWorkout] = []
    @State private var items: [UnifiedWorkout] = []
    @State private var allTimeItems: [UnifiedWorkout] = []
    @State private var referenceDate = Date()
    @State private var isLoading = false
    @State private var showingLinks = false
    @State private var showingImporter = false
    @State private var showingManualWorkout = false
    @State private var itemPendingDeletion: UnifiedWorkout?
    @State private var showingDeleteConfirmation = false
    @State private var showingSyncStatus = false
    @State private var hasLoadedData = false
    @AppStorage("ignoredHevyWorkoutLinks") private var ignoredLinksRaw = ""
    @AppStorage(BridgeSettings.hiddenHealthWorkoutIDsKey) private var hiddenHealthWorkoutIDsRaw = ""
    @AppStorage("hiddenHevyWorkoutIDs") private var hiddenHevyWorkoutIDsRaw = ""

    var body: some View {
        List {
            if showingSyncStatus {
                SyncRefreshStatusView()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Zeitraum", selection: $range) {
                    ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            WorkoutRangeOverview(range: range,
                                 referenceDate: $referenceDate,
                                 items: items,
                                 sportItems: allTimeItems)

            Section {
                NavigationLink {
                    WorkoutSportListView(items: allTimeItems,
                                         hevySummary: hevySummary) { item in
                        itemPendingDeletion = item
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Label("Sportarten", systemImage: "figure.mixed.cardio")
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if items.isEmpty {
                ContentUnavailableView("Keine Workouts",
                                       systemImage: "figure.run",
                                       description: Text("Im gewählten Zeitraum sind keine Workouts vorhanden."))
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        UnifiedWorkoutDetailView(item: item,
                                                 hevySummary: hevySummary,
                                                 records: [])
                    } label: {
                        UnifiedWorkoutRow(item: item, records: [])
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            itemPendingDeletion = item
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("GPX/TCX importieren", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await refreshCurrentRange() }
                    } label: {
                        Label("Aktualisieren", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        showingManualWorkout = true
                    } label: {
                        Label("Training manuell", systemImage: "plus")
                    }
                    Button {
                        showingLinks = true
                    } label: {
                        Label("Verknüpfen", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingLinks) {
            NavigationStack {
                WorkoutLinkManagerView(items: allTimeItems, ignoredLinksRaw: $ignoredLinksRaw)
            }
        }
        .sheet(isPresented: $showingManualWorkout) {
            ManualWorkoutView { workout in
                Task {
                    await LocalWorkoutStore.shared.save(workout)
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
        }
        .refreshable {
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
        .onChange(of: ignoredLinksRaw) { _, _ in rebuildItems() }
        .onChange(of: hiddenHealthWorkoutIDsRaw) { _, _ in rebuildItems() }
        .onChange(of: hiddenHevyWorkoutIDsRaw) { _, _ in rebuildItems() }
        .onChange(of: showingLinks) { _, isShowing in
            if isShowing { showingSyncStatus = false }
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
        .confirmationDialog("Workout entfernen?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible,
                            presenting: itemPendingDeletion) { item in
            Button("Entfernen", role: .destructive) {
                Task { await deleteWorkout(item) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { item in
            Text(deleteWarning(for: item))
        }
    }

    private func loadCached() async {
        isLoading = items.isEmpty
        async let allTimeHealth = HealthWorkoutCacheStore.shared.loadAllTime()
        async let cachedHevy = HevyFitnessCacheStore.shared.load()
        async let cachedLocal = LocalWorkoutStore.shared.loadSummaries()
        let completeHealth = await allTimeHealth
        healthWorkouts = completeHealth.isEmpty
            ? await HealthWorkoutCacheStore.shared.load(range: range, referenceDate: referenceDate)
            : []
        hevySummary = await cachedHevy
        localWorkouts = await cachedLocal
        rebuildItems(allTimeHealth: completeHealth)
        hasLoadedData = true
        isLoading = false
    }

    private func refreshCurrentRange() async {
        isLoading = items.isEmpty
        let cachedHevy = hevySummary
        async let syncCount: Int? = try? BridgeSyncService.shared.syncNow()
        async let freshHevy = try? BridgeFitnessService.shared.fetchHevySummary()

        _ = await syncCount
        if let freshHealth = try? await health.fetchWorkouts(in: range, referenceDate: referenceDate) {
            let cacheableHealth = freshHealth.filter(\.isEligibleForLocalHealthCache)
            await HealthWorkoutCacheStore.shared.save(cacheableHealth, range: range, referenceDate: referenceDate)
            await HealthWorkoutCacheStore.shared.mergeAllTime(cacheableHealth)
            healthWorkouts = cacheableHealth
        } else {
            healthWorkouts = await HealthWorkoutCacheStore.shared.load(range: range, referenceDate: referenceDate)
        }
        let refreshedHevy = await freshHevy
        if let refreshedHevy {
            await HevyFitnessCacheStore.shared.save(refreshedHevy)
        }
        hevySummary = refreshedHevy ?? cachedHevy
        localWorkouts = await LocalWorkoutStore.shared.loadSummaries()
        rebuildItems(allTimeHealth: await HealthWorkoutCacheStore.shared.loadAllTime())
        isLoading = false
        SyncRefreshStatusStore.markLocalRefresh()
        showingSyncStatus = true
    }

    private func refreshLocalAppleHealthRange() async {
        isLoading = items.isEmpty
        if let fresh = try? await health.fetchWorkouts(in: range, referenceDate: referenceDate) {
            let cacheableHealth = fresh.filter(\.isEligibleForLocalHealthCache)
            await HealthWorkoutCacheStore.shared.save(cacheableHealth, range: range, referenceDate: referenceDate)
            await HealthWorkoutCacheStore.shared.mergeAllTime(cacheableHealth)
            healthWorkouts = cacheableHealth
        } else {
            healthWorkouts = await HealthWorkoutCacheStore.shared.load(range: range, referenceDate: referenceDate)
        }
        localWorkouts = await LocalWorkoutStore.shared.loadSummaries()
        rebuildItems(allTimeHealth: await HealthWorkoutCacheStore.shared.loadAllTime())
        isLoading = false
    }

    private func rebuildItems(allTimeHealth: [WorkoutSummary]? = nil) {
        if let allTimeHealth {
            allTimeHealthWorkouts = allTimeHealth
        }
        let sourceHealth = allTimeHealthWorkouts.isEmpty ? healthWorkouts : allTimeHealthWorkouts
        let completeHealth = sourceHealth.filter {
            !hiddenHealthWorkoutIDs.contains($0.uuid.uuidString)
        }
        let completeHevy = (hevySummary?.recentWorkouts ?? [])
            .filter { !hiddenHevyWorkoutIDs.contains($0.id) }
        allTimeItems = UnifiedWorkoutBuilder.build(health: completeHealth,
                                                   hevy: completeHevy,
                                                   local: localWorkouts,
                                                   ignoredLinks: ignoredLinks)
        filterItemsForSelectedRange()
    }

    private func filterItemsForSelectedRange() {
        let interval = range.dateInterval(referenceDate: referenceDate)
        items = allTimeItems.filter { interval.contains($0.startDate) }
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let workout = try? WorkoutFileImporter.importWorkout(from: url) {
                await LocalWorkoutStore.shared.save(workout)
            }
        }
        _ = try? await BridgeSyncService.shared.uploadLocalWorkouts()
        await loadCached()
    }

    private func deleteWorkout(_ item: UnifiedWorkout) async {
        if let local = item.local {
            await LocalWorkoutStore.shared.delete(id: local.id)
            _ = try? await BridgeSyncService.shared.deleteImportedWorkout(id: local.id)
        }
        if let health = item.health {
            var ids = hiddenHealthWorkoutIDs
            ids.insert(health.uuid.uuidString)
            hiddenHealthWorkoutIDsRaw = ids.sorted().joined(separator: ",")
            _ = try? await BridgeSyncService.shared.deleteImportedWorkout(id: health.uuid)
        }
        if let hevy = item.hevy {
            var ids = hiddenHevyWorkoutIDs
            ids.insert(hevy.id)
            hiddenHevyWorkoutIDsRaw = ids.sorted().joined(separator: ",")
        }
        localWorkouts = await LocalWorkoutStore.shared.loadSummaries()
        rebuildItems()
    }

    private func deleteWarning(for item: UnifiedWorkout) -> String {
        var parts: [String] = []
        if item.local != nil {
            parts.append("Importierte oder manuelle Daten werden lokal und in der Bridge gelöscht.")
        }
        if item.health != nil {
            parts.append("Apple-Health-Daten werden in dieser App ausgeblendet; Apple Health selbst bleibt unverändert.")
        }
        if item.hevy != nil {
            parts.append("Hevy-Daten werden in dieser App ausgeblendet; Hevy selbst bleibt unverändert.")
        }
        return parts.joined(separator: " ")
    }

    private var ignoredLinks: Set<String> {
        Set(ignoredLinksRaw.split(separator: ",").map(String.init))
    }

    private var hiddenHealthWorkoutIDs: Set<String> {
        Set(hiddenHealthWorkoutIDsRaw.split(separator: ",").map(String.init))
    }

    private var hiddenHevyWorkoutIDs: Set<String> {
        Set(hiddenHevyWorkoutIDsRaw.split(separator: ",").map(String.init))
    }

}

struct UnifiedWorkout: Identifiable {
    let id: String
    let health: WorkoutSummary?
    let hevy: HevyWorkoutSummary?
    let local: LocalWorkout?
    let startDate: Date

    nonisolated init(id: String,
                     health: WorkoutSummary?,
                     hevy: HevyWorkoutSummary?,
                     local: LocalWorkout?,
                     hevyStartDate: Date? = nil) {
        self.id = id
        self.health = health
        self.hevy = hevy
        self.local = local
        startDate = hevyStartDate
            ?? hevy.flatMap { parseHevyDate($0.startTime) }
            ?? local?.start
            ?? health?.start
            ?? .distantPast
    }

    nonisolated var hevyDate: Date? {
        hevy == nil ? nil : startDate
    }

    nonisolated var title: String {
        if hevy != nil { return L10n.string("Krafttraining") }
        if let local { return L10n.string(local.sport) }
        return health?.activityName ?? L10n.string("Workout")
    }

    nonisolated var symbol: String {
        if hevy != nil { return "figure.strengthtraining.traditional" }
        if let local {
            switch local.sport.lowercased() {
            case "bouldern": return "figure.climbing"
            case "squash": return "figure.tennis"
            default: return "figure.run"
            }
        }
        return health?.symbol ?? "figure.run"
    }

    nonisolated var isMerged: Bool { [health != nil, hevy != nil, local != nil].filter { $0 }.count > 1 }

    nonisolated var sportName: String { title }

    nonisolated var sourceSummary: String {
        var sources: [String] = []
        if let health {
            sources.append(health.sourceName.map { "Apple Health · \($0)" } ?? "Apple Health")
        }
        if hevy != nil {
            sources.append("Hevy")
        }
        if let local {
            sources.append(local.source.displayName)
        }
        return sources.removingDuplicates().joined(separator: " + ")
    }

    nonisolated var duration: TimeInterval {
        local?.duration ?? health?.duration ?? hevyDuration ?? 0
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
        if let hevy { return hevy.volumeKg }
        let volume = strengthExercises
            .flatMap(\.sets)
            .map(\.volumeKg)
            .reduce(0, +)
        return volume > 0 ? volume : nil
    }

    nonisolated var setCount: Int? {
        if let hevy { return hevy.setCount }
        let count = strengthExercises.flatMap(\.sets).count
        return count > 0 ? count : nil
    }

    nonisolated var strengthExercises: [UnifiedStrengthExercise] {
        if let hevy {
            return hevy.exercises.map(UnifiedStrengthExercise.init)
        }
        return (local?.exercises ?? []).map(UnifiedStrengthExercise.init)
    }

    nonisolated var linkID: String? {
        guard let health, let hevy else { return nil }
        return "\(health.uuid.uuidString)|\(hevy.id)"
    }

    private nonisolated var hevyDuration: TimeInterval? {
        guard let hevy else { return nil }
        let seconds = hevy.exercises
            .flatMap(\.sets)
            .compactMap(\.durationSeconds)
            .reduce(0, +)
        return seconds > 0 ? seconds : nil
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

    nonisolated init(_ exercise: HevyWorkoutExercise) {
        id = exercise.id
        name = exercise.title
        category = "Krafttraining"
        start = nil
        end = nil
        durationSeconds = nil
        notes = ""
        settings = [:]
        sets = exercise.sets.map(UnifiedStrengthSet.init)
    }

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

    nonisolated init(_ set: HevySetSummary) {
        id = "hevy-\(set.setIndex)"
        index = set.setIndex
        type = set.setType ?? "Satz"
        reps = set.reps
        weightKg = set.weightKg
        rpe = set.rpe
        volumeKg = (set.weightKg ?? 0) * (set.reps ?? 0)
        isPersonalRecord = false
    }

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
                                  hevy: [HevyWorkoutSummary],
                                  local: [LocalWorkout],
                                  ignoredLinks: Set<String>) -> [UnifiedWorkout] {
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

        for hevyWorkout in hevy {
            let hevyDate = parseHevyDate(hevyWorkout.startTime)
            let candidates = hevyDate.map { healthCandidates(around: $0, groupedByDay: healthByDay) } ?? []
            let match = candidates
                .filter { !usedHealth.contains($0.uuid) }
                .filter { candidate in
                    let linkID = "\(candidate.uuid.uuidString)|\(hevyWorkout.id)"
                    return !ignoredLinks.contains(linkID)
                }
                .min { lhs, rhs in
                    abs(lhs.start.timeIntervalSince(hevyDate ?? lhs.start))
                    < abs(rhs.start.timeIntervalSince(hevyDate ?? rhs.start))
                }

            if let match, let hevyDate, isClose(match, hevyDate: hevyDate) {
                usedHealth.insert(match.uuid)
                let localMatch = closestLocal(to: hevyDate, in: local, used: usedLocal)
                if let localMatch { usedLocal.insert(localMatch.id) }
                out.append(UnifiedWorkout(id: "merged-\(match.uuid)-\(hevyWorkout.id)",
                                          health: match,
                                          hevy: hevyWorkout,
                                          local: localMatch,
                                          hevyStartDate: hevyDate))
            } else {
                let localMatch = hevyDate.flatMap { closestLocal(to: $0, in: local, used: usedLocal) }
                if let localMatch { usedLocal.insert(localMatch.id) }
                out.append(UnifiedWorkout(id: "hevy-\(hevyWorkout.id)",
                                          health: nil,
                                          hevy: hevyWorkout,
                                          local: localMatch,
                                          hevyStartDate: hevyDate))
            }
        }

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
                                      hevy: nil,
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
                                      hevy: nil,
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

    private nonisolated static func isClose(_ health: WorkoutSummary, hevyDate: Date) -> Bool {
        let distance = abs(health.start.timeIntervalSince(hevyDate))
        let sameDay = Calendar.current.isDate(health.start, inSameDayAs: hevyDate)
        let isStrength = health.activityName.localizedCaseInsensitiveContains("kraft")
            || health.activityName.localizedCaseInsensitiveContains("strength")
        return distance <= 90 * 60 || (sameDay && isStrength)
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
                .foregroundStyle(item.hevy != nil ? .green : HealthCategory.workouts.tint)
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
        if let hevy = item.hevy { return L10n.format("%lld Sätze", Int64(hevy.setCount)) }
        if let local = item.local { return formatWorkoutDuration(local.duration) }
        guard let health = item.health else { return "" }
        return formatWorkoutDuration(health.duration)
    }

    private var secondaryValue: String {
        if let hevy = item.hevy { return formatKg(hevy.volumeKg) }
        if let local = item.local {
            var parts: [String] = []
            if let km = local.distanceKm { parts.append(String(format: "%.2f km", km)) }
            if let kcal = local.energyKcal { parts.append("\(Int(kcal.rounded())) kcal") }
            if let hr = local.averageHeartRate { parts.append("Ø \(Int(hr)) bpm") }
            return parts.joined(separator: " · ")
        }
        guard let health = item.health else { return "" }
        var parts: [String] = []
        if let km = health.distanceKm, km > 0 { parts.append(String(format: "%.2f km", km)) }
        if let kcal = health.energyKcal, kcal > 0 { parts.append("\(Int(kcal)) kcal") }
        return parts.joined(separator: " · ")
    }
}

struct UnifiedWorkoutDetailView: View {
    let item: UnifiedWorkout
    let hevySummary: HevyFitnessSummary?
    var records: [WorkoutRecord] = []
    @State private var healthDetail: WorkoutDetail?

    var body: some View {
        if let hevy = item.hevy {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.startDate, format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: 12) {
                        stat("Übungen", "\(hevy.exerciseCount)")
                        stat("Sätze", "\(hevy.setCount)")
                        stat("Volumen", formatKg(hevy.volumeKg))
                    }
                    if let local = item.local {
                        NavigationLink {
                            LocalWorkoutDetailLoaderView(summary: local)
                        } label: {
                            Label("Importierte Trainingsdaten", systemImage: "doc.text")
                        }
                    }
                }

                if !mergedHealthStats.isEmpty {
                    Section("Weitere Trainingswerte") {
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

                if !records.isEmpty {
                    Section("Rekorde") {
                        ForEach(records) { record in
                            Label {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.localizedTitle).font(.subheadline.bold())
                                        Text(record.localizedSubtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(record.localizedValue).font(.subheadline.bold())
                                }
                            } icon: {
                                Image(systemName: "trophy.fill").foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section("Übungen") {
                    ForEach(item.strengthExercises) { exercise in
                        NavigationLink {
                            StrengthExerciseDetailView(exercise: StrengthExerciseAnalyzer.row(for: exercise,
                                                                                              in: [item]))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(exercise.name).font(.headline)
                                Text("\(exercise.setCount) Sätze · Best \(exercise.bestWeightKg.map(formatKg) ?? "-")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Krafttraining")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let health = item.health {
                    healthDetail = try? await HealthKitManager.shared.workoutDetail(for: health.uuid)
                }
            }
        } else if let health = item.health {
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
            return String(format: "%.1f km/h", km / (workout.duration / 3600))
        }
        let total = Int((workout.duration / km).rounded())
        return "\(total / 60):" + String(format: "%02d /km", total % 60)
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
                    workout = await LocalWorkoutStore.shared.fullWorkout(id: summary.id) ?? summary
                }
            }
    }
}

struct StrengthExerciseDetailView: View {
    let exercise: StrengthExerciseAggregate

    var body: some View {
        List {
            Section {
                if exercise.points.isEmpty {
                    ContentUnavailableView("Noch kein Verlauf",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Für diese Übung gibt es noch keine Trainingspunkte."))
                } else {
                    Chart(exercise.points) { point in
                        if let weight = point.weightKg, weight > 0 {
                            LineMark(x: .value("Training", point.date),
                                     y: .value("Bestgewicht", weight))
                                .foregroundStyle(HealthCategory.workouts.tint)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Training", point.date),
                                      y: .value("Bestgewicht", weight))
                                .foregroundStyle(HealthCategory.workouts.tint)
                                .annotation(position: .top) {
                                    Text(formatKg(weight))
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 230)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.day().month(), centered: false)
                                .font(.caption2)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel()
                                .font(.caption2)
                        }
                    }
                    Label("Bestgewicht pro Training", systemImage: "chart.line.uptrend.xyaxis")
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

            Section("Verlauf") {
                ForEach(exercise.points.sorted { $0.date > $1.date }) { point in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.date, format: .dateTime.day().month().year())
                                .font(.subheadline.bold())
                            Text("\(point.setCount) Sätze · \(formatKg(point.volumeKg)) Volumen")
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

    nonisolated static func row(for exercise: HevyWorkoutExercise, global: HevyExerciseSummary?) -> StrengthExerciseAggregate {
        let trendPoints = (global?.trend ?? []).compactMap { point -> StrengthExercisePoint? in
            guard let date = parseTrendDate(point.day) else { return nil }
            return StrengthExercisePoint(id: "\(exercise.id)-\(point.day)",
                                         date: date,
                                         setCount: point.sets,
                                         volumeKg: point.volumeKg,
                                         weightKg: point.weightKg)
        }
        let fallbackPoint = StrengthExercisePoint(id: "\(exercise.id)-current",
                                                  date: Date(),
                                                  setCount: exercise.setCount,
                                                  volumeKg: exercise.volumeKg,
                                                  weightKg: exercise.bestWeightKg)
        let points = trendPoints.isEmpty ? [fallbackPoint] : trendPoints
        return StrengthExerciseAggregate(id: exercise.id,
                                         name: exercise.title,
                                         workoutCount: global?.workoutCount ?? 1,
                                         setCount: global?.setCount ?? exercise.setCount,
                                         volumeKg: global?.totalVolumeKg ?? exercise.volumeKg,
                                         bestWeightKg: global?.bestWeightKg ?? exercise.bestWeightKg,
                                         points: points)
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

struct WorkoutLinkManagerView: View {
    let items: [UnifiedWorkout]
    @Binding var ignoredLinksRaw: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Verknüpfte Workouts") {
                let linked = items.filter(\.isMerged)
                if linked.isEmpty {
                    Text("Keine automatischen Verknüpfungen.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(linked) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.startDate, format: .dateTime.day().month().year().hour().minute())
                                    .font(.headline)
                                Text("Apple Health + Hevy")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Trennen") {
                                ignore(item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Verknüpfen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }
            }
        }
    }

    private func ignore(_ item: UnifiedWorkout) {
        guard let linkID = item.linkID else { return }
        var values = Set(ignoredLinksRaw.split(separator: ",").map(String.init))
        values.insert(linkID)
        ignoredLinksRaw = values.sorted().joined(separator: ",")
    }
}

nonisolated func parseHevyDate(_ text: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
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
