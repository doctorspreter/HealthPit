//
//  HealthConditionDetailView.swift
//  Healthpit
//
//  Ein einzelnes Tagebuch: Verlauf, Muster, Einträge.
//
//  Die Auswertung oben beantwortet, wonach in so einem Tagebuch überhaupt
//  gesucht wird: Wie oft war es zuletzt? Wie stark im Schnitt? Und was steht
//  am häufigsten daneben, wenn es auftritt? Der häufigste Auslöser ist der
//  einzige Grund, warum jemand so ein Tagebuch überhaupt führt.
//

import SwiftUI
import Charts

struct HealthConditionDetailView: View {
    let condition: HealthCondition
    var onChange: () -> Void = {}

    @State private var episodes: [HealthEpisode] = []
    @State private var editing: HealthEpisode?
    @State private var isLoading = true

    private let tint = Color.mint
    private let calendar = Calendar.healthApp

    var body: some View {
        List {
            Section { summary }

            if !monthlyCounts.isEmpty {
                Section(L10n.string("Häufigkeit")) {
                    Chart(monthlyCounts, id: \.month) { entry in
                        BarMark(x: .value("Monat", entry.month, unit: .month),
                                y: .value("Anzahl", entry.count))
                            .foregroundStyle(tint)
                    }
                    .frame(height: 150)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.caption2)
                        }
                    }
                }
            }

            if !topTriggers.isEmpty {
                Section(L10n.string("Häufigste Auslöser")) {
                    ForEach(topTriggers, id: \.trigger) { entry in
                        HStack {
                            Text(L10n.string(entry.trigger.displayKey))
                                .font(.subheadline)
                            Spacer()
                            Text(L10n.format("%lld×", Int64(entry.count)))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !topSymptoms.isEmpty {
                Section(L10n.string("Häufigste Begleiterscheinungen")) {
                    ForEach(topSymptoms, id: \.symptom) { entry in
                        HStack {
                            Text(L10n.string(entry.symptom.displayKey))
                                .font(.subheadline)
                            Spacer()
                            Text(L10n.format("%lld×", Int64(entry.count)))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(L10n.string("Einträge")) {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ForEach(episodes) { episode in
                        row(episode)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(L10n.string(condition.displayKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = HealthEpisode(condition: condition)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.string("Eintrag hinzufügen"))
            }
        }
        .sheet(item: $editing) { episode in
            HealthEpisodeEditor(episode: episode) { saved in
                Task {
                    await HealthDiary.save(saved)
                    await reload()
                    onChange()
                }
            }
        }
        .task { await reload() }
    }

    // MARK: Auswertung

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .leading)],
                  alignment: .leading, spacing: 14) {
            stat(L10n.string("Einträge"), "\(episodes.count)")
            if let average = averageSeverity {
                stat(L10n.string("Ø Stärke"), String(format: "%.1f/10", average))
            }
            if let averageDuration {
                stat(L10n.string("Ø Dauer"), formatWorkoutDuration(averageDuration))
            }
            if last30Days > 0 {
                stat(L10n.string("Letzte 30 Tage"), "\(last30Days)")
            }
            if let helped = medicationHelpRate {
                stat(L10n.string("Medikament half"), "\(Int(helped * 100)) %")
            }
        }
        .padding(.vertical, 2)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var averageSeverity: Double? {
        let values = episodes.map(\.severity).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var averageDuration: TimeInterval? {
        let values = episodes.compactMap(\.duration).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var last30Days: Int {
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) else { return 0 }
        return episodes.filter { $0.startedAt >= cutoff }.count
    }

    /// Nur über die Einträge, bei denen überhaupt ein Medikament steht —
    /// sonst zählten leere Felder als „hat nicht geholfen".
    private var medicationHelpRate: Double? {
        let answered = episodes.filter { !$0.medication.isEmpty && $0.medicationHelped != nil }
        guard !answered.isEmpty else { return nil }
        let helped = answered.filter { $0.medicationHelped == true }.count
        return Double(helped) / Double(answered.count)
    }

    private var monthlyCounts: [(month: Date, count: Int)] {
        Dictionary(grouping: episodes) { calendar.startOfMonth(for: $0.startedAt) }
            .map { (month: $0.key, count: $0.value.count) }
            .sorted { $0.month < $1.month }
    }

    private var topTriggers: [(trigger: EpisodeTrigger, count: Int)] {
        episodes.flatMap(\.triggers)
            .reduce(into: [EpisodeTrigger: Int]()) { $0[$1, default: 0] += 1 }
            .map { (trigger: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    private var topSymptoms: [(symptom: EpisodeSymptom, count: Int)] {
        episodes.flatMap(\.symptoms)
            .reduce(into: [EpisodeSymptom: Int]()) { $0[$1, default: 0] += 1 }
            .map { (symptom: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    // MARK: Liste

    private func row(_ episode: HealthEpisode) -> some View {
        Button { editing = episode } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(episode.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if episode.severity > 0 {
                        Text("\(episode.severity)/10")
                            .font(.caption.bold())
                            .foregroundStyle(tint)
                    }
                }
                if !detailLine(episode).isEmpty {
                    Text(detailLine(episode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    await HealthDiary.delete(episode)
                    await reload()
                    onChange()
                }
            } label: {
                Label(L10n.string("Löschen"), systemImage: "trash")
            }
        }
    }

    private func detailLine(_ episode: HealthEpisode) -> String {
        var parts: [String] = []
        if let subtype = episode.subtype {
            parts.append(L10n.string(subtype.displayKey))
        }
        if let duration = episode.duration, duration > 0 {
            parts.append(formatWorkoutDuration(duration))
        } else if episode.isOngoing {
            parts.append(L10n.string("läuft"))
        }
        if !episode.symptoms.isEmpty {
            parts.append(episode.symptoms
                .map { L10n.string($0.displayKey) }
                .sorted()
                .joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func reload() async {
        episodes = await HealthDiary.load(condition: condition)
        isLoading = false
    }
}
