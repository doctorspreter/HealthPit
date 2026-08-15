//
//  CycleDetailView.swift
//  Healthpit
//
//  Zyklusuebersicht mit Kalender, Zyklusliste und Ereignissen – plus Eingabe
//  eigener Eintraege, die nach Apple Health zurueckgeschrieben werden.
//

import HealthKit
import SwiftUI

struct CycleDetailView: View {
    @State private var overview = CycleOverview()
    @State private var isLoading = true
    @State private var editingDate: Date?
    @State private var message: String?
    /// Der angezeigte Monat. Vorher war das Raster fest auf die letzten sechs
    /// Wochen verdrahtet, aeltere Eintraege waren damit unerreichbar.
    @State private var visibleMonth = Calendar.healthApp.startOfMonth(for: Date())

    private let health = HealthKitManager.shared

    var body: some View {
        Group {
            if isLoading {
                ProgressView(L10n.string("Lade …"))
            } else {
                List {
                    Section {
                        ProfessionalPageHero(
                            eyebrow: "Zyklusgesundheit",
                            title: "Dein Zyklus",
                            subtitle: "Verlauf, Blutung und Symptome diskret und übersichtlich dokumentiert.",
                            symbol: "drop.circle.fill",
                            tint: HealthCategory.cycle.tint,
                            value: overview.currentCycleDay.map { "Tag \($0)" } ?? "–",
                            detail: "aktueller Zyklus"
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 10, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    summarySection
                    monthControls
                    calendarSection
                    cyclesSection
                    eventsSection
                    if let message {
                        Section {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .professionalPageBackground(tint: HealthCategory.cycle.tint)
        .navigationTitle(HealthCategory.cycle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingDate = Calendar.healthApp.startOfDay(for: Date())
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Eintrag hinzufügen")
            }
        }
        .sheet(item: Binding(
            get: { editingDate.map(EditableDay.init(date:)) },
            set: { editingDate = $0?.date }
        )) { day in
            CycleDayEditorView(date: day.date,
                               existing: overview.entry(on: day.date)) {
                await reload()
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Abschnitte

    @ViewBuilder
    private var summarySection: some View {
        if overview.hasData {
            Section {
                HStack(spacing: 12) {
                    summaryTile(overview.currentCycleDay.map { L10n.format("Tag %lld", $0) } ?? "–",
                                "aktueller Zyklustag")
                    summaryTile(overview.averageCycleLength.map { L10n.format("%lld Tage", $0) } ?? "–",
                                "Ø Zyklus")
                    summaryTile(overview.averagePeriodLength.map { L10n.format("%lld Tage", $0) } ?? "–",
                                "Ø Periode")
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("Noch keine Zyklusdaten"))
                        .font(.subheadline.bold())
                    Text(L10n.string("HealthPit zeigt hier, was in Apple Health steht. Über „+“ lassen sich eigene Einträge anlegen; sie werden nach Apple Health zurückgeschrieben."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .professionalCard(tint: HealthCategory.cycle.tint)
            }
        }
    }

    private func summaryTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(L10n.string(label))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .professionalCard(tint: HealthCategory.cycle.tint, cornerRadius: 16)
    }

    private var monthControls: some View {
        Section {
            HStack(spacing: 10) {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)

                Text(visibleMonth, format: .dateTime.month(.wide).year())
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(isCurrentMonth)
            }
        }
    }

    /// Der gewaehlte Monat als Raster – ein Tippen oeffnet die Eingabe.
    private var calendarSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                      spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // Der Monat faengt selten am Wochenanfang an; die Luecken halten
                // die Wochentagsspalten in einer Linie.
                ForEach(0..<leadingBlanks, id: \.self) { index in
                    Color.clear.frame(height: 1).id("blank-\(index)")
                }
                ForEach(monthDays, id: \.self) { day in
                    Button {
                        editingDate = day
                    } label: {
                        dayCell(day)
                    }
                    .buttonStyle(.plain)
                    .disabled(day > Date())
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let entry = overview.entry(on: day)
        let isToday = Calendar.healthApp.isDateInToday(day)
        return VStack(spacing: 2) {
            Text(day.formatted(.dateTime.day()))
                .font(.caption2)
                .foregroundStyle(entry?.flow.isBleeding == true ? .white : .primary)
            Circle()
                .fill(entry?.flow.isBleeding == true ? Color.white.opacity(0.9) : .clear)
                .frame(width: 4, height: 4)
                .opacity(entry?.isCycleStart == true ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(cellColor(for: entry), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isToday ? HealthCategory.cycle.tint : .clear, lineWidth: 1.5)
        }
    }

    private func cellColor(for entry: CycleDayEntry?) -> Color {
        guard let entry, entry.flow.isBleeding else { return Color(.secondarySystemBackground) }
        switch entry.flow.intensity {
        case 3:  return HealthCategory.cycle.tint
        case 2:  return HealthCategory.cycle.tint.opacity(0.75)
        default: return HealthCategory.cycle.tint.opacity(0.5)
        }
    }

    @ViewBuilder
    private var cyclesSection: some View {
        if !overview.cycles.isEmpty {
            Section(L10n.string("Zyklen")) {
                ForEach(overview.cycles.reversed()) { cycle in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cycle.start.formatted(.dateTime.day().month().year()))
                                .font(.subheadline.bold())
                            Text(L10n.format("%lld Blutungstage", cycle.bleedingDays))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let length = cycle.lengthInDays {
                            Text(L10n.format("%lld Tage", length))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L10n.string("läuft"))
                                .font(.caption)
                                .foregroundStyle(HealthCategory.cycle.tint)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        if !overview.events.isEmpty {
            Section(L10n.string("Ereignisse")) {
                ForEach(Array(overview.events.prefix(30))) { event in
                    HStack {
                        Image(systemName: event.kind.systemImage)
                            .foregroundStyle(HealthCategory.cycle.tint)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.kind.title)
                                .font(.subheadline)
                            Text(event.valueTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(event.date.formatted(.dateTime.day().month()))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await delete(event) }
                        } label: {
                            Label(L10n.string("Löschen"), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: Daten

    private var isCurrentMonth: Bool {
        visibleMonth >= Calendar.healthApp.startOfMonth(for: Date())
    }

    private var monthDays: [Date] {
        let calendar = Calendar.healthApp
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: visibleMonth) }
    }

    /// Wie viele Leerfelder vor dem Ersten stehen, abhaengig vom Wochenanfang
    /// der Region.
    private var leadingBlanks: Int {
        let calendar = Calendar.healthApp
        let weekday = calendar.component(.weekday, from: visibleMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.healthApp
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func shiftMonth(by offset: Int) {
        let calendar = Calendar.healthApp
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else {
            return
        }
        let limit = calendar.startOfMonth(for: Date())
        visibleMonth = min(shifted, limit)
        Task { await reload() }
    }

    private func delete(_ event: CycleEvent) async {
        do {
            try await health.deleteCycleEvent(kind: event.kind, date: event.date)
            await reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload() async {
        isLoading = overview.days.isEmpty && overview.events.isEmpty
        defer { isLoading = false }
        do {
            // Bis zum angezeigten Monat zurueckladen, sonst ist beim Blaettern
            // in die Vergangenheit alles leer.
            let calendar = Calendar.healthApp
            let months = calendar.dateComponents([.month], from: visibleMonth, to: Date()).month ?? 0
            overview = try await health.fetchCycleOverview(monthsBack: max(12, months + 2))
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Huelle, damit `Date` als `sheet(item:)` taugt.
private struct EditableDay: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - Eingabe

struct CycleDayEditorView: View {
    let date: Date
    let existing: CycleDayEntry?
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var flow: MenstrualFlow = .none
    @State private var isCycleStart = false
    @State private var ovulationResult: Int = 0
    @State private var hasIntermenstrualBleeding = false
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var message: String?

    private let health = HealthKitManager.shared

    /// Rohwerte von `HKCategoryValueOvulationTestResult`; 0 heisst "nicht erfasst".
    private let ovulationOptions: [(value: Int, title: String)] = [
        (0, "Kein Test"),
        (1, "Negativ"),
        (2, "LH-Anstieg"),
        (4, "Östrogen-Anstieg"),
        (3, "Nicht eindeutig"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L10n.string("Tag")) {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month().year()))
                    }
                }

                Section(L10n.string("Blutung")) {
                    Picker(L10n.string("Stärke"), selection: $flow) {
                        ForEach(MenstrualFlow.selectable) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(L10n.string("Erster Tag des Zyklus"), isOn: $isCycleStart)
                        .disabled(!flow.isBleeding)

                    Text(L10n.string("„Keine Blutung“ entfernt einen zuvor in HealthPit angelegten Eintrag für diesen Tag."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.string("Weitere Einträge")) {
                    Picker(L10n.string("Ovulationstest"), selection: $ovulationResult) {
                        ForEach(ovulationOptions, id: \.value) { option in
                            Text(L10n.string(option.title)).tag(option.value)
                        }
                    }
                    Toggle(L10n.string("Zwischenblutung"), isOn: $hasIntermenstrualBleeding)
                    Text(L10n.string("Diese beiden Einträge werden ergänzt, nicht ersetzt – ein bereits gespeicherter Eintrag bleibt bestehen."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let existing, !existing.isOwnEntry {
                    Section {
                        Text(L10n.string("Der vorhandene Eintrag stammt aus einer anderen App. HealthPit ändert ihn nicht, sondern legt einen eigenen Eintrag daneben an."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if existing?.isOwnEntry == true {
                    Section {
                        Button(role: .destructive) {
                            Task { await deleteEntry() }
                        } label: {
                            HStack {
                                if isDeleting { ProgressView() }
                                Text(L10n.string("Eintrag löschen"))
                            }
                        }
                        .disabled(isDeleting || isSaving)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.string("Zyklus-Eintrag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text(L10n.string("Sichern")) }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                flow = existing?.flow ?? .none
                isCycleStart = existing?.isCycleStart ?? false
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await health.saveCycleDay(date: date,
                                          flow: flow,
                                          isCycleStart: isCycleStart && flow.isBleeding)
            if ovulationResult != 0 {
                try await health.saveCycleEvent(kind: .ovulationTest,
                                                date: date,
                                                rawValue: ovulationResult)
            }
            if hasIntermenstrualBleeding {
                // Zwischenblutung kennt keine Abstufung – HealthKit erwartet
                // hier den Platzhalterwert.
                try await health.saveCycleEvent(kind: .intermenstrualBleeding,
                                                date: date,
                                                rawValue: HKCategoryValue.notApplicable.rawValue)
            }
            await onSaved()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Entfernt alles, was Healthpit an diesem Tag angelegt hat.
    private func deleteEntry() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await health.deleteCycleEntries(on: date)
            await onSaved()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
