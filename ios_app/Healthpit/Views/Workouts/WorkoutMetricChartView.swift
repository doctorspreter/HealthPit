//
//  WorkoutMetricChartView.swift
//  Healthpit
//
//  Ein kombiniertes Trainingsdiagramm fuer Pace/Speed, Puls und Hoehenmeter.
//

import Charts
import CoreLocation
import SwiftUI

enum WorkoutMetricKind: String, CaseIterable, Identifiable {
    case pace
    case speed
    case heartRate
    case elevation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pace: return L10n.string("Pace")
        case .speed: return L10n.string("Tempo")
        case .heartRate: return L10n.string("Puls")
        case .elevation: return L10n.string("Höhe")
        }
    }

    var color: Color {
        switch self {
        case .pace: return .orange
        case .speed: return .blue
        case .heartRate: return .pink
        case .elevation: return .green
        }
    }
}

struct WorkoutMetricChartView: View {
    let splits: [WorkoutSplit]
    let heartRate: HeartRateSummary?
    let elevationGainBySplit: [Int: Double]
    let isCycling: Bool

    @State private var selectedKinds: [WorkoutMetricKind] = []
    @State private var selectedKilometer: Int?
    @State private var chartZoomLevel = 1.0

    var body: some View {
        let kinds = activeKinds
        let series = seriesValues(for: kinds)
        let domains = scaleDomains(for: series)
        let points = chartPoints(for: kinds, series: series, domains: domains)
        let showsPointSymbols = points.count <= 60
        let selectedPoints = nearestPoints(to: selectedKilometer, in: points, kinds: kinds)
        let selectedIDs = Set(selectedPoints.map(\.id))
        let primaryKind = kinds.first ?? (isCycling ? .speed : .pace)
        let secondaryKind = kinds.dropFirst().first
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                metricPicker(activeKinds: kinds)

                axisAssignment(primary: primaryKind, secondary: secondaryKind)

                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("km", point.kilometer),
                            y: .value("Skaliert", point.normalized)
                        )
                        .interpolationMethod(showsPointSymbols ? .catmullRom : .linear)
                        .foregroundStyle(by: .value("Metrik", point.kind.title))

                        if showsPointSymbols {
                            PointMark(
                                x: .value("km", point.kilometer),
                                y: .value("Skaliert", point.normalized)
                            )
                            .foregroundStyle(by: .value("Metrik", point.kind.title))
                        }

