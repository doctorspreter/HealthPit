//
//  HealthDiaryView.swift
//  Healthpit
//
//  Physische Gesundheit: die Tagebücher.
//
//  Die Einstiegsseite zeigt nur die Beschwerdebilder, zu denen es Einträge
//  gibt, plus den Weg, ein neues anzulegen. Eine Liste aus elf Krankheiten,
//  von denen zehn leer sind, sagt weniger als eine aus zweien, die man
//  wirklich führt.
//

import SwiftUI

struct HealthDiaryView: View {
    @State private var episodes: [HealthEpisode] = []
    @State private var editing: HealthEpisode?
    @State private var isLoading = true

    private let tint = Color.mint

    /// Beschwerdebilder mit Einträgen, das häufigste zuerst.
    private var usedConditions: [(condition: HealthCondition, count: Int, latest: Date)] {
        Dictionary(grouping: episodes, by: \.condition)
            .map { (condition: $0.key,
                    count: $0.value.count,
                    latest: $0.value.map(\.startedAt).max() ?? .distantPast) }
            .sorted { $0.latest > $1.latest }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Physische Gesundheit"))
                        .font(.title2.bold())
                    Text(L10n.string("Tagebuch für Beschwerden, die in Episoden kommen."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !isLoading, !ongoing.isEmpty {
                        Text(L10n.format("%lld laufend", Int64(ongoing.count)))
                            .font(.caption)
                            .foregroundStyle(tint)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }

            if !ongoing.isEmpty {
                Section(L10n.string("Läuft gerade")) {
                    ForEach(ongoing) { episode in
                        episodeRow(episode)
                    }
                }
            }

            Section(L10n.string("Tagebücher")) {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if usedConditions.isEmpty {
                    Text(L10n.string("Noch kein Tagebuch geführt. Mit „+“ den ersten Eintrag anlegen."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(usedConditions, id: \.condition) { entry in
                        NavigationLink {
                            HealthConditionDetailView(condition: entry.condition) {
                                Task { await reload() }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.condition.systemImage)
                                    .foregroundStyle(tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.string(entry.condition.displayKey))
                                        .font(.subheadline.weight(.semibold))
                                    Text(L10n.format("%lld Einträge · zuletzt %@",
                                                     Int64(entry.count),
                                                     entry.latest.formatted(.dateTime.day().month().year())))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(L10n.string("Gesundheit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = HealthEpisode() } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L10n.string("Eintrag hinzufügen"))
            }
        }
        .sheet(item: $editing) { episode in
            HealthEpisodeEditor(episode: episode) { saved in
                Task {
                    await HealthDiary.save(saved)
                    await reload()
                }
            }
        }
        .task { await reload() }
    }

    private var ongoing: [HealthEpisode] { episodes.filter(\.isOngoing) }

    private func episodeRow(_ episode: HealthEpisode) -> some View {
        Button { editing = episode } label: {
            HStack(spacing: 12) {
                Image(systemName: episode.condition.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string(episode.condition.displayKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(episode.startedAt.formatted(.dateTime.day().month().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if episode.severity > 0 {
                    Text("\(episode.severity)/10")
                        .font(.caption.bold())
                        .foregroundStyle(tint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        episodes = await HealthDiary.load()
        isLoading = false
    }
}

/// Der Zugang zum Tagebuch, damit die Views nicht selbst am Store hängen.
@MainActor
enum HealthDiary {
    static func load(condition: HealthCondition? = nil) async -> [HealthEpisode] {
        guard let store = try? await HealthPitData.shared.store(),
              let episodes = try? await store.healthEpisodes(condition: condition) else {
            return []
        }
        return episodes
    }

    static func save(_ episode: HealthEpisode) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.upsertHealthEpisode(episode)
    }

    static func delete(_ episode: HealthEpisode) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.deleteHealthEpisode(id: episode.id)
    }
}
