//
//  RecordsView.swift
//  Healthpit
//
//  Persoenliche Rekorde aus Apple Health und lokalen Importen.
//

import SwiftUI

struct RecordsView: View {
    @State private var records: [WorkoutRecord] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var visibleRecordLimit = 10
    @State private var selectedSport = allSportsValue
    @State private var recordWorkouts: [UnifiedWorkout] = []

    private static let allSportsValue = "Alle"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProfessionalPageHero(
                    eyebrow: "Persönliche Bestleistungen",
                    title: "Deine Rekorde",
                    subtitle: "Fortschritt, der sichtbar bleibt – über alle Sportarten und Zeiträume.",
                    symbol: "trophy.fill",
                    tint: .orange,
                    value: records.isEmpty ? "–" : "\(visibleRecords.count)",
                    detail: "Bestleistungen"
                )

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                } else if records.isEmpty {
                    ProfessionalEmptyState(title: "Noch keine Rekorde",
                                           message: message ?? L10n.string("Noch nicht genug Daten vorhanden."),
                                           symbol: "trophy.fill",
                                           tint: .orange)
                } else {
                    motivationHeader

                    VStack(alignment: .leading, spacing: 12) {
                        ProfessionalSectionHeader(title: "Sportart",
                                                  subtitle: "Filtere deine persönlichen Bestleistungen")
                    Picker(L10n.string("Sportart"), selection: $selectedSport) {
                        ForEach(sportOptions, id: \.self) { sport in
                            Text(L10n.string(sport)).tag(sport)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(L10n.string("Rekorde beziehen sich immer auf die komplette verfügbare Zeit."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .professionalCard(tint: .orange)

                    ProfessionalSectionHeader(title: "Highlights",
                                              subtitle: "Deine stärksten aktuellen Leistungen")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(Array(visibleRecords.prefix(4))) { record in
                            recordLink(record) {
                                highlightCard(record)
                            }
                        }
                    }

                    ProfessionalSectionHeader(title: "Alle Bestleistungen",
                                              subtitle: "Chronologisch nach dem neuesten Rekord")
                    LazyVStack(spacing: 10) {
                    ForEach(Array(visibleRecords.prefix(visibleRecordLimit))) { record in
                        recordLink(record) {
                            recordRow(record)
                        }
                    }
                    if visibleRecords.count > visibleRecordLimit {
                        Button {
                            visibleRecordLimit += 10
                        } label: {
                            Label(L10n.string("Weitere anzeigen"), systemImage: "chevron.down")
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .professionalCard(tint: .orange)
                        }
                    }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .professionalPageBackground(tint: .orange)
        .navigationTitle(L10n.string("Rekorde"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refreshRecords()
            SyncRefreshStatusStore.markLocalRefresh()
        }
        .task { await loadCachedRecords() }
    }

    private var motivationHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(visibleRecords.count) Bestleistungen")
                        .font(.title3.bold())
                    Text(selectedSport == Self.allSportsValue
                         ? L10n.string("Alle Sportarten · gesamte Zeit")
                         : L10n.format("%@ · gesamte Zeit", L10n.string(selectedSport)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }

            if let newest = visibleRecords.first {
                HStack(spacing: 10) {
                    Image(systemName: newest.symbol)
                        .font(.title3)
                        .foregroundStyle(newest.tint)
                        .frame(width: 38, height: 38)
                        .background(newest.tint.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("Rekord"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.format("%@ · %@", newest.localizedTitle, newest.localizedValue))
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(L10n.format("%@ · %@", newest.localizedSport, newest.localizedSubtitle))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(12)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .professionalCard(tint: .orange)
    }

    private var sportOptions: [String] {
        [Self.allSportsValue] + Array(Set(records.map(\.sport))).sorted()
    }

    private var visibleRecords: [WorkoutRecord] {
        let filtered = selectedSport == Self.allSportsValue
            ? records
            : records.filter { $0.sport == selectedSport }
        return filtered.sorted {
            if $0.date == $1.date {
                if $0.priority == $1.priority {
                    return $0.sport < $1.sport
                }
                return $0.priority < $1.priority
            }
            return $0.date > $1.date
        }
    }

    @ViewBuilder
    private func recordLink<Content: View>(_ record: WorkoutRecord,
                                           @ViewBuilder content: () -> Content) -> some View {
        if let workout = workout(for: record) {
            NavigationLink {
                UnifiedWorkoutDetailView(item: workout,
                                         records: [record])
            } label: {
                content()
            }
        } else {
            content()
        }
    }

    private func recordRow(_ record: WorkoutRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: record.symbol)
                .font(.title2)
                .foregroundStyle(record.tint)
                .frame(width: 38, height: 38)
                .background(record.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(record.localizedTitle).font(.headline)
                Text(L10n.format("%@ · %@", record.localizedSport, record.localizedSubtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.localizedValue)
                .font(.subheadline.bold())
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
        .professionalCard(tint: record.tint)
    }

    private func highlightCard(_ record: WorkoutRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: record.symbol)
                .font(.title2)
                .foregroundStyle(record.tint)
                .frame(width: 42, height: 42)
                .background(record.tint.opacity(0.14), in: Circle())
            Spacer(minLength: 0)
            Text(record.localizedValue)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.localizedTitle)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(record.localizedSport)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(record.localizedSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .padding(14)
        .background(record.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(record.tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func loadCachedRecords() async {
        records = await WorkoutRecordCacheStore.shared.load()
        await loadRecordWorkouts()
        ensureSelectedSportExists()
        visibleRecordLimit = min(max(visibleRecordLimit, 10), max(visibleRecords.count, 10))
        if records.isEmpty {
            message = L10n.string("Noch keine gespeicherten Rekorde. Zum Berechnen nach unten ziehen.")
        }
    }

    private func refreshRecords() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        await WorkoutRecordRefreshService.shared.refreshFromLocalCaches()
        records = await WorkoutRecordCacheStore.shared.load()
        await loadRecordWorkouts()
        ensureSelectedSportExists()
        visibleRecordLimit = min(max(visibleRecordLimit, 10), max(visibleRecords.count, 10))
        if records.isEmpty {
            message = L10n.string("Mehr Workouts oder importierte Trainings benötigt.")
        }
    }

    private func loadRecordWorkouts() async {
        recordWorkouts = await HealthQuery.shared.unifiedWorkouts()
    }

    private func workout(for record: WorkoutRecord) -> UnifiedWorkout? {
        if let exact = recordWorkouts.first(where: { $0.id == record.workoutID }) {
            return exact
        }
        return recordWorkouts.first { workout in
            workout.sportName == record.sport &&
            abs(workout.startDate.timeIntervalSince(record.date)) < 60
        }
    }

    private func ensureSelectedSportExists() {
        if selectedSport != Self.allSportsValue,
           !records.contains(where: { $0.sport == selectedSport }) {
            selectedSport = Self.allSportsValue
        }
    }

}

#Preview {
    NavigationStack {
        RecordsView()
    }
}