                        if selectedIDs.contains(point.id) {
                            PointMark(
                                x: .value("Ausgewählt", point.kilometer),
                                y: .value("Skaliert", point.normalized)
                            )
                            .foregroundStyle(point.kind.color)
                            .symbolSize(85)
                        }
                    }

                    if let selectedKilometer = selectedPoints.first?.kilometer {
                        RuleMark(x: .value("Ausgewählt", selectedKilometer))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .frame(height: 260)
                .chartForegroundStyleScale(colorScale)
                .chartXAxisLabel(WorkoutUnits.isImperial ? L10n.string("Meilen") : L10n.string("Kilometer"))
                .chartYScale(domain: 0...1)
                .chartXScale(domain: kilometerDomain(for: points))
                .chartXVisibleDomain(length: visibleKilometerCount(for: points))
                .chartScrollableAxes(.horizontal)
                .chartTapSelection(value: $selectedKilometer)
                .chartPinchZoom($chartZoomLevel)
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: normalizedAxisValues) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let normalized = value.as(Double.self),
                               let domain = domains[primaryKind] {
                                Text(axisValue(domain.rawValue(at: normalized), for: primaryKind))
                                    .font(.caption2)
                                    .foregroundStyle(primaryKind.color)
                            }
                        }
                    }

                    if let secondaryKind, let secondaryDomain = domains[secondaryKind] {
                        AxisMarks(position: .trailing, values: normalizedAxisValues) { value in
                            AxisTick()
                            AxisValueLabel {
                                if let normalized = value.as(Double.self) {
                                    Text(axisValue(secondaryDomain.rawValue(at: normalized), for: secondaryKind))
                                        .font(.caption2)
                                        .foregroundStyle(secondaryKind.color)
                                }
                            }
                        }
                    }
                }
                .modernChartSurface(tint: primaryKind.color)

                if let selectedKilometer = selectedPoints.first?.kilometer, !selectedPoints.isEmpty {
                    ChartSelectedValue(
                        title: "\(WorkoutUnits.distanceSymbol) \(selectedKilometer)",
                        values: selectedPoints.map { ($0.kind.color, $0.displayValue) }
                    )
                }

                ChartGestureHint()
            }
        }
    }

    private func metricPicker(activeKinds: [WorkoutMetricKind]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableKinds) { kind in
                    Button {
                        toggle(kind, current: activeKinds)
                        selectedKilometer = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: activeKinds.contains(kind) ? "checkmark.circle.fill" : "circle")
                            Text(kind.title)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(kind.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(kind.color.opacity(activeKinds.contains(kind) ? 0.16 : 0.07),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func axisAssignment(primary: WorkoutMetricKind,
                                secondary: WorkoutMetricKind?) -> some View {
        HStack {
            Text("Links: \(primary.title)")
                .foregroundStyle(primary.color)
            Spacer()
            if let secondary {
                Text("Rechts: \(secondary.title)")
                    .foregroundStyle(secondary.color)
            }
        }
        .font(.caption2.bold())
    }

    private var availableKinds: [WorkoutMetricKind] {
        var kinds: [WorkoutMetricKind] = []
        if !rawValues(for: isCycling ? .speed : .pace).isEmpty {
            kinds.append(isCycling ? .speed : .pace)
        }
        if hasHeartRate { kinds.append(.heartRate) }
        if hasElevation { kinds.append(.elevation) }
        return kinds
    }

    private var activeKinds: [WorkoutMetricKind] {
        let available = availableKinds
        let filtered = selectedKinds.filter { available.contains($0) }
        if !filtered.isEmpty {
            return filtered
        }
        return available
    }

    private func seriesValues(for kinds: [WorkoutMetricKind]) -> [WorkoutMetricKind: [WorkoutMetricRawValue]] {
        Dictionary(uniqueKeysWithValues: kinds.map { ($0, rawValues(for: $0)) })
    }

    private func scaleDomains(for series: [WorkoutMetricKind: [WorkoutMetricRawValue]])
        -> [WorkoutMetricKind: WorkoutMetricScaleDomain] {
        series.mapValues { WorkoutMetricScaleDomain(values: $0.map(\.value)) }
    }

    private func chartPoints(for kinds: [WorkoutMetricKind],
                             series: [WorkoutMetricKind: [WorkoutMetricRawValue]],
                             domains: [WorkoutMetricKind: WorkoutMetricScaleDomain]) -> [WorkoutMetricChartPoint] {
        kinds.flatMap { kind -> [WorkoutMetricChartPoint] in
            guard let domain = domains[kind] else { return [] }
            return (series[kind] ?? []).map {
                WorkoutMetricChartPoint(kilometer: $0.kilometer,
                                        kind: kind,
                                        normalized: domain.normalized($0.value),
                                        displayValue: displayValue($0.value, for: kind))
            }
        }
    }

    private func nearestPoints(to kilometer: Int?,
                               in points: [WorkoutMetricChartPoint],
                               kinds: [WorkoutMetricKind]) -> [WorkoutMetricChartPoint] {
        guard let kilometer else { return [] }
        return kinds.compactMap { kind in
            points.filter { $0.kind == kind }
                .min { abs($0.kilometer - kilometer) < abs($1.kilometer - kilometer) }
        }
    }

    private func toggle(_ kind: WorkoutMetricKind, current: [WorkoutMetricKind]) {
        if current.contains(kind) {
            guard current.count > 1 else { return }
            selectedKinds = current.filter { $0 != kind }
        } else {
            selectedKinds = current + [kind]
        }
    }

    private func kilometerDomain(for points: [WorkoutMetricChartPoint]) -> ClosedRange<Int> {
        let values = points.map(\.kilometer)
        let lower = values.min() ?? 0
        return lower...(max(values.max() ?? lower, lower + 1))
    }

    private func visibleKilometerCount(for points: [WorkoutMetricChartPoint]) -> Int {
        let domain = kilometerDomain(for: points)
        let count = domain.upperBound - domain.lowerBound + 1
        return min(count, max(2, Int(ceil(Double(count) / chartZoomLevel))))
    }

    private var hasHeartRate: Bool {
        splits.contains { splitHeartRate($0) != nil }
    }

    private var hasElevation: Bool {
        splits.contains { (elevationGainBySplit[$0.id] ?? 0) > 0 }
    }

    private func rawValues(for kind: WorkoutMetricKind) -> [WorkoutMetricRawValue] {
        splits.compactMap { split in
            switch kind {
            case .pace:
                guard split.paceSecondsPerKm.isFinite, split.paceSecondsPerKm > 0 else { return nil }
                return WorkoutMetricRawValue(kilometer: split.id, value: split.paceSecondsPerKm / 60)
            case .speed:
                guard split.averageSpeedKmh.isFinite, split.averageSpeedKmh > 0 else { return nil }
                return WorkoutMetricRawValue(kilometer: split.id, value: split.averageSpeedKmh)
            case .heartRate:
                guard let bpm = splitHeartRate(split) else { return nil }
                return WorkoutMetricRawValue(kilometer: split.id, value: bpm)
            case .elevation:
                guard let meters = elevationGainBySplit[split.id], meters > 0 else { return nil }
                return WorkoutMetricRawValue(kilometer: split.id, value: meters)
            }
        }
    }

    private func splitHeartRate(_ split: WorkoutSplit) -> Double? {
        guard let start = split.start,
              let end = split.end,
              let samples = heartRate?.samples,
              !samples.isEmpty else {
            return nil
        }
        let values = samples
            .filter { $0.date >= start && $0.date <= end }
            .map(\.bpm)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func displayValue(_ value: Double, for kind: WorkoutMetricKind) -> String {
        switch kind {
        case .pace:
            return WorkoutUnits.pace(secondsPerKilometer: Int((value * 60).rounded()))
        case .speed:
            return WorkoutUnits.speed(kmh: value)
        case .heartRate:
            return "\(Int(value.rounded())) bpm"
        case .elevation:
            return "\(Int(value.rounded())) hm"
        }
    }

    private func axisValue(_ value: Double, for kind: WorkoutMetricKind) -> String {
        switch kind {
        case .pace:
            return WorkoutUnits.pace(secondsPerKilometer: Int((value * 60).rounded()))
        case .speed:
            return compactAxisNumber(WorkoutUnits.speedValue(kmh: value), unit: WorkoutUnits.speedSymbol)
        case .heartRate:
            return "\(Int(value.rounded()))"
        case .elevation:
            return "\(Int(value.rounded()))"
        }
    }

    private var normalizedAxisValues: [Double] {
        [0, 0.5, 1]
    }

    private var colorScale: KeyValuePairs<String, Color> {
        [
            WorkoutMetricKind.pace.title: WorkoutMetricKind.pace.color,
            WorkoutMetricKind.speed.title: WorkoutMetricKind.speed.color,
            WorkoutMetricKind.heartRate.title: WorkoutMetricKind.heartRate.color,
            WorkoutMetricKind.elevation.title: WorkoutMetricKind.elevation.color,
        ]
    }
}

private struct WorkoutMetricRawValue {
    let kilometer: Int
    let value: Double
}

private struct WorkoutMetricChartPoint: Identifiable {
    let kilometer: Int
    let kind: WorkoutMetricKind
    let normalized: Double
    let displayValue: String

    var id: String { "\(kind.rawValue)-\(kilometer)" }
}

struct WorkoutTimelineSample: Hashable {
    let timestamp: Date?
    let latitude: Double?
    let longitude: Double?
    let elevation: Double?
    let heartRate: Double?
}

struct WorkoutSampleTimelineChartView: View {
    let samples: [WorkoutTimelineSample]
    let heartRate: HeartRateSummary?
    let isCycling: Bool
    private let cachedSpeedValues: [WorkoutTimelineSpeedValue]

    @State private var selectedKinds: [WorkoutMetricKind] = []
    @State private var selectedDate: Date?
    @State private var chartZoomLevel = 1.0

    init(samples: [WorkoutTimelineSample], heartRate: HeartRateSummary?, isCycling: Bool) {
        self.samples = samples
        self.heartRate = heartRate
        self.isCycling = isCycling
        self.cachedSpeedValues = Self.makeSpeedValues(from: samples)
    }

    var body: some View {
        let kinds = activeKinds
        let series = seriesValues(for: kinds)
        let domains = scaleDomains(for: series)
        let points = chartPoints(for: kinds, series: series, domains: domains)
        let showsPointSymbols = points.count <= 60
        let selectedPoints = nearestPoints(to: selectedDate, in: points, kinds: kinds)
        let selectedIDs = Set(selectedPoints.map(\.id))
        let primaryKind = kinds.first ?? (isCycling ? .speed : .pace)
        let secondaryKind = kinds.dropFirst().first
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("Alle Messwerte"))
                    .font(.headline)
                metricPicker(activeKinds: kinds)
                axisAssignment(primary: primaryKind, secondary: secondaryKind)
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Zeit", point.date),
                            y: .value("Skaliert", point.normalized)
                        )
                        .interpolationMethod(showsPointSymbols ? .catmullRom : .linear)
                        .foregroundStyle(by: .value("Metrik", point.kind.title))

                        if showsPointSymbols {
                            PointMark(
                                x: .value("Zeit", point.date),
                                y: .value("Skaliert", point.normalized)
                            )
                            .foregroundStyle(by: .value("Metrik", point.kind.title))
                        }

                        if selectedIDs.contains(point.id) {
                            PointMark(
                                x: .value("Ausgewählt", point.date),
                                y: .value("Skaliert", point.normalized)
                            )
                            .foregroundStyle(point.kind.color)
                            .symbolSize(85)
                        }
                    }

                    if let selectedDate = selectedPoints.first?.date {
                        RuleMark(x: .value("Ausgewählt", selectedDate))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .frame(height: 260)
                .chartForegroundStyleScale(colorScale)
                .chartYScale(domain: 0...1)
                .chartXScale(domain: timelineDomain(for: points))
                .chartXVisibleDomain(length: visibleTimelineDuration(for: points))
                .chartScrollableAxes(.horizontal)
                .chartTapSelection(value: $selectedDate)
                .chartPinchZoom($chartZoomLevel)
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: normalizedAxisValues) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let normalized = value.as(Double.self),
                               let domain = domains[primaryKind] {
                                Text(axisValue(domain.rawValue(at: normalized), for: primaryKind))
                                    .font(.caption2)
                                    .foregroundStyle(primaryKind.color)
                            }
                        }
                    }

                    if let secondaryKind, let secondaryDomain = domains[secondaryKind] {
                        AxisMarks(position: .trailing, values: normalizedAxisValues) { value in
                            AxisTick()
                            AxisValueLabel {
                                if let normalized = value.as(Double.self) {
                                    Text(axisValue(secondaryDomain.rawValue(at: normalized), for: secondaryKind))
                                        .font(.caption2)
                                        .foregroundStyle(secondaryKind.color)
                                }
                            }
                        }
                    }
                }
                .modernChartSurface(tint: primaryKind.color)

                if let selectedDate = selectedPoints.first?.date, !selectedPoints.isEmpty {
                    ChartSelectedValue(
                        title: selectedDate.formatted(.dateTime.hour().minute().second()),
                        values: selectedPoints.map { ($0.kind.color, $0.displayValue) }
                    )
                }

                ChartGestureHint()
            }
        }
    }

    private func metricPicker(activeKinds: [WorkoutMetricKind]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableKinds) { kind in
                    Button {
                        toggle(kind, current: activeKinds)
                        selectedDate = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: activeKinds.contains(kind) ? "checkmark.circle.fill" : "circle")
                            Text(kind.title)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(kind.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(kind.color.opacity(activeKinds.contains(kind) ? 0.16 : 0.07),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func axisAssignment(primary: WorkoutMetricKind,
                                secondary: WorkoutMetricKind?) -> some View {
        HStack {
            Text("Links: \(primary.title)")
                .foregroundStyle(primary.color)
            Spacer()
            if let secondary {
                Text("Rechts: \(secondary.title)")
                    .foregroundStyle(secondary.color)
            }
        }
        .font(.caption2.bold())
    }

    private var availableKinds: [WorkoutMetricKind] {
        var kinds: [WorkoutMetricKind] = []
        if !rawValues(for: isCycling ? .speed : .pace).isEmpty {
            kinds.append(isCycling ? .speed : .pace)
        }
        if !rawValues(for: .heartRate).isEmpty {
            kinds.append(.heartRate)
        }
        if !rawValues(for: .elevation).isEmpty {
            kinds.append(.elevation)
        }
        return kinds
    }

    private var activeKinds: [WorkoutMetricKind] {
        let available = availableKinds
        let filtered = selectedKinds.filter { available.contains($0) }
        if !filtered.isEmpty {
            return filtered
        }
        return available
    }

    private func seriesValues(for kinds: [WorkoutMetricKind]) -> [WorkoutMetricKind: [WorkoutTimelineRawValue]] {
        Dictionary(uniqueKeysWithValues: kinds.map { ($0, rawValues(for: $0)) })
    }

    private func scaleDomains(for series: [WorkoutMetricKind: [WorkoutTimelineRawValue]])
        -> [WorkoutMetricKind: WorkoutMetricScaleDomain] {
        series.mapValues { WorkoutMetricScaleDomain(values: $0.map(\.value)) }
    }

    private func chartPoints(for kinds: [WorkoutMetricKind],
                             series: [WorkoutMetricKind: [WorkoutTimelineRawValue]],
                             domains: [WorkoutMetricKind: WorkoutMetricScaleDomain]) -> [WorkoutTimelineChartPoint] {
        kinds.flatMap { kind -> [WorkoutTimelineChartPoint] in
            guard let domain = domains[kind] else { return [] }
            return chartSampledValues(series[kind] ?? []).map {
                WorkoutTimelineChartPoint(date: $0.date,
                                          kind: kind,
                                          normalized: domain.normalized($0.value),
                                          displayValue: displayValue($0.value, for: kind))
            }
        }
    }

    private func nearestPoints(to date: Date?,
                               in points: [WorkoutTimelineChartPoint],
                               kinds: [WorkoutMetricKind]) -> [WorkoutTimelineChartPoint] {
        guard let date else { return [] }
        return kinds.compactMap { kind in
            points.filter { $0.kind == kind }
                .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
    }

    private func toggle(_ kind: WorkoutMetricKind, current: [WorkoutMetricKind]) {
        if current.contains(kind) {
            guard current.count > 1 else { return }
            selectedKinds = current.filter { $0 != kind }
        } else {
            selectedKinds = current + [kind]
        }
    }

    private func timelineDomain(for points: [WorkoutTimelineChartPoint]) -> ClosedRange<Date> {
        let dates = points.map(\.date)
        let start = dates.min() ?? Date()
        let end = dates.max() ?? start.addingTimeInterval(1)
        return start...(end > start ? end : start.addingTimeInterval(1))
    }

    private func visibleTimelineDuration(for points: [WorkoutTimelineChartPoint]) -> TimeInterval {
        let domain = timelineDomain(for: points)
        let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return min(total, max(30, total / chartZoomLevel))
    }

    private func rawValues(for kind: WorkoutMetricKind) -> [WorkoutTimelineRawValue] {
        switch kind {
        case .pace, .speed:
            return speedValues.map { value in
                WorkoutTimelineRawValue(date: value.date,
                                        value: kind == .speed ? value.speedKmh : 60 / max(value.speedKmh, 0.1))
            }
        case .heartRate:
            let sampleValues = (heartRate?.samples ?? []).map {
                WorkoutTimelineRawValue(date: $0.date, value: $0.bpm)
            }
            if !sampleValues.isEmpty {
                return sampleValues
            }
            return samples.compactMap {
                guard let date = $0.timestamp, let bpm = $0.heartRate, bpm > 0 else { return nil }
                return WorkoutTimelineRawValue(date: date, value: bpm)
            }
        case .elevation:
            return samples.compactMap {
                guard let date = $0.timestamp, let elevation = $0.elevation else { return nil }
                return WorkoutTimelineRawValue(date: date, value: elevation)
            }
        }
    }

    private var speedValues: [WorkoutTimelineSpeedValue] {
        cachedSpeedValues
    }

    private static func makeSpeedValues(from samples: [WorkoutTimelineSample]) -> [WorkoutTimelineSpeedValue] {
        let route = samples
            .compactMap { sample -> (date: Date, location: CLLocation)? in
                guard let date = sample.timestamp,
                      let latitude = sample.latitude,
                      let longitude = sample.longitude else {
                    return nil
                }
                return (date, CLLocation(latitude: latitude, longitude: longitude))
            }
            .sorted { $0.date < $1.date }

        guard route.count > 1 else { return [] }
        var out: [WorkoutTimelineSpeedValue] = []
        for index in route.indices.dropFirst() {
            let previous = route[index - 1]
            let current = route[index]
            let seconds = current.date.timeIntervalSince(previous.date)
            guard seconds > 2 else { continue }
            let km = current.location.distance(from: previous.location) / 1000
            let speed = km / (seconds / 3600)
            guard speed.isFinite, speed > 0, speed < 80 else { continue }
            out.append(WorkoutTimelineSpeedValue(date: current.date, speedKmh: speed))
        }
        return out
    }

    private func displayValue(_ value: Double, for kind: WorkoutMetricKind) -> String {
        switch kind {
        case .pace:
            return WorkoutUnits.pace(secondsPerKilometer: Int((value * 60).rounded()))
        case .speed:
            return WorkoutUnits.speed(kmh: value)
        case .heartRate:
            return "\(Int(value.rounded())) bpm"
        case .elevation:
            return "\(Int(value.rounded())) m"
        }
    }

    private func axisValue(_ value: Double, for kind: WorkoutMetricKind) -> String {
        switch kind {
        case .pace:
            return WorkoutUnits.pace(secondsPerKilometer: Int((value * 60).rounded()))
        case .speed:
            return compactAxisNumber(WorkoutUnits.speedValue(kmh: value), unit: WorkoutUnits.speedSymbol)
        case .heartRate, .elevation:
            return "\(Int(value.rounded()))"
        }
    }

    private var normalizedAxisValues: [Double] {
        [0, 0.5, 1]
    }

    private var colorScale: KeyValuePairs<String, Color> {
        [
            WorkoutMetricKind.pace.title: WorkoutMetricKind.pace.color,
            WorkoutMetricKind.speed.title: WorkoutMetricKind.speed.color,
            WorkoutMetricKind.heartRate.title: WorkoutMetricKind.heartRate.color,
            WorkoutMetricKind.elevation.title: WorkoutMetricKind.elevation.color,
        ]
    }
}

private struct WorkoutTimelineRawValue {
    let date: Date
    let value: Double
}

private struct WorkoutTimelineSpeedValue {
    let date: Date
    let speedKmh: Double
}

private struct WorkoutTimelineChartPoint: Identifiable {
    let date: Date
    let kind: WorkoutMetricKind
    let normalized: Double
    let displayValue: String

    var id: String { "\(kind.rawValue)-\(date.timeIntervalSinceReferenceDate)" }
}

private struct WorkoutMetricScaleDomain {
    let lowerBound: Double
    let upperBound: Double

    init(values: [Double]) {
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? minimum
        if maximum - minimum < 0.0001 {
            let padding = max(abs(minimum) * 0.05, 0.5)
            lowerBound = minimum - padding
            upperBound = maximum + padding
        } else {
            lowerBound = minimum
            upperBound = maximum
        }
    }

    func normalized(_ value: Double) -> Double {
        (value - lowerBound) / (upperBound - lowerBound)
    }

    func rawValue(at normalized: Double) -> Double {
        lowerBound + ((upperBound - lowerBound) * normalized)
    }
}

private func compactAxisNumber(_ value: Double, unit: String? = nil) -> String {
    let number = compactChartAxisNumber(value)
    guard let unit, !unit.isEmpty else { return number }
    return "\(number) \(unit)"
}
