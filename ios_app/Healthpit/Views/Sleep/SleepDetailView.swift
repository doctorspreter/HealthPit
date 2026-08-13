//
//  SleepDetailView.swift
//  Healthpit
//
//  Screen 5 – Schlaf, übersichtlich:
//   • Kennzahlen der letzten Nacht (Schlaf, Bett, Effizienz)
//   • Hypnogramm der letzten Nacht (Phasen über die Zeit)
//   • gestapeltes Balkendiagramm der Phasen pro Nacht über den Zeitraum
//   • Durchschnittswerte
//

import SwiftUI
import Charts

extension SleepStage {
    var color: Color {
        switch self {
        case .deep:  return .indigo
        case .core:  return .blue
        case .rem:   return .cyan
        case .awake: return .orange
        }
    }
}

struct SleepDetailView: View {
    private let health = HealthKitManager.shared

    @State private var range: TimeRange = .day
    @State private var referenceDate = Date()
    @State private var sessions: [SleepSession] = []
    @State private var isLoading = false
    @State private var selectedSleepTime: Date?
    @State private var hypnogramZoomLevel = 1.0
    @State private var selectedNightDate: Date?
    @State private var nightlyZoomLevel = 1.0

    /// Reihenfolge der Y-Achse im Hypnogramm (unten → oben).
    ///
    /// Reihenfolge und Farben werden aus `SleepStage` abgeleitet, nicht
    /// getrennt gepflegt. Feste deutsche Schlüssel hier führten in jeder
    /// anderen Sprache zum Absturz, weil Swift Charts einen Wert, den seine
    /// Skala nicht kennt, nicht zeichnen kann.
    private var stageOrder: [String] {
        [SleepStage.deep, .core, .rem, .awake].map(\.title)
    }
    private var styleScale: [(String, Color)] {
        [SleepStage.deep, .core, .rem, .awake].map { ($0.title, $0.color) }
    }
    private let metricColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sleepHero

