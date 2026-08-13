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
    @State private var selectedMonthDate: Date?
    @State private var yearChartZoomLevel = 1.0

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
                                           onDelete: { _ in })
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.symbol)
                            .font(.headline)
                            .foregroundStyle(HealthCategory.workouts.tint)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string(row.sport)).font(.subheadline.bold())
                            Text(L10n.format("%lld Trainings · %@", Int64(row.count), durationText(row.duration)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.distanceKm > 0 {
                            Text(WorkoutUnits.distance(km: row.distanceKm))
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
            // Bewusst feste Zeilen statt LazyVGrid: ein Lazy-Container in einer
            // Listenzeile laesst UIKit die Zellenhoehe immer wieder neu messen —
            // die Liste geriet dadurch beim Oeffnen in eine Layout-Schleife und
            // die App brach ab.
            HStack(spacing: 4) {
                ForEach(weekdayHeaders, id: \.self) { title in
                    Text(L10n.string(title))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(monthGridWeeks().enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        monthDayCell(day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func monthDayCell(_ day: Date?) -> some View {
        if let day {
            let hasWorkout = !workouts(on: day).isEmpty
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hasWorkout ? HealthCategory.workouts.tint : Color.secondary.opacity(0.14))
                .frame(maxWidth: .infinity)
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
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 22)
        }
    }

    /// Der Monat in Wochenzeilen — die letzte Woche wird auf sieben Felder
    /// aufgefuellt, damit alle Zeilen gleich breit rastern.
    private func monthGridWeeks() -> [[Date?]] {
        var days = monthGridDays()
        let remainder = days.count % 7
        if remainder != 0 {
            days.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }
        return stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
    }

    private var yearOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.format("%lld Trainings im Jahr", Int64(items.count)))
                .font(.headline)
            Chart {
                ForEach(monthCounts) { item in
                    LineMark(x: .value("Monat", item.month),
                             y: .value("Trainings", item.count))
                        .foregroundStyle(HealthCategory.workouts.tint)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Monat", item.month),
                              y: .value("Trainings", item.count))
                        .foregroundStyle(HealthCategory.workouts.tint)

                    if item.id == selectedMonth?.id {
                        PointMark(x: .value("Ausgewählt", item.month),
                                  y: .value("Trainings", item.count))
                            .foregroundStyle(HealthCategory.workouts.tint)
                            .symbolSize(75)
                    }
                }

                if let selectedMonth {
                    RuleMark(x: .value("Ausgewählt", selectedMonth.month))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .frame(height: 150)
            .chartXScale(domain: yearChartDomain)
            .chartXVisibleDomain(length: yearChartVisibleDuration)
            .chartScrollableAxes(.horizontal)
            .chartTapSelection(value: $selectedMonthDate)
            .chartPinchZoom($yearChartZoomLevel, maximumZoom: 4)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(compactChartAxisNumber(number))
                                .font(.caption2)
                        } else if let number = value.as(Int.self) {
                            Text(number.formatted())
                                .font(.caption2)
                        }
                    }
                }
            }
            .modernChartSurface(tint: HealthCategory.workouts.tint)

            if let selectedMonth {
                ChartSelectedValue(
                    title: selectedMonth.month.formatted(.dateTime.month(.wide).year()),
                    values: [(HealthCategory.workouts.tint, "\(selectedMonth.count) Trainings")]
                )
            }

            ChartGestureHint()
        }
    }

    private var selectedMonth: WorkoutMonthCount? {
        guard let selectedMonthDate else { return nil }
        return monthCounts.min {
            abs($0.month.timeIntervalSince(selectedMonthDate))
                < abs($1.month.timeIntervalSince(selectedMonthDate))
        }
    }

    private var yearChartDomain: ClosedRange<Date> {
        let dates = monthCounts.map(\.month)
        let start = dates.min() ?? referenceDate
        let last = dates.max() ?? start
        let end = calendar.date(byAdding: .month, value: 1, to: last) ?? last.addingTimeInterval(31 * 86_400)
        return start...end
    }

    private var yearChartVisibleDuration: TimeInterval {
        max(62 * 86_400, yearChartDomain.upperBound.timeIntervalSince(yearChartDomain.lowerBound) / yearChartZoomLevel)
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
    let month: Date
    let count: Int

    var id: Date { month }
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
    let onDelete: (UnifiedWorkout) -> Void

    @State private var range: WorkoutSportRange = .all
    @State private var referenceDate = Date()
    @State private var selectedChartDate: Date?
    @State private var chartZoomLevel = 1.0

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
        let points = chartPoints
        let highlightedPoint = selectedChartPoint(in: points)
        let chartDomain = sportChartDomain(for: points)
        let showsPointSymbols = points.count <= 60
        return List {
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
                if points.isEmpty {
                    ContentUnavailableView("Keine Daten",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Für diese Sportart liegen noch keine Werte vor."))
                } else {
                    Chart {
                        ForEach(points) { point in
                            LineMark(x: .value("Tag", point.day),
                                     y: .value(isStrength ? "Volumen" : "Minuten", point.primaryValue))
                                .foregroundStyle(HealthCategory.workouts.tint)
                                .interpolationMethod(showsPointSymbols ? .catmullRom : .linear)
                            if showsPointSymbols {
                                PointMark(x: .value("Tag", point.day),
                                          y: .value(isStrength ? "Volumen" : "Minuten", point.primaryValue))
                                    .foregroundStyle(HealthCategory.workouts.tint)
                            }

                            if point.id == highlightedPoint?.id {
                                PointMark(x: .value("Ausgewählt", point.day),
                                          y: .value(isStrength ? "Volumen" : "Minuten", point.primaryValue))
                                    .foregroundStyle(HealthCategory.workouts.tint)
                                    .symbolSize(80)
                            }
                        }

                        if let highlightedPoint {
                            RuleMark(x: .value("Ausgewählt", highlightedPoint.day))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .frame(height: 220)
                    .chartYAxisLabel(isStrength ? "Volumen (kg)" : "Dauer (Min)")
                    .chartXScale(domain: chartDomain)
                    .chartXVisibleDomain(length: sportChartVisibleDuration(for: chartDomain))
                    .chartScrollableAxes(.horizontal)
                    .chartTapSelection(value: $selectedChartDate)
                    .chartPinchZoom($chartZoomLevel)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.day().month(), centered: false)
                                .font(.caption2)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text(compactChartAxisNumber(number))
                                        .font(.caption2)
                                } else if let number = value.as(Int.self) {
                                    Text(number.formatted())
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .modernChartSurface(tint: HealthCategory.workouts.tint)

                    if let selectedChartPoint = highlightedPoint {
                        ChartSelectedValue(
                            title: selectedChartPoint.day.formatted(.dateTime.weekday(.abbreviated).day().month().year()),
                            values: [(HealthCategory.workouts.tint, selectedChartPoint.label)]
                        )
                    }

                    ChartGestureHint()
                }

                HStack(spacing: 12) {
                    stat("Trainings", "\(visibleItems.count)")
                    stat("Dauer", durationText(totalDuration))
                    if isStrength {
                        stat("Volumen", formatKg(totalVolumeKg))
                    } else {
                        stat("Distanz", totalDistanceKm > 0 ? WorkoutUnits.distance(km: totalDistanceKm) : "-")
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
                                Text(L10n.format("%lld Trainings · %lld Sätze · %@", Int64(row.workoutCount), Int64(row.setCount), formatKg(row.volumeKg)))
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

    private func selectedChartPoint(in points: [WorkoutSportChartPoint]) -> WorkoutSportChartPoint? {
        guard let selectedChartDate else { return nil }
        return points.min {
            abs($0.day.timeIntervalSince(selectedChartDate))
                < abs($1.day.timeIntervalSince(selectedChartDate))
        }
    }

    private func sportChartDomain(for points: [WorkoutSportChartPoint]) -> ClosedRange<Date> {
        let start = points.map(\.day).min() ?? referenceDate
        let last = points.map(\.day).max() ?? start
        let end = Calendar.healthApp.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        return start...end
    }

    private func sportChartVisibleDuration(for domain: ClosedRange<Date>) -> TimeInterval {
        let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return min(total, max(86_400, total / chartZoomLevel))
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
