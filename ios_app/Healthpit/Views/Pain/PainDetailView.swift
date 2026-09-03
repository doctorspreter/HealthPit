//
//  PainDetailView.swift
//  Healthpit
//
//  Schmerzen und Verletzungen: Kalender, laufende Beschwerden, Verlauf.
//
//  Der Kalender ist der Einstieg — Beschwerden liest man an ihrem Muster,
//  nicht an einer Zahl. Ein Tag ist eingefaerbt, solange eine Beschwerde ihn
//  ueberdeckt: nicht nur der Tag des Eintrags, sondern die ganze Spanne bis
//  zum Ende. Eine Zerrung ueber zwei Wochen ist zwei Wochen lang da.
//

import SwiftUI

struct PainDetailView: View {
    @State private var entries: [PainEntry] = []
    @State private var referenceMonth = Date()
    @State private var selectedDay: Date?
    @State private var editing: PainEntry?
    @State private var isLoading = true

    private let calendar = Calendar.healthApp
    private let tint = Color.red

    var body: some View {
        List {
            header
            calendarSection
            if !ongoing.isEmpty {
                Section(L10n.string("Laufende Beschwerden")) {
                    ForEach(ongoing) { entry in row(entry) }
                }
            }
            entriesSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(L10n.string("Schmerzen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = PainEntry(startedAt: selectedDay ?? .now)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.string("Eintrag hinzufügen"))
            }
        }
        .sheet(item: $editing) { entry in
            PainEntryEditor(entry: entry) { saved in
                Task {
                    await PainJournal.save(saved)
                    await reload()
                }
            }
        }
        .task { await reload() }
    }

    // MARK: Kopf

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Schmerzen & Verletzungen"))
                    .font(.title2.bold())
                Text(L10n.string("Was wehtut, wo es sitzt und wie lange es bleibt."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !isLoading {
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(ongoing.isEmpty ? .secondary : tint)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var summaryLine: String {
        if ongoing.isEmpty {
            return entries.isEmpty
                ? L10n.string("Noch nichts eingetragen.")
                : L10n.string("Zurzeit nichts Laufendes.")
        }
        return L10n.format("%lld laufend", Int64(ongoing.count))
    }

    // MARK: Kalender

    private var calendarSection: some View {
        Section {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(referenceMonth, format: .dateTime.month(.wide).year())
                    .font(.subheadline.bold())
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .disabled(nextMonthIsFuture)
            }

            // Feste Zeilen statt LazyVGrid: ein Lazy-Container in einer
            // Listenzeile treibt UIKit in eine Layout-Schleife.
            HStack(spacing: 4) {
                ForEach(weekdayHeaders, id: \.self) { title in
                    Text(title)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(monthWeeks().enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        dayCell(day)
                    }
                }
            }

            if let selectedDay {
                Button {
                    self.selectedDay = nil
                } label: {
                    Label(selectedDay.formatted(.dateTime.weekday(.abbreviated).day().month()),
                          systemImage: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let severity = peakSeverity(on: day)
            let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(fill(for: severity))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .overlay {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.caption2.bold())
                        .foregroundStyle(severity == nil ? Color.secondary : Color.white)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.primary, lineWidth: 2)
                    } else if calendar.isDateInToday(day) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.orange, lineWidth: 2)
                    }
                }
                .onTapGesture {
                    selectedDay = isSelected ? nil : day
                }
                .accessibilityLabel(day.formatted(.dateTime.day().month()))
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 26)
        }
    }

    /// Je staerker der Schmerz, desto kraeftiger der Tag. Ohne Angabe der
    /// Staerke bleibt eine mittlere Toenung — der Tag zaehlt trotzdem.
    private func fill(for severity: Int?) -> Color {
        guard let severity else { return Color.secondary.opacity(0.14) }
        if severity <= 0 { return tint.opacity(0.45) }
        return tint.opacity(0.30 + min(Double(severity), 10) / 10 * 0.7)
    }

    // MARK: Liste

    private var entriesSection: some View {
        Section(listTitle) {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if visibleEntries.isEmpty {
                Text(L10n.string("Für diesen Zeitraum ist nichts eingetragen."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleEntries) { entry in row(entry) }
            }
        }
    }

    private var listTitle: String {
        selectedDay == nil ? L10n.string("Im Monat") : L10n.string("Am gewählten Tag")
    }

    private func row(_ entry: PainEntry) -> some View {
        Button {
            editing = entry
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.kind.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string(entry.region.displayKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detailLine(entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entry.isFromWorkout {
                        Label(L10n.string("Aus einem Training"), systemImage: "figure.run")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if entry.severity > 0 {
                    Text("\(entry.severity)/10")
                        .font(.caption.bold())
                        .foregroundStyle(tint)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    await PainJournal.delete(entry)
                    await reload()
                }
            } label: {
                Label(L10n.string("Löschen"), systemImage: "trash")
            }
        }
    }

    private func detailLine(_ entry: PainEntry) -> String {
        var parts: [String] = []
        if let quality = entry.quality {
            parts.append(L10n.string(quality.displayKey))
        }
        parts.append(entry.startedAt.formatted(.dateTime.day().month().year()))
        if let end = entry.endedAt {
            parts.append("– " + end.formatted(.dateTime.day().month().year()))
        } else {
            parts.append(L10n.string("läuft"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Auswertung

    private var ongoing: [PainEntry] {
        entries.filter(\.isOngoing)
    }

    private var visibleEntries: [PainEntry] {
        if let selectedDay {
            return entries.filter { covers($0, day: selectedDay) }
        }
        guard let interval = calendar.dateInterval(of: .month, for: referenceMonth) else {
            return entries
        }
        return entries.filter { overlaps($0, interval: interval) }
    }

    /// Eine Beschwerde deckt jeden Tag von ihrem Beginn bis zu ihrem Ende ab –
    /// laeuft sie noch, bis heute.
    private func covers(_ entry: PainEntry, day: Date) -> Bool {
        let start = calendar.startOfDay(for: entry.startedAt)
        let end = calendar.startOfDay(for: entry.endedAt ?? Date())
        let target = calendar.startOfDay(for: day)
        return target >= start && target <= end
    }

    private func overlaps(_ entry: PainEntry, interval: DateInterval) -> Bool {
        let end = entry.endedAt ?? Date()
        return entry.startedAt < interval.end && end >= interval.start
    }

    private func peakSeverity(on day: Date) -> Int? {
        let covering = entries.filter { covers($0, day: day) }
        guard !covering.isEmpty else { return nil }
        return covering.map(\.severity).max() ?? 0
    }

    // MARK: Kalenderraster

    private var weekdayHeaders: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func monthWeeks() -> [[Date?]] {
        var days = monthGridDays()
        guard !days.isEmpty else { return [] }
        let remainder = days.count % 7
        if remainder != 0 {
            days += Array(repeating: nil, count: 7 - remainder)
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    private func monthGridDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: referenceMonth),
              let range = calendar.range(of: .day, in: .month, for: interval.start) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
        return Array(repeating: nil, count: leading) + days
    }

    private var nextMonthIsFuture: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: referenceMonth) else {
            return true
        }
        return next > Date()
    }

    private func shiftMonth(_ offset: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: referenceMonth) else {
            return
        }
        referenceMonth = shifted
        selectedDay = nil
    }

    private func reload() async {
        entries = await PainJournal.load()
        isLoading = false
    }
}