                Picker("Zeitraum", selection: $range) {
                    ForEach([TimeRange.day, .week, .month, .year]) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(5)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                periodControls

                if isLoading && sessions.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else if sessions.isEmpty {
                    ProfessionalEmptyState(title: "Keine Schlafdaten",
                                           message: "Für diesen Zeitraum liegen keine Schlafdaten vor.",
                                           symbol: "bed.double.fill",
                                           tint: .indigo)
                } else {
                    if range == .day {
                        daySleepOverview
                    } else {
                        sleepHeadline
                        averageSummary
                        stageDistribution(averageSleep)
                        nightlyStacked
                        averages
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .professionalPageBackground(tint: .indigo)
        .navigationTitle("Schlaf")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadKey) { await load() }
    }

    private var sleepHero: some View {
        let overview = sessions.isEmpty ? nil : (range == .day ? sessions.first.map(self.overview(for:)) : averageSleep)
        return ProfessionalPageHero(
            eyebrow: range == .day ? "Letzte Nacht" : periodLabel,
            title: "Schlaf & Erholung",
            subtitle: "Phasen, Dauer und Qualität verständlich zusammengefasst.",
            symbol: "moon.stars.fill",
            tint: .indigo,
            value: overview?.asleep.hoursMinutes ?? "–",
            detail: overview.map { "\(Int(($0.efficiency * 100).rounded())) % Effizienz" }
        )
    }

    private var periodControls: some View {
        HStack(spacing: 10) {
            Button {
                referenceDate = shiftedReference(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            VStack(spacing: 4) {
                Text(periodLabel)
                    .font(.subheadline.bold())
                DatePicker("Datum", selection: $referenceDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .frame(maxWidth: .infinity)

            Button {
                referenceDate = shiftedReference(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(isNextPeriodInFuture)
        }
        .padding(12)
        .professionalCard(tint: .indigo, cornerRadius: 18)
    }

    // MARK: Apple-Health-nahe Zusammenfassung

    private var sleepHeadline: some View {
        let s = averageSleep
        return VStack(alignment: .leading, spacing: 10) {
            Text("Durchschnittlicher Schlaf")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(s.asleep.hoursMinutes)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(sessions.count == 1
                 ? L10n.string("1 Nacht im Zeitraum")
                 : L10n.format("%lld Nächte im Zeitraum", Int64(sessions.count)))
                .font(.caption)
                .foregroundStyle(.secondary)
            phaseBar(s)
                .frame(height: 16)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .professionalCard(tint: .indigo)
    }

    private var daySleepOverview: some View {
        Group {
            if let last = sessions.first {
                VStack(alignment: .leading, spacing: 18) {
                    Text(last.end, format: .dateTime.weekday(.wide).day().month())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    summaryCards(overview(for: last), showAveragePrefix: false)
                    stageDistribution(overview(for: last))
                    if !last.segments.isEmpty {
                        hypnogram(last)
                    }
                }
            } else {
                ContentUnavailableView("Keine Schlafdaten",
                                       systemImage: "bed.double",
                                       description: Text("Für die letzte Nacht liegen keine Schlafdaten vor."))
            }
        }
    }

    private func stageDistribution(_ s: SleepOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfessionalSectionHeader(title: "Schlafphasen",
                                      subtitle: "Verteilung der erfassten Nacht")
            phaseBar(s)
                .frame(height: 18)
            ForEach(stageSlices(s)) { slice in
                HStack(spacing: 10) {
                    Circle()
                        .fill(slice.stage.color)
                        .frame(width: 10, height: 10)
                    Text(slice.stage.title)
                        .font(.subheadline)
                    Spacer()
                    Text(slice.duration.hoursMinutes)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(16)
        .professionalCard(tint: .indigo)
    }

    private func phaseBar(_ s: SleepOverview) -> some View {
        let slices = stageSlices(s).filter { $0.duration > 0 }
        let total = max(slices.reduce(0) { $0 + $1.duration }, 1)
        return GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(slices) { slice in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(slice.stage.color)
                        .frame(width: max(proxy.size.width * (slice.duration / total), 4))
                }
            }
        }
    }

    // MARK: Zeitraum-Schnitt

    private var averageSummary: some View {
        let s = averageSleep
        return VStack(alignment: .leading, spacing: 8) {
            Text("Durchschnitt im gewählten Zeitraum")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            summaryCards(s, showAveragePrefix: true)
        }
    }

    private var averageSleep: SleepOverview {
        let count = Double(max(sessions.count, 1))
        return SleepOverview(
            asleep: sessions.reduce(0) { $0 + $1.asleep } / count,
            timeInBed: sessions.reduce(0) { $0 + $1.timeInBed } / count,
            deep: sessions.reduce(0) { $0 + $1.deep } / count,
            core: sessions.reduce(0) { $0 + $1.core } / count,
            rem: sessions.reduce(0) { $0 + $1.rem } / count,
            awake: sessions.reduce(0) { $0 + $1.awake } / count,
            efficiency: sessions.reduce(0) { $0 + $1.efficiency } / count
        )
    }

    private func lastNightSummary(_ s: SleepSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.end, format: .dateTime.weekday(.wide).day().month())
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                bigStat(s.asleep.hoursMinutes, "Schlaf", .indigo)
                bigStat(s.timeInBed.hoursMinutes, "Im Bett", .blue)
                bigStat("\(Int((s.efficiency * 100).rounded())) %", "Effizienz", .teal)
            }
        }
    }

    private func summaryCards(_ s: SleepOverview, showAveragePrefix: Bool) -> some View {
        let prefix = showAveragePrefix ? "Ø " : ""
        return LazyVGrid(columns: metricColumns, spacing: 12) {
            bigStat(s.asleep.hoursMinutes, "\(prefix)Schlafzeit", .indigo)
            bigStat(s.timeInBed.hoursMinutes, "\(prefix)Bettzeit", .blue)
            bigStat("\(Int((s.efficiency * 100).rounded())) %", "\(prefix)Effizienz", .teal)
            bigStat(s.awake.hoursMinutes, "\(prefix)Wachzeit", .orange)
        }
    }

    // MARK: Hypnogramm der letzten Nacht

    private func hypnogram(_ s: SleepSession) -> some View {
        let selectedSegment = selectedSleepSegment(in: s)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Letzte Nacht").font(.headline)
            Chart {
                ForEach(s.segments) { seg in
                    BarMark(
                        xStart: .value("Start", seg.start),
                        xEnd: .value("Ende", seg.end),
                        y: .value("Phase", seg.stage.title)
                    )
                    .foregroundStyle(seg.stage.color)
                    .cornerRadius(4)
                    .opacity(seg.id == selectedSegment?.id ? 1 : 0.82)
                }

                if let segment = selectedSegment {
                    RuleMark(x: .value("Ausgewählt", selectedSleepTime ?? segment.start))
                        .foregroundStyle(.primary.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: stageOrder)
            .chartXScale(domain: s.start...s.end)
            .chartXVisibleDomain(length: max(30 * 60, s.end.timeIntervalSince(s.start) / hypnogramZoomLevel))
            .chartScrollableAxes(.horizontal)
            .chartTapSelection(value: $selectedSleepTime)
            .chartPinchZoom($hypnogramZoomLevel, maximumZoom: 4)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                    AxisGridLine(); AxisTick()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 180)
            .modernChartSurface(tint: .indigo)

            if let segment = selectedSegment {
                ChartSelectedValue(
                    title: "\(segment.start.formatted(.dateTime.hour().minute()))–\(segment.end.formatted(.dateTime.hour().minute()))",
                    values: [(segment.stage.color, "\(segment.stage.title) · \(segment.duration.hoursMinutes)")]
                )
            }

            ChartGestureHint()

            // Legende mit Dauer je Phase
            ForEach(SleepStage.allCases) { stage in
                let dur = s.duration(of: stage)
                if dur > 0 {
                    HStack(spacing: 8) {
                        Circle().fill(stage.color).frame(width: 10, height: 10)
                        Text(stage.title)
                        Spacer()
                        Text(dur.hoursMinutes).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: Verlauf – Phasen pro Nacht (gestapelt)

    private var nightlyStacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phasen pro Nacht").font(.headline)
            Chart {
                ForEach(sessionsForCharts) { s in
                    ForEach(SleepStage.allCases.filter { $0 != .awake }) { stage in
                        BarMark(
                            x: .value("Nacht", s.end, unit: .day),
                            y: .value("Stunden", s.duration(of: stage) / 3600)
                        )
                        .foregroundStyle(by: .value("Phase", stage.title))
                    }
                }

                if let selectedNight {
                    RuleMark(x: .value("Ausgewählt", selectedNight.end))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartForegroundStyleScale(
                domain: styleScale.map(\.0),
                range: styleScale.map(\.1)
            )
            .id(range.rawValue)
            .frame(height: 220)
            .chartXScale(domain: nightlyChartDomain)
            .chartXVisibleDomain(length: nightlyVisibleDuration)
            .chartScrollableAxes(.horizontal)
            .chartTapSelection(value: $selectedNightDate)
            .chartPinchZoom($nightlyZoomLevel)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.day().month(), centered: false)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
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
            .modernChartSurface(tint: .indigo)

            if let selectedNight {
                ChartSelectedValue(
                    title: selectedNight.end.formatted(.dateTime.weekday(.abbreviated).day().month().year()),
                    values: SleepStage.allCases
                        .filter { $0 != .awake && selectedNight.duration(of: $0) > 0 }
                        .map { ($0.color, "\($0.title) \(selectedNight.duration(of: $0).hoursMinutes)") }
                )
            }

            ChartGestureHint()
        }
    }

    // MARK: Durchschnitte

    private var averages: some View {
        let count = Double(max(sessions.count, 1))
        let avgSleep = sessions.reduce(0) { $0 + $1.asleep } / count
        let avgDeep = sessions.reduce(0) { $0 + $1.deep } / count
        let avgREM = sessions.reduce(0) { $0 + $1.rem } / count
        let avgEff = sessions.reduce(0) { $0 + $1.efficiency } / count
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.format("Durchschnitt (%lld Nächte)", Int64(sessions.count))).font(.headline)
            LazyVGrid(columns: metricColumns, spacing: 12) {
                smallStat(avgSleep.hoursMinutes, "Ø Schlaf")
                smallStat(avgDeep.hoursMinutes, "Ø Tief")
                smallStat(avgREM.hoursMinutes, "Ø REM")
                smallStat("\(Int((avgEff * 100).rounded())) %", "Ø Effizienz")
            }
        }
    }

    // MARK: Bausteine

    private func bigStat(_ value: String, _ title: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(L10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(14)
        .professionalCard(tint: color, cornerRadius: 18)
    }

    private func smallStat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(L10n.string(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(12)
        .professionalCard(tint: .indigo, cornerRadius: 16)
    }

    private func load() async {
        isLoading = true
        selectedSleepTime = nil
        selectedNightDate = nil
        hypnogramZoomLevel = 1
        nightlyZoomLevel = 1
        sessions = await SleepCacheStore.shared.load(range: range, referenceDate: referenceDate)
        isLoading = sessions.isEmpty
        let fresh = (try? await health.fetchSleep(in: range, referenceDate: referenceDate)) ?? sessions
        sessions = fresh
        if !fresh.isEmpty {
            await SleepCacheStore.shared.save(fresh, range: range, referenceDate: referenceDate)
        }
        isLoading = false
    }

    private var loadKey: String {
        "\(range.rawValue)-\(Int(referenceDate.timeIntervalSince1970 / 60))"
    }

    private var periodLabel: String {
        let interval = range.dateInterval(referenceDate: referenceDate)
        switch range {
        case .day:
            return interval.start.formatted(.dateTime.weekday(.abbreviated).day().month().year())
        case .week, .month:
            let end = Calendar.healthApp.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(.dateTime.day().month())) - \(end.formatted(.dateTime.day().month().year()))"
        case .year:
            return interval.start.formatted(.dateTime.year())
        }
    }

    private var isNextPeriodInFuture: Bool {
        range.dateInterval(referenceDate: shiftedReference(by: 1)).start > Date()
    }

    private func shiftedReference(by amount: Int) -> Date {
        let component: Calendar.Component
        let value: Int
        switch range {
        case .day:
            component = .day
            value = amount
        case .week:
            component = .day
            value = amount * 7
        case .month:
            component = .month
            value = amount
        case .year:
            component = .year
            value = amount
        }
        return Calendar.healthApp.date(byAdding: component, value: value, to: referenceDate) ?? referenceDate
    }

    private var sessionsForCharts: [SleepSession] {
        sessions.sorted { $0.end < $1.end }
    }

    private func selectedSleepSegment(in session: SleepSession) -> SleepSegment? {
        guard let selectedSleepTime else { return nil }
        if let exact = session.segments.first(where: {
            selectedSleepTime >= $0.start && selectedSleepTime <= $0.end
        }) {
            return exact
        }
        return session.segments.min {
            abs($0.start.addingTimeInterval($0.duration / 2).timeIntervalSince(selectedSleepTime))
                < abs($1.start.addingTimeInterval($1.duration / 2).timeIntervalSince(selectedSleepTime))
        }
    }

    private var selectedNight: SleepSession? {
        guard let selectedNightDate else { return nil }
        return sessionsForCharts.min {
            abs($0.end.timeIntervalSince(selectedNightDate))
                < abs($1.end.timeIntervalSince(selectedNightDate))
        }
    }

    private var nightlyChartDomain: ClosedRange<Date> {
        let start = sessionsForCharts.map(\.end).min() ?? referenceDate
        let last = sessionsForCharts.map(\.end).max() ?? start
        let end = Calendar.healthApp.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        return start...end
    }

    private var nightlyVisibleDuration: TimeInterval {
        max(2 * 86_400, nightlyChartDomain.upperBound.timeIntervalSince(nightlyChartDomain.lowerBound) / nightlyZoomLevel)
    }

    private func stageSlices(_ s: SleepOverview) -> [SleepStageSlice] {
        [
            SleepStageSlice(stage: .deep, duration: s.deep),
            SleepStageSlice(stage: .core, duration: s.core),
            SleepStageSlice(stage: .rem, duration: s.rem),
            SleepStageSlice(stage: .awake, duration: s.awake)
        ]
    }

    private func overview(for session: SleepSession) -> SleepOverview {
        SleepOverview(asleep: session.asleep,
                      timeInBed: session.timeInBed,
                      deep: session.deep,
                      core: session.core,
                      rem: session.rem,
                      awake: session.awake,
                      efficiency: session.efficiency)
    }
}

private struct SleepStageSlice: Identifiable {
    let stage: SleepStage
    let duration: TimeInterval
    var id: String { stage.rawValue }
}

private struct SleepOverview {
    let asleep: TimeInterval
    let timeInBed: TimeInterval
    let deep: TimeInterval
    let core: TimeInterval
    let rem: TimeInterval
    let awake: TimeInterval
    let efficiency: Double
}
