//
//  DuplicateSettingsView.swift
//  Healthpit
//
//  Trainings, die zweimal in Home Assistant liegen. Die Integration schlaegt
//  Paare vor, entschieden wird hier — bewusst von Hand, weil zwei Einheiten
//  kurz hintereinander genauso echt sein koennen wie eine doppelt gemeldete.
//

import SwiftUI

struct DuplicateSettingsView: View {
    @State private var report = WorkoutDuplicateReport.empty
    @State private var isLoading = false
    @State private var busyKeys: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Zwei Aufzeichnungen derselben Einheit entstehen, wenn mehrere Quellen dasselbe Training melden. Hier entscheidest du, was zusammengehört.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isLoading && report.candidates.isEmpty && report.decisions.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Wird geprüft ...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if report.candidates.isEmpty {
                Section {
                    Label("Keine Duplikate gefunden", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(L10n.format("Vorschläge (%@)", "\(report.candidates.count)")) {
                    ForEach(report.candidates) { candidate in
                        candidateRow(candidate)
                    }
                }
            }

            if !report.decisions.isEmpty {
                Section("Entschieden") {
                    ForEach(report.decisions) { decision in
                        decisionRow(decision)
                    }
                }
            }
        }
        .navigationTitle("Duplikate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .alert("Duplikate", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Zeilen

    @ViewBuilder
    private func candidateRow(_ candidate: WorkoutDuplicateCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(candidate.reasonText)
                    .font(.subheadline.bold())
                Spacer()
                Text(confidenceText(candidate.confidence))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            sideRow(candidate.left)
            Divider()
            sideRow(candidate.right)

            if busyKeys.contains(candidate.id) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Wird gespeichert ...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        Task { await decide(candidate, .merge) }
                    } label: {
                        // Ohne Symbol und mit einer Zeile: „Zusammenfuehren"
                        // brach sonst mitten im Wort um, und in den laengeren
                        // Sprachen wird es nicht kuerzer.
                        Text("Zusammenführen")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await decide(candidate, .separate) }
                    } label: {
                        Text("Getrennt lassen")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sideRow(_ side: WorkoutDuplicateSide) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(side.sportLabel)
                .font(.callout)
            Text(detailLine(side))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(originLine(side))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func decisionRow(_ decision: WorkoutDuplicateDecision) -> some View {
        HStack {
            Label(
                decision.isMerge
                    ? L10n.string("Als ein Training")
                    : L10n.string("Als zwei Trainings"),
                systemImage: decision.isMerge ? "arrow.triangle.merge" : "arrow.triangle.branch"
            )
            .font(.footnote)
            Spacer()
            if busyKeys.contains(decision.id) {
                ProgressView()
            } else {
                Button("Zurücknehmen") {
                    Task { await undo(decision) }
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Texte

    private func detailLine(_ side: WorkoutDuplicateSide) -> String {
        var parts: [String] = []
        if let date = side.startDate {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        } else if !side.start.isEmpty {
            parts.append(side.start)
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

    private func originLine(_ side: WorkoutDuplicateSide) -> String {
        // Das Geraet heisst oft wie die Quelle („GymPit" · „GymPit"). Einmal
        // reicht; der Name traegt nur etwas bei, wenn er etwas Neues sagt.
        guard !side.deviceID.isEmpty,
              side.deviceID.caseInsensitiveCompare(side.sourceLabel) != .orderedSame else {
            return side.sourceLabel
        }
        return "\(side.sourceLabel) · \(side.deviceID)"
    }

    private func confidenceText(_ value: Double) -> String {
        L10n.format("Sicherheit %@ %%", "\(Int((value * 100).rounded()))")
    }

    // MARK: - Aktionen

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            report = try await BridgeSyncService.shared.loadDuplicates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decide(_ candidate: WorkoutDuplicateCandidate, _ action: WorkoutDuplicateAction) async {
        busyKeys.insert(candidate.id)
        defer { busyKeys.remove(candidate.id) }
        do {
            try await BridgeSyncService.shared.decideDuplicate(
                primary: candidate.left.key,
                linked: candidate.right.key,
                action: action
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ decision: WorkoutDuplicateDecision) async {
        busyKeys.insert(decision.id)
        defer { busyKeys.remove(decision.id) }
        do {
            try await BridgeSyncService.shared.undoDuplicateDecision(
                primary: decision.primary,
                linked: decision.linked
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        DuplicateSettingsView()
    }
}
