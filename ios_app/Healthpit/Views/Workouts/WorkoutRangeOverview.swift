//
//  WorkoutRangeOverview.swift
//  Healthpit
//
//  Kleine Zeitraum-Uebersicht ueber Trainingshaeufigkeit.
//

import Charts
import SwiftUI

struct WorkoutRangeOverview: View {
    let range: TimeRange
    @Binding var referenceDate: Date
    let items: [UnifiedWorkout]
    let sportItems: [UnifiedWorkout]
    private let calendar = Calendar.healthApp

    var body: some View {
        Section("Übersicht") {
            rangeHeader
            switch range {
            case .day:
                dayOverview
            case .week:
                weekOverview
            case .month:
                monthOverview
            case .year:
                yearOverview
            }
        }
    }

    @ViewBuilder
    private var sportOverview: some View {
        if !sportStats.isEmpty {
            Text("Sportarten")
                .font(.subheadline.bold())
            ForEach(sportStats) { row in
                NavigationLink {
                    WorkoutSportDetailView(sport: row.sport,
                                           items: itemsForSport(row.sport),
                                           hevySummary: nil,
                                           onDelete: { _ in })
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.symbol)
                            .font(.headline)
                            .foregroundStyle(HealthCategory.workouts.tint)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string(row.sport)).font(.subheadline.bold())
                            Text("\(row.count) Trainings · \(durationText(row.duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.distanceKm > 0 {
                            Text(String(format: "%.1f km", row.distanceKm))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var rangeHeader: some View {
        HStack(spacing: 8) {
            Button {
                referenceDate = shiftedReference(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)

            VStack(spacing: 4) {
                Text(rangeTitle)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                DatePicker("Datum", selection: $referenceDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)

            Button {
                referenceDate = shiftedReference(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(nextReferenceIsFuture)
        }
    }

    private var dayOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(items.count) Training\(items.count == 1 ? "" : "s") heute")
                .font(.headline)
            ForEach(items.prefix(4)) { item in
                HStack {
                    Label(item.title, systemImage: item.symbol)
                    Spacer()
                    Text(durationText(item.duration))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private var weekOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                stat("Trainings", "\(items.count)")
                stat("Tage aktiv", "\(activeDays.count)")
                stat("Dauer", durationText(items.map(\.duration).reduce(0, +)))
            }
            let days = weekDays()
            HStack(spacing: 7) {
                ForEach(days, id: \.self) { day in
                    let dayWorkouts = workouts(on: day)
                    let hasWorkout = !dayWorkouts.isEmpty
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(hasWorkout ? HealthCategory.workouts.tint : Color.secondary.opacity(0.16))
                            .frame(height: 24)
                            .overlay {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(hasWorkout ? Color.white : Color.secondary)
                            }
                            .overlay {
                                if calendar.isDateInToday(day) {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color.orange, lineWidth: 2)
                                }
                            }
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var monthOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(activeDays.count) Trainingstage im Monat")
                .font(.subheadline.bold())
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdayHeaders, id: \.self) { title in
                    Text(L10n.string(title))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(monthGridDays().enumerated()), id: \.offset) { _, day in
                    if let day {
                        let dayWorkouts = workouts(on: day)
                        let hasWorkout = !dayWorkouts.isEmpty
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(hasWorkout ? HealthCategory.workouts.tint : Color.secondary.opacity(0.14))
                            .frame(height: 22)
                            .overlay {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(hasWorkout ? Color.white : Color.secondary)
                            }
                            .overlay {
                                if calendar.isDateInToday(day) {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color.orange, lineWidth: 2)
                                }
                            }
                            .accessibilityLabel(day.formatted(.dateTime.day().month()))
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
    }

    private var yearOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(items.count) Trainings im Jahr")
                .font(.headline)
            Chart(monthCounts) { item in
                LineMark(x: .value("Monat", item.month),
                         y: .value("Trainings", item.count))
                    .foregroundStyle(HealthCategory.workouts.tint)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Monat", item.month),
                          y: .value("Trainings", item.count))
                    .foregroundStyle(HealthCategory.workouts.tint)
            }
            .frame(height: 150)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline)
            Text(L10n.string(title)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeDays: Set<Date> {
        Set(items.map { calendar.startOfDay(for: $0.startDate) })
    }

    private var sportStats: [WorkoutSportStat] {
        Dictionary(grouping: sportItems, by: \.sportName)
            .map { sport, values in
                WorkoutSportStat(sport: sport,
                                 symbol: values.first?.symbol ?? "figure.run",
                                 count: values.count,
                                 duration: values.map(\.duration).reduce(0, +),
                                 distanceKm: values.compactMap(\.distanceKm).reduce(0, +))
            }
            .sorted {
                if $0.count == $1.count { return $0.duration > $1.duration }
                return $0.count > $1.count
            }
    }

    private func workouts(on day: Date) -> [UnifiedWorkout] {
        items.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
    }

    private func itemsForSport(_ sport: String) -> [UnifiedWorkout] {
        sportItems.filter { $0.sportName == sport }
    }

    private func weekDays() -> [Date] {
        let interval = TimeRange.week.dateInterval(referenceDate: referenceDate, calendar: calendar)
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    private var weekdayHeaders: [String] {
        ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    }

    private func monthGridDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: referenceDate),
              let daysRange = calendar.range(of: .day, in: .month, for: interval.start) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        let monthDays = daysRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leadingEmptyDays) + monthDays
    }

    private var monthCounts: [WorkoutMonthCount] {
        let year = calendar.component(.year, from: referenceDate)
        let january = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? referenceDate
        return (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: january) else {
                return nil
            }
            let count = items.filter { calendar.isDate($0.startDate, equalTo: month, toGranularity: .month) }.count
            return WorkoutMonthCount(month: month, count: count)
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        formatWorkoutDuration(seconds)
    }

    private var rangeTitle: String {
        let interval = range.dateInterval(referenceDate: referenceDate)
        switch range {
        case .day:
            return interval.start.formatted(.dateTime.weekday(.abbreviated).day().month().year())
        case .week:
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(.dateTime.day().month())) - \(end.formatted(.dateTime.day().month().year()))"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return interval.start.formatted(.dateTime.year())
        }
    }

    private func shiftedReference(by value: Int) -> Date {
        let component: Calendar.Component
        switch range {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return calendar.date(byAdding: component, value: value, to: referenceDate) ?? referenceDate
    }

    private var nextReferenceIsFuture: Bool {
        range.dateInterval(referenceDate: shiftedReference(by: 1)).start > Date()
    }
}

private struct WorkoutMonthCount: Identifiable {
    let id = UUID()
    let month: Date
    let count: Int
}

private struct WorkoutSportStat: Identifiable {
    var id: String { sport }
    let sport: String
    let symbol: String
    let count: Int
    let duration: TimeInterval
    let distanceKm: Double
}

struct WorkoutSportListView: View {
    let items: [UnifiedWorkout]
    let hevySummary: HevyFitnessSummary?
    let onDelete: (UnifiedWorkout) -> Void

    private var sports: [String] {
        Set(items.map(\.sportName)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if sports.isEmpty {
                ContentUnavailableView("Keine Sportarten",
                                       systemImage: "figure.run",
                                       description: Text("Es sind noch keine Workouts vorhanden."))
            } else {
                ForEach(sports, id: \.self) { sport in
                    NavigationLink(sport) {
                        WorkoutSportDetailView(sport: sport,
                                               items: items.filter { $0.sportName == sport },
                                               hevySummary: hevySummary,
                                               onDelete: onDelete)
                    }
                }
            }
        }
        .navigationTitle("Sportarten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum WorkoutSportRange: String, CaseIterable, Identifiable {
    case all
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.string("Alles")
        case .day: L10n.string("Tag")
        case .week: L10n.string("Woche")
        case .month: L10n.string("Monat")
        case .year: L10n.string("Jahr")
        }
    }

    var timeRange: TimeRange? {
        switch self {
        case .all: nil
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }
}

struct WorkoutSportDetailView: View {
    let sport: String
    let items: [UnifiedWorkout]
    let hevySummary: HevyFitnessSummary?
    let onDelete: (UnifiedWorkout) -> Void

    @State private var range: WorkoutSportRange = .all
    @State private var referenceDate = Date()

    private var visibleItems: [UnifiedWorkout] {
        guard let timeRange = range.timeRange else { return items }
        let interval = timeRange.dateInterval(referenceDate: referenceDate, calendar: .healthApp)
        return items.filter { interval.contains($0.startDate) }
    }

    private var isStrength: Bool {
        normalizeStrengthSport(sport) == "Krafttraining"
    }

    private var strengthRows: [StrengthExerciseAggregate] {
        StrengthExerciseAnalyzer.rows(from: visibleItems)
    }

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $range) {
                    ForEach(WorkoutSportRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if range != .all {
                    HStack {
                        Button {
                            shiftReference(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)

                        DatePicker("Datum",
                                   selection: $referenceDate,
                                   in: ...Date(),
                                   displayedComponents: .date)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)

                        Button {
                            shiftReference(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(nextReferenceIsFuture)
                    }
                }
            }

            Section {
                if chartPoints.isEmpty {
                    ContentUnavailableView("Keine Daten",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Für diese Sportart liegen noch keine Werte vor."))
                } else {
                    Chart(chartPoints) { point in
                        LineMark(x: .value("Tag", point.day),
                                 y: .value(isStrength ? "Volumen" : "Minuten", point.primaryValue))
                            .foregroundStyle(HealthCategory.workouts.tint)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Tag", point.day),
                                  y: .value(isStrength ? "Volumen" : "Minuten", point.primaryValue))
                            .foregroundStyle(HealthCategory.workouts.tint)
                    }
                    .frame(height: 220)
                    .chartYAxisLabel(isStrength ? "Volumen (kg)" : "Dauer (Min)")
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.day().month(), centered: false)
                                .font(.caption2)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel()
                                .font(.caption2)
                        }
                    }
                }

                HStack(spacing: 12) {
                    stat("Trainings", "\(visibleItems.count)")
                    stat("Dauer", durationText(totalDuration))
                    if isStrength {
                        stat("Volumen", formatKg(totalVolumeKg))
                    } else {
                        stat("Distanz", totalDistanceKm > 0 ? String(format: "%.1f km", totalDistanceKm) : "-")
                    }
                }
            }

            if isStrength, !strengthRows.isEmpty {
                Section("Maschinen & Übungen") {
                    ForEach(strengthRows) { row in
                        NavigationLink {
                            StrengthExerciseDetailView(exercise: row)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.name)
                                    .font(.headline)
                                Text("\(row.workoutCount) Trainings · \(row.setCount) Sätze · \(formatKg(row.volumeKg))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Section("Trainings") {
                ForEach(visibleItems) { item in
                    NavigationLink {
                        UnifiedWorkoutDetailView(item: item,
                                                 hevySummary: hevySummary,
                                                 records: [])
                    } label: {
                        UnifiedWorkoutRow(item: item, records: [])
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            onDelete(item)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(sport)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chartPoints: [WorkoutSportChartPoint] {
        let calendar = Calendar.healthApp
        let grouped = Dictionary(grouping: visibleItems, by: { calendar.startOfDay(for: $0.startDate) })
        return grouped.map { day, values in
            let durationMinutes = values.map(\.duration).reduce(0, +) / 60
            let volume = values.compactMap(\.volumeKg).reduce(0, +)
            let primary = isStrength ? volume : durationMinutes
            let label = isStrength ? formatKg(volume) : "\(Int(durationMinutes.rounded())) Min"
            return WorkoutSportChartPoint(day: day,
                                          primaryValue: primary,
                                          label: label)
        }
        .filter { $0.primaryValue > 0 }
        .sorted { $0.day < $1.day }
    }

    private var totalDuration: TimeInterval {
        visibleItems.map(\.duration).reduce(0, +)
    }

    private var totalDistanceKm: Double {
        visibleItems.compactMap(\.distanceKm).reduce(0, +)
    }

    private var totalVolumeKg: Double {
        visibleItems.compactMap(\.volumeKg).reduce(0, +)
    }

    private func shiftReference(by value: Int) {
        guard let timeRange = range.timeRange else { return }
        let component: Calendar.Component
        switch timeRange {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        referenceDate = Calendar.healthApp.date(byAdding: component,
                                                value: value,
                                                to: referenceDate) ?? referenceDate
    }

    private var nextReferenceIsFuture: Bool {
        guard let timeRange = range.timeRange else { return true }
        let component: Calendar.Component
        switch timeRange {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        let next = Calendar.healthApp.date(byAdding: component,
                                           value: 1,
                                           to: referenceDate) ?? referenceDate
        return timeRange.dateInterval(referenceDate: next, calendar: .healthApp).start > Date()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(L10n.string(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        formatWorkoutDuration(seconds)
    }
}

private struct WorkoutSportChartPoint: Identifiable {
    let day: Date
    let primaryValue: Double
    let label: String

    var id: Date { day }
}
