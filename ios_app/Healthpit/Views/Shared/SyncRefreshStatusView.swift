//
//  SyncRefreshStatusView.swift
//  Healthpit
//
//  Zeigt den laufenden Sync Schritt fuer Schritt und danach die letzten
//  Zeitpunkte.
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

    private var activity = SyncActivity.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch activity.state {
            case .running:
                stepList
            case .succeeded(let count):
                resultRow(
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    text: count == 1
                        ? L10n.string("1 Wert übertragen")
                        : L10n.format("%lld Werte übertragen", Int64(count))
                )
                timestamps
            case .failed(let message):
                resultRow(systemImage: "exclamationmark.triangle.fill", tint: .orange, text: message)
                timestamps
            case .idle:
                timestamps
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.default, value: activity.currentStep)
    }

    /// Alle Schritte auf einmal, damit sichtbar ist was noch kommt — ein
    /// wandernder Spinner allein sagt nicht, wie weit es ist.
    private var stepList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(SyncStep.allCases) { step in
                HStack(spacing: 7) {
                    stepIcon(for: step)
                        .frame(width: 15)
                    Text(step.title)
                        .foregroundStyle(step == activity.currentStep ? Color.primary : Color.secondary)
                    Spacer(minLength: 8)
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(for step: SyncStep) -> some View {
        if activity.finishedSteps.contains(step) {
            Image(systemName: "checkmark").foregroundStyle(.green)
        } else if step == activity.currentStep {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        }
    }

    private func resultRow(systemImage: String, tint: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 15)
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
        }
    }

    private var timestamps: some View {
        VStack(alignment: .leading, spacing: 5) {
            timestampRow(
                title: "Letzte lokale Aktualisierung",
                systemImage: "iphone",
                date: lastLocalRefreshDate
            )
            timestampRow(
                title: "Letzte Übertragung",
                systemImage: "arrow.triangle.2.circlepath",
                date: lastBridgeSyncDate
            )
        }
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
                Text(L10n.string("Noch nie"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
