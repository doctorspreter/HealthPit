//
//  PainCard.swift
//  Healthpit
//
//  Startseiten-Kachel fuer Schmerzen und Verletzungen.
//
//  Zeigt, was laeuft. Ist nichts offen, sagt sie das — eine leere Kachel
//  waere in diesem Bereich die schlechteste Auskunft.
//

import SwiftUI

struct PainCard: View {
    let size: DashboardWidgetSize

    @State private var entries: [PainEntry] = []

    private var ongoing: [PainEntry] { entries.filter(\.isOngoing) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bandage.fill")
                    .foregroundStyle(.red)
                Text(L10n.string("Schmerzen"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(ongoing.isEmpty ? "–" : "\(ongoing.count)")
                .font(.title2.bold())
                .foregroundStyle(ongoing.isEmpty ? Color.secondary : Color.red)

            if size != .small {
                Text(ongoing.isEmpty
                     ? L10n.string("Nichts Laufendes")
                     : L10n.string(ongoing[0].region.displayKey))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .professionalCard(tint: .red)
        .task { entries = await PainJournal.load() }
    }
}
