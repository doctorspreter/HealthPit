//
//  HealthDiaryCard.swift
//  Healthpit
//
//  Startseiten-Kachel der physischen Gesundheit.
//
//  Zeigt, was gerade läuft, sonst wie lange es her ist. „Seit 12 Tagen
//  nichts" ist in einem Kopfschmerztagebuch die beste Nachricht, die es gibt,
//  und gehört deshalb auf die Kachel.
//

import SwiftUI

struct HealthDiaryCard: View {
    let size: DashboardWidgetSize

    @State private var episodes: [HealthEpisode] = []

    private var ongoing: [HealthEpisode] { episodes.filter(\.isOngoing) }

    private var daysSinceLast: Int? {
        guard ongoing.isEmpty, let latest = episodes.map(\.startedAt).max() else { return nil }
        return Calendar.healthApp.dateComponents([.day], from: latest, to: Date()).day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(.mint)
                Text(L10n.string("Gesundheit"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(headline)
                .font(.title2.bold())
                .foregroundStyle(ongoing.isEmpty ? Color.secondary : Color.mint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if size != .small {
                Text(subline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .professionalCard(tint: .mint)
        .task { episodes = await HealthDiary.load() }
    }

    private var headline: String {
        if !ongoing.isEmpty { return "\(ongoing.count)" }
        if let days = daysSinceLast { return "\(days)" }
        return "–"
    }

    private var subline: String {
        if let first = ongoing.first {
            return L10n.string(first.condition.displayKey)
        }
        if daysSinceLast != nil {
            return L10n.string("Tage ohne Episode")
        }
        return L10n.string("Noch kein Eintrag")
    }
}
