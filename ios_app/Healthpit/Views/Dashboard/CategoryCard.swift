//
//  CategoryCard.swift
//  Healthpit
//
//  Einzelne Dashboard-Kachel. Lädt für ihre Kategorie 1–2 Kennzahlen live aus
//  HealthKit. CardContainer kapselt den gemeinsamen Karten-Look (PLAN 7).
//

import SwiftUI

// MARK: - Kleine Dashboard-Bausteine

private struct DashboardCardHeader: View {
    let title: String
    let systemImage: String
    let tint: Color
    let size: DashboardWidgetSize

    var body: some View {
        if size == .small {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.bold())
                Text(L10n.string(title))
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label(L10n.string(title), systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct DashboardMetricColumn: View {
    let value: String
    let label: String
    var valueFont: Font = .caption.bold()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(valueFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(L10n.string(label))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Gemeinsamer Karten-Look

struct CardContainer<Content: View>: View {
    let tint: Color
    let size: DashboardWidgetSize
    let content: Content

    init(tint: Color, size: DashboardWidgetSize = .medium, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.size = size
        self.content = content()
    }

    var body: some View {
        content
            .padding(size == .small ? 11 : 14)
            .frame(maxWidth: .infinity,
                   minHeight: size.minHeight,
                   maxHeight: size.minHeight,
                   alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.18),
                                Color(.secondarySystemBackground),
                                Color(.systemBackground),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(tint.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.11), radius: 12, y: 6)
            .clipped()
    }
}

// MARK: - Kategorie-Kachel

struct CategoryCard: View {
    let category: HealthCategory
    var size: DashboardWidgetSize = .medium

    @State private var values: [String: DashboardMetricCacheEntry] = [:]
    @State private var loaded = false

    private var headlineMetrics: [HealthMetric] {
        HealthMetric.headline(for: category)
    }

    private func value(for metric: HealthMetric) -> Double? {
        values[metric.id]?.value
    }

    /// Messdatum, aber nur wenn der Wert „alt" ist (älter als 2 Tage) – sonst nil.
    private func staleDate(for metric: HealthMetric) -> Date? {
        guard let measured = values[metric.id]?.measuredAt else { return nil }
        let cutoff = Calendar.healthApp.date(byAdding: .day, value: -2, to: .now) ?? .now
        return measured < cutoff ? measured : nil
    }

    /// Was je Größe angezeigt wird: 1x1 eine, 2x2 zwei, 4x2 bis zu vier
    /// (nach dem Laden bevorzugt die mit echten Werten).
    private var visibleMetrics: [HealthMetric] {
        switch size {
        case .small:
            return Array(headlineMetrics.prefix(1))
        case .medium:
            return Array(headlineMetrics.prefix(2))
        case .wide:
            guard loaded else { return Array(headlineMetrics.prefix(4)) }
            let withValues = headlineMetrics.filter { value(for: $0) != nil }
            return Array((withValues.isEmpty ? headlineMetrics : withValues).prefix(4))
        }
    }

    var body: some View {
        CardContainer(tint: category.tint, size: size) {
            VStack(alignment: .leading, spacing: size.isCompact ? 8 : 12) {
                DashboardCardHeader(title: category.title,
                                    systemImage: category.systemImage,
                                    tint: category.tint,
                                    size: size)

                if size == .wide {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(visibleMetrics) { metric in
                            wideMetricColumn(for: metric)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(visibleMetrics) { metric in
                        valueRow(for: metric)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .task { await load() }
    }

    /// Kompakte Spalte für 4x2: Zahl prominent, Bezeichnung + Einheit darunter.
    private func wideMetricColumn(for metric: HealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let value = value(for: metric) {
                Text(metric.formattedValue(value))
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Text(loaded ? "–" : "…")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
            Text(wideLabel(for: metric))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            staleDateLabel(for: metric)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Winziges Messdatum, nur wenn der Wert alt ist.
    @ViewBuilder
    private func staleDateLabel(for metric: HealthMetric) -> some View {
        if let date = staleDate(for: metric) {
            Text(date, format: .dateTime.day().month().year(.twoDigits))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Bezeichnung + Einheit, ohne Dopplung wenn beide gleich sind (z. B. "Schritte").
    private func wideLabel(for metric: HealthMetric) -> String {
        let unit = metric.displaySymbol
        if unit.isEmpty || unit == metric.title { return metric.title }
        return "\(metric.title) (\(unit))"
    }

    @ViewBuilder
    private func valueRow(for metric: HealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let value = value(for: metric) {
                Text(metric.formattedValueWithUnit(value))
                    .font(size == .small ? .callout.bold() : .title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(size == .small ? 2 : 1)
                    .minimumScaleFactor(size == .small ? 0.8 : 0.65)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(loaded ? "–" : "…")
                    .font(size == .small ? .callout.bold() : .title3.bold())
                    .foregroundStyle(.secondary)
            }
            if size != .small {
                HStack(spacing: 5) {
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let date = staleDate(for: metric) {
                        Text(date, format: .dateTime.day().month().year(.twoDigits))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func load() async {
        values = await HealthQuery.shared.headlineValues(for: headlineMetrics)
        loaded = true
    }
}

// MARK: - Workout-Kachel

struct WorkoutCard: View {
    var size: DashboardWidgetSize = .medium

    @State private var latestWorkout: WorkoutSummary?
    @State private var lastSevenDays: [WorkoutSummary] = []
    @State private var loaded = false

    var body: some View {
        CardContainer(tint: HealthCategory.workouts.tint, size: size) {
            VStack(alignment: .leading, spacing: size.isCompact ? 8 : 12) {
                DashboardCardHeader(title: HealthCategory.workouts.title,
                                    systemImage: HealthCategory.workouts.systemImage,
                                    tint: HealthCategory.workouts.tint,
                                    size: size)

                if let latestWorkout {
                    switch size {
                    case .small:
                        compactWorkoutBlock(latestWorkout)
                    case .medium:
                        latestWorkoutBlock(latestWorkout, prominent: true)
                    case .wide:
                        HStack(alignment: .top, spacing: 14) {
                            latestWorkoutBlock(latestWorkout, prominent: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            weekWorkoutBlock
                                .frame(width: 132, alignment: .leading)
                        }
                    }
                } else {
                    emptyWorkoutBlock
                }

                Spacer(minLength: 0)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let all = await HealthQuery.shared.workouts()
        let calendar = Calendar.healthApp
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
        lastSevenDays = all.filter { $0.start >= start }
        latestWorkout = all.first
        loaded = true
    }

    private var emptyWorkoutBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(loaded ? "–" : "…")
                .font(size == .small ? .callout.bold() : .title3.bold())
            Text(L10n.string("letztes Workout"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func compactWorkoutBlock(_ workout: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.activityName)
                .font(.callout.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(workout.duration.hoursMinutes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func latestWorkoutBlock(_ workout: WorkoutSummary, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.string("Zuletzt"))
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Label(workout.activityName, systemImage: workout.symbol)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(workout.start, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 12) {
                DashboardMetricColumn(value: workout.duration.hoursMinutes,
                                      label: "Dauer",
                                      valueFont: prominent ? .title3.bold() : .callout.bold())
                if let distance = workout.distanceKm, distance > 0 {
                    DashboardMetricColumn(value: WorkoutUnits.distance(km: distance, fractionDigits: 2),
                                          label: "Distanz")
                } else if let kcal = workout.energyKcal, kcal > 0 {
                    DashboardMetricColumn(value: "\(Int(kcal.rounded())) kcal",
                                          label: "Energie")
                }
            }
        }
    }

    private var weekWorkoutBlock: some View {
        let totalDuration = lastSevenDays.reduce(0) { $0 + $1.duration }
        let avgPerDay = totalDuration / 7

        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("Letzte 7 Tage"))
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 10) {
                DashboardMetricColumn(value: lastSevenDays.isEmpty ? "–" : "\(lastSevenDays.count)",
                                      label: "Workouts")
                DashboardMetricColumn(value: avgPerDay > 0 ? avgPerDay.hoursMinutes : "–",
                                      label: "Ø/Tag")
            }
            weekBars
        }
    }

    private var weekBars: some View {
        let bars = workoutWeekBars()
        let maxValue = max(bars.map(\.minutes).max() ?? 0, 1)

        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(bars) { bar in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(bar.minutes > 0 ? HealthCategory.workouts.tint : Color.secondary.opacity(0.18))
                        .frame(width: 10,
                               height: max(4, CGFloat(bar.minutes) / CGFloat(maxValue) * 24))
                    Text(bar.label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 38, alignment: .bottom)
    }

    private func workoutWeekBars() -> [WorkoutWeekBar] {
        let calendar = Calendar.healthApp
        let today = calendar.startOfDay(for: .now)
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: today) else { return nil }
            let minutes = lastSevenDays
                .filter { calendar.isDate($0.start, inSameDayAs: day) }
                .reduce(0) { $0 + Int(($1.duration / 60).rounded()) }
            return WorkoutWeekBar(id: offset,
                                  label: formatter.string(from: day).uppercased(),
                                  minutes: minutes)
        }
    }
}

private struct WorkoutWeekBar: Identifiable {
    let id: Int
    let label: String
    let minutes: Int
}

// MARK: - Schlaf-Kachel

struct SleepCard: View {
    var size: DashboardWidgetSize = .medium

    @State private var lastNight: SleepSession?
    @State private var loaded = false

    var body: some View {
        CardContainer(tint: HealthCategory.sleep.tint, size: size) {
            VStack(alignment: .leading, spacing: size.isCompact ? 8 : 12) {
                DashboardCardHeader(title: HealthCategory.sleep.title,
                                    systemImage: HealthCategory.sleep.systemImage,
                                    tint: HealthCategory.sleep.tint,
                                    size: size)

                if let lastNight {
                    switch size {
                    case .small:
                        sleepMainBlock(lastNight, showLabel: false)
                    case .medium:
                        sleepMainBlock(lastNight, showLabel: true)
                        Text("Im Bett: \(lastNight.timeInBed.hoursMinutes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .wide:
                        HStack(alignment: .top, spacing: 14) {
                            sleepMainBlock(lastNight, showLabel: true)
                            VStack(alignment: .leading, spacing: 6) {
                                DashboardMetricColumn(value: "\(Int((lastNight.efficiency * 100).rounded())) %",
                                                      label: "Effizienz")
                                sleepStageBar(lastNight)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text(loaded ? "–" : "…")
                        .font(size == .small ? .callout.bold() : .title3.bold())
                }

                Spacer(minLength: 0)
            }
        }
        .task { await load() }
    }

    private func load() async {
        // Die Nacht kommt aus der Datenbank. Vorher stand hier ein
        // Zwischenspeicher, der für vergangene Tage nie wieder geschrieben
        // wurde – ein einmal falsch abgelegter Wert blieb dort für immer.
        lastNight = await HealthQuery.shared.nights(in: TimeRange.day.dateInterval()).first
        loaded = true
    }

    private func sleepMainBlock(_ session: SleepSession, showLabel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.asleep.hoursMinutes)
                .font(size == .small ? .callout.bold() : .title3.bold())
                .lineLimit(size == .small ? 2 : 1)
                .minimumScaleFactor(size == .small ? 0.8 : 0.65)
                .fixedSize(horizontal: false, vertical: true)
            if showLabel {
                Text(L10n.string("letzte Nacht"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sleepStageBar(_ session: SleepSession, height: CGFloat = 8) -> some View {
        let total = max(session.asleep + session.awake, 1)
        return GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 2) {
                sleepStageSegment(value: session.deep, total: total, width: width, color: .indigo)
                sleepStageSegment(value: session.core, total: total, width: width, color: .blue)
                sleepStageSegment(value: session.rem, total: total, width: width, color: .purple)
                sleepStageSegment(value: session.awake, total: total, width: width, color: .orange)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }

    private func sleepStageSegment(value: TimeInterval, total: TimeInterval,
                                   width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color.opacity(value > 0 ? 0.85 : 0.18))
            .frame(width: max(3, CGFloat(value / total) * width))
    }
}

// MARK: - Rekorde-Kachel

struct RecordsCard: View {
    var size: DashboardWidgetSize = .medium

    @State private var records: [WorkoutRecord] = []
    @State private var title = "…"
    @State private var detail = "lade Rekorde"

    var body: some View {
        CardContainer(tint: .orange, size: size) {
            VStack(alignment: .leading, spacing: size.isCompact ? 8 : 12) {
                DashboardCardHeader(title: "Rekorde",
                                    systemImage: "trophy.fill",
                                    tint: .orange,
                                    size: size)

                switch size {
                case .small:
                    recordValueBlock(value: title, detail: nil)
                case .medium:
                    recordValueBlock(value: title, detail: detail)
                case .wide:
                    HStack(alignment: .top, spacing: 14) {
                        recordValueBlock(value: title, detail: detail)
                        if records.count > 1 {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.string("Auch stark"))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                recordPreview(records[1])
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .task { await load() }
    }

    private func load() async {
        records = WorkoutRecordAnalyzer.records(for: await HealthQuery.shared.unifiedWorkouts())
        if let record = records.first {
            title = record.localizedValue
            detail = L10n.format("%@: %@", record.localizedSport, record.localizedTitle)
            return
        }
        title = L10n.string("Noch keine")
        detail = L10n.string("Trainingsdaten fehlen")
    }

    private func recordValueBlock(value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(size == .small ? .callout.bold() : .title3.bold())
                .lineLimit(size == .small ? 2 : 1)
                .minimumScaleFactor(size == .small ? 0.8 : 0.75)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(L10n.string(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(size == .wide ? 1 : 2)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private func recordPreview(_ record: WorkoutRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(record.localizedValue, systemImage: record.symbol)
                .font(.caption.bold())
                .foregroundStyle(record.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(L10n.format("%@: %@", record.localizedSport, record.localizedTitle))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - Zyklus-Kachel

struct CycleCard: View {
    var size: DashboardWidgetSize = .medium

    @State private var overview = CycleOverview()
    @State private var loaded = false

    var body: some View {
        CardContainer(tint: HealthCategory.cycle.tint, size: size) {
            VStack(alignment: .leading, spacing: size.isCompact ? 8 : 12) {
                DashboardCardHeader(title: HealthCategory.cycle.title,
                                    systemImage: HealthCategory.cycle.systemImage,
                                    tint: HealthCategory.cycle.tint,
                                    size: size)

                if overview.hasData {
                    switch size {
                    case .small:
                        mainBlock(showLabel: false)
                    case .medium:
                        mainBlock(showLabel: true)
                        secondaryLine
                    case .wide:
                        HStack(alignment: .top, spacing: 14) {
                            mainBlock(showLabel: true)
                            VStack(alignment: .leading, spacing: 6) {
                                if let average = overview.averageCycleLength {
                                    DashboardMetricColumn(value: L10n.format("%lld Tage", average),
                                                          label: "Ø Zyklus")
                                }
                                if let period = overview.averagePeriodLength {
                                    DashboardMetricColumn(value: L10n.format("%lld Tage", period),
                                                          label: "Ø Periode")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text(loaded ? "–" : "…")
                        .font(size == .small ? .callout.bold() : .title3.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .task { await load() }
    }

    private func mainBlock(showLabel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(mainValue)
                .font(size == .small ? .callout.bold() : .title3.bold())
                .lineLimit(size == .small ? 2 : 1)
                .minimumScaleFactor(size == .small ? 0.8 : 0.65)
                .fixedSize(horizontal: false, vertical: true)
            if showLabel {
                Text(L10n.string("aktueller Zyklustag"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if let start = overview.currentCycle?.start {
            Text(L10n.string("Letzte Periode:") + " " + start.formatted(.dateTime.day().month()))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var mainValue: String {
        guard let day = overview.currentCycleDay else { return "–" }
        return L10n.format("Tag %lld", day)
    }

    private func load() async {
        overview = await HealthQuery.shared.cycleOverview()
        loaded = true
    }
}
