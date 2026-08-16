//
//  DuplicateMergeSheet.swift
//  Healthpit
//
//  Zusammenfuehren mit Auswahl: welche der beiden Aufzeichnungen bleibt, und
//  soll die andere auch aus Apple Health verschwinden?
//
//  Der zweite Teil hat eine Grenze, die nicht bei HealthPit liegt: iOS laesst
//  jede App nur ihre eigenen Eintraege in Apple Health loeschen. Kommt dasselbe
//  Training von Health Sync und von Huawei, kann HealthPit keine der beiden
//  Kopien entfernen — das muss vor der Entscheidung dastehen und nicht als
//  Fehlermeldung danach.
//

import SwiftUI

/// Was der Anwender entschieden hat.
struct WorkoutDuplicateMergeChoice: Sendable {
    enum Keep: Sendable { case left, right }
    var keep: Keep
    /// Die nicht behaltene Aufzeichnung auch aus Apple Health entfernen.
    var removeFromAppleHealth: Bool
}

struct DuplicateMergeSheet: View {
    let candidate: WorkoutDuplicateCandidate
    let onConfirm: (WorkoutDuplicateMergeChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keep: WorkoutDuplicateMergeChoice.Keep = .left
    @State private var removeFromAppleHealth = false
    @State private var origins: [String: HealthKitManager.AppleHealthOrigin] = [:]
    @State private var isChecking = true

    private var discarded: WorkoutDuplicateSide {
        keep == .left ? candidate.right : candidate.left
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.string("Beide Aufzeichnungen erscheinen ab jetzt als ein Training. Welche davon behalten wird, entscheidet, was in Apple Health gelöscht werden kann."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.string("Behalten")) {
                    choiceRow(.left, candidate.left)
                    choiceRow(.right, candidate.right)
                }

                Section {
                    appleHealthSection
                } header: {
                    Text(L10n.string("Apple Health"))
                }

                Section {
                    Button(L10n.string("Zusammenführen")) {
                        onConfirm(WorkoutDuplicateMergeChoice(
                            keep: keep,
                            removeFromAppleHealth: removeFromAppleHealth && canDeleteDiscarded
                        ))
                        dismiss()
                    }
                    .disabled(isChecking)
                }
            }
            .navigationTitle(L10n.string("Zusammenführen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("Abbrechen")) { dismiss() }
                }
            }
            .task { await checkOrigins() }
        }
    }

    // MARK: - Auswahl

    @ViewBuilder
    private func choiceRow(_ value: WorkoutDuplicateMergeChoice.Keep,
                           _ side: WorkoutDuplicateSide) -> some View {
        Button {
            keep = value
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: keep == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(keep == value ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(side.sportLabel)
                        .font(.callout)
                    Text(side.sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(detailLine(side))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Apple Health

    @ViewBuilder
    private var appleHealthSection: some View {
        if isChecking {
            HStack(spacing: 10) {
                ProgressView()
                Text(L10n.string("Wird geprüft ..."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if let uuid = discarded.appleHealthUUID, let origin = origins[uuid.uuidString] {
            switch origin {
            case .ours:
                Toggle(isOn: $removeFromAppleHealth) {
                    Text(L10n.string("Die andere Aufzeichnung auch aus Apple Health löschen"))
                        .font(.footnote)
                }
            case .foreign(let app):
                explanation(
                    L10n.format("Dieser Eintrag wurde von %@ geschrieben. Apple Health erlaubt das Löschen nur der App, die ihn angelegt hat — HealthPit kann ihn dort nicht entfernen.", app),
                    systemImage: "lock"
                )
                openHealthButton
            case .missing:
                explanation(
                    L10n.string("Zu dieser Aufzeichnung liegt in Apple Health nichts (mehr) vor."),
                    systemImage: "questionmark.circle"
                )
            }
        } else {
            explanation(
                L10n.string("Diese Aufzeichnung stammt nicht aus Apple Health. In HealthPit und Home Assistant wird sie trotzdem zusammengeführt."),
                systemImage: "info.circle"
            )
        }
    }

    private var openHealthButton: some View {
        Button {
            if let url = URL(string: "x-apple-health://") {
                UIApplication.shared.open(url)
            }
        } label: {
            Label(L10n.string("Apple Health öffnen"), systemImage: "arrow.up.forward.app")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private func explanation(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }

    private var canDeleteDiscarded: Bool {
        guard let uuid = discarded.appleHealthUUID else { return false }
        return origins[uuid.uuidString]?.isDeletable == true
    }

    // MARK: - Daten

    /// Fuer beide Seiten nachsehen, wer den Eintrag geschrieben hat.
    ///
    /// Beide, nicht nur die verworfene: die Auswahl laesst sich umstellen, und
    /// dann muss die Auskunft sofort danebenstehen und nicht erst nachgeladen
    /// werden.
    private func checkOrigins() async {
        isChecking = true
        defer { isChecking = false }
        var found: [String: HealthKitManager.AppleHealthOrigin] = [:]
        for side in [candidate.left, candidate.right] {
            guard let uuid = side.appleHealthUUID else { continue }
            found[uuid.uuidString] = await HealthKitManager.shared.origin(ofWorkout: uuid)
        }
        origins = found
    }

    private func detailLine(_ side: WorkoutDuplicateSide) -> String {
        var parts: [String] = []
        if let date = side.startDate {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if side.durationSeconds > 0 {
            parts.append(L10n.format("%@ min", "\(Int((side.durationSeconds / 60).rounded()))"))
        }
        if let distance = side.distanceKm, distance > 0 {
            parts.append(String(format: "%.2f km", distance))
        }
        if side.setCount > 0 {
            parts.append(L10n.format("%@ Sätze", "\(side.setCount)"))
        }
        return parts.joined(separator: " · ")
    }
}
