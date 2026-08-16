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
    @State private var merging: WorkoutDuplicateCandidate?
    @State private var noticeMessage: String?

    var body: some View {
        List {
            Section {
                Text(L10n.string("Zwei Aufzeichnungen derselben Einheit entstehen, wenn mehrere Quellen dasselbe Training melden. Hier entscheidest du, was zusammengehört."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isLoading && report.candidates.isEmpty && report.decisions.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.string("Wird geprüft ..."))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if report.candidates.isEmpty {
                Section {
                    Label(L10n.string("Keine Duplikate gefunden"), systemImage: "checkmark.circle")
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
                Section(L10n.string("Entschieden")) {
                    ForEach(report.decisions) { decision in
                        decisionRow(decision)
                    }
                }
            }
        }
        .navigationTitle(L10n.string("Duplikate"))
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
        .alert(L10n.string("Duplikate"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.string("OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(L10n.string("Zusammengeführt"), isPresented: Binding(
            get: { noticeMessage != nil },
            set: { if !$0 { noticeMessage = nil } }
        )) {
            Button(L10n.string("OK"), role: .cancel) {}
        } message: {
            Text(noticeMessage ?? "")
        }
        .sheet(item: $merging) { candidate in
            DuplicateMergeSheet(candidate: candidate) { choice in
                Task { await merge(candidate, choice) }
            }
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
                    Text(L10n.string("Wird gespeichert ..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        // Nicht sofort entscheiden: erst fragen, welche der
                        // beiden bleibt und was mit der anderen in Apple
                        // Health geschehen soll.
                        merging = candidate
                    } label: {
                        // Ohne Symbol und mit einer Zeile: „Zusammenfuehren"
                        // brach sonst mitten im Wort um, und in den laengeren
                        // Sprachen wird es nicht kuerzer.
                        Text(L10n.string("Zusammenführen"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await decide(candidate, .separate) }
                    } label: {
                        Text(L10n.string("Getrennt lassen"))
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
        VStack(alignment: .leading, spacing: 8) {
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
                    Button(L10n.string("Zurücknehmen")) {
                        Task { await undo(decision) }
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                }
            }

            // Worum es ging. Ohne diese Zeilen war jede Entscheidung von jeder
            // anderen ununterscheidbar.
            if decision.sides.isEmpty {
                Text(L10n.string("Die zugehörigen Trainings sind nicht mehr vorhanden."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(decision.sides.enumerated()), id: \.offset) { index, side in
                    if index > 0 { Divider() }
                    sideRow(side)
                }
            }
        }
        .padding(.vertical, 4)
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

    /// Zusammenfuehren, und auf Wunsch die verworfene Kopie aus Apple Health
    /// entfernen.
    ///
    /// Die Reihenfolge ist Absicht: erst die Entscheidung, die Home Assistant
    /// ohnehin dauerhaft haelt, dann das Loeschen. Scheitert das Loeschen, ist
    /// die Zusammenfuehrung trotzdem gespeichert — umgekehrt waere ein Eintrag
    /// weg, ohne dass jemand das Paar entschieden haette.
    private func merge(_ candidate: WorkoutDuplicateCandidate,
                       _ choice: WorkoutDuplicateMergeChoice) async {
        busyKeys.insert(candidate.id)
        defer { busyKeys.remove(candidate.id) }

        let kept = choice.keep == .left ? candidate.left : candidate.right
        let discarded = choice.keep == .left ? candidate.right : candidate.left
        do {
            try await BridgeSyncService.shared.decideDuplicate(
                primary: kept.key,
                linked: discarded.key,
                action: .merge
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if choice.removeFromAppleHealth, let uuid = discarded.appleHealthUUID {
            do {
                switch try await HealthKitManager.shared.deleteWorkout(uuid: uuid) {
                case .ours:
                    noticeMessage = L10n.string("Die Aufzeichnung wurde auch aus Apple Health gelöscht.")
                case .foreign(let app):
                    noticeMessage = L10n.format("In Apple Health blieb der Eintrag stehen: Er wurde von %@ geschrieben, und nur diese App darf ihn löschen.", app)
                case .missing:
                    noticeMessage = L10n.string("In Apple Health war zu dieser Aufzeichnung nichts mehr vorhanden.")
                }
            } catch {
                noticeMessage = error.localizedDescription
            }
        }

        await load()
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
