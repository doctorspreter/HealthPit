//
//  SyncRefreshStatusView.swift
//  Healthpit
//
//  Zeigt nach einer Aktualisierung die letzten lokalen und Bridge-Zeitpunkte.
//

import SwiftUI

enum SyncRefreshStatusStore {
    static func markLocalRefresh(at date: Date = .now) {
        UserDefaults.standard.set(date, forKey: BridgeSettings.lastLocalRefreshDateKey)
    }
}

struct SyncRefreshStatusView: View {
    @AppStorage(BridgeSettings.lastLocalRefreshDateKey) private var lastLocalRefreshDate = Date.distantPast
    @AppStorage(BridgeSettings.lastSyncDateKey) private var lastBridgeSyncDate = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            timestampRow(
                title: "Letzte lokale Aktualisierung",
                systemImage: "iphone",
                date: lastLocalRefreshDate
            )
            timestampRow(
                title: "Letzter Bridge-Sync",
                systemImage: "arrow.triangle.2.circlepath",
                date: lastBridgeSyncDate
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func timestampRow(title: String, systemImage: String, date: Date) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .frame(width: 15)
            Text(L10n.string(title))
            Spacer(minLength: 8)
            if date > .distantPast {
                Text(date, format: .dateTime.day().month().hour().minute())
                    .foregroundStyle(.primary)
            } else {
                Text("Noch nie")
            }
        }
    }
}
