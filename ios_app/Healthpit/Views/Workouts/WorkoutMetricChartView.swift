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

    @State private var selected: Set<WorkoutMetricKind> = []

    var body: some View {
        let points = chartPoints
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                metricPicker

                Chart(points) { point in
                    LineMark(
                        x: .value("km", point.kilometer),
                        y: .value("Wert", point.normalized)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(by: .value("Metrik", point.kind.title))

                    PointMark(
                        x: .value("km", point.kilometer),
                        y: .value("Wert", point.normalized)
                    )
                    .foregroundStyle(by: .value("Metrik", point.kind.title))
                }
                .frame(height: 260)
                .chartForegroundStyleScale(colorScale)
                .chartXAxisLabel("Kilometer")
                .chartYAxis(.hidden)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }

                if !latestValues.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(latestValues) { item in
                            Label(item.value, systemImage: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(item.kind.color)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableKinds) { kind in
                    Button {
                        toggle(kind)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedKinds.contains(kind) ? "checkmark.circle.fill" : "circle")
                            Text(kind.title)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(kind.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(kind.color.opacity(selectedKinds.contains(kind) ? 0.16 : 0.07),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    private var selectedKinds: Set<WorkoutMetricKind> {
        let available = Set(availableKinds)
        let filtered = selected.intersection(available)
        return filtered.isEmpty ? available : filtered
    }

    private var chartPoints: [WorkoutMetricChartPoint] {
        selectedKinds.flatMap { normalizedPoints(for: $0) }
            .sorted {
                if $0.kind.title == $1.kind.title { return $0.kilometer < $1.kilometer }
                return $0.kind.title < $1.kind.title
            }
    }

    private var latestValues: [WorkoutMetricLatestValue] {
        selectedKinds.compactMap { kind in
            guard let last = rawValues(for: kind).last else { return nil }
            return WorkoutMetricLatestValue(kind: kind, value: displayValue(last.value, for: kind))
        }
        .sorted { $0.kind.title < $1.kind.title }
    }

    private var colorScale: KeyValuePairs<String, Color> {
        [
            WorkoutMetricKind.pace.title: WorkoutMetricKind.pace.color,
            WorkoutMetricKind.speed.title: WorkoutMetricKind.speed.color,
            WorkoutMetricKind.heartRate.title: WorkoutMetricKind.heartRate.color,
            WorkoutMetricKind.elevation.title: WorkoutMetricKind.elevation.color,
        ]
    }

    private var hasHeartRate: Bool {
        splits.contains { splitHeartRate($0) != nil }
    }

    private var hasElevation: Bool {
        splits.contains { (elevationGainBySplit[$0.id] ?? 0) > 0 }
    }

    private func toggle(_ kind: WorkoutMetricKind) {
        if selectedKinds.contains(kind), selectedKinds.count == 1 {
            selected = []
            return
        }
        if selected.contains(kind) {
            selected.remove(kind)
        } else {
            selected.insert(kind)
        }
    }

    private func normalizedPoints(for kind: WorkoutMetricKind) -> [WorkoutMetricChartPoint] {
        let values = rawValues(for: kind)
        guard !values.isEmpty else { return [] }
        let raw = values.map(\.value)
        let minValue = raw.min() ?? 0
        let maxValue = raw.max() ?? minValue
        let span = max(maxValue - minValue, 0.0001)

        return values.map { item in
            WorkoutMetricChartPoint(kilometer: item.kilometer,
                                    kind: kind,
                                    normalized: (item.value - minValue) / span,
                                    displayValue: displayValue(item.value, for: kind))
        }
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
            let seconds = Int((value * 60).rounded())
            return "\(seconds / 60):" + String(format: "%02d /km", seconds % 60)
        case .speed:
            return String(format: "%.1f km/h", value)
        case .heartRate:
            return "\(Int(value.rounded())) bpm"
        case .elevation:
            return "\(Int(value.rounded())) hm"
        }
    }
}

private struct WorkoutMetricRawValue {
    let kilometer: Int
    let value: Double
}

private struct WorkoutMetricChartPoint: Identifiable {
    let id = UUID()
    let kilometer: Int
    let kind: WorkoutMetricKind
    let normalized: Double
    let displayValue: String
}

private struct WorkoutMetricLatestValue: Identifiable {
    let id = UUID()
    let kind: WorkoutMetricKind
    let value: String
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

    @State private var selected: Set<WorkoutMetricKind> = []

    var body: some View {
        let points = chartPoints
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Alle Messwerte")
                    .font(.headline)
                metricPicker
                Chart(points) { point in
                    LineMark(
                        x: .value("Zeit", point.date),
                        y: .value("Wert", point.normalized)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(by: .value("Metrik", point.kind.title))

                    PointMark(
                        x: .value("Zeit", point.date),
                        y: .value("Wert", point.normalized)
                    )
                    .foregroundStyle(by: .value("Metrik", point.kind.title))
                }
                .frame(height: 260)
                .chartForegroundStyleScale(colorScale)
                .chartYAxis(.hidden)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
                            .font(.caption2)
                    }
                }

                if !latestValues.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(latestValues) { item in
                            Label(item.value, systemImage: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(item.kind.color)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableKinds) { kind in
                    Button {
                        toggle(kind)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedKinds.contains(kind) ? "checkmark.circle.fill" : "circle")
                            Text(kind.title)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(kind.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(kind.color.opacity(selectedKinds.contains(kind) ? 0.16 : 0.07),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    private var selectedKinds: Set<WorkoutMetricKind> {
        let available = Set(availableKinds)
        let filtered = selected.intersection(available)
        return filtered.isEmpty ? available : filtered
    }

    private var chartPoints: [WorkoutTimelineChartPoint] {
        selectedKinds.flatMap { normalizedPoints(for: $0) }
            .sorted {
                if $0.kind.title == $1.kind.title { return $0.date < $1.date }
                return $0.kind.title < $1.kind.title
            }
    }

    private var latestValues: [WorkoutMetricLatestValue] {
        selectedKinds.compactMap { kind in
            guard let last = rawValues(for: kind).last else { return nil }
            return WorkoutMetricLatestValue(kind: kind, value: displayValue(last.value, for: kind))
        }
        .sorted { $0.kind.title < $1.kind.title }
    }

    private var colorScale: KeyValuePairs<String, Color> {
        [
            WorkoutMetricKind.pace.title: WorkoutMetricKind.pace.color,
            WorkoutMetricKind.speed.title: WorkoutMetricKind.speed.color,
            WorkoutMetricKind.heartRate.title: WorkoutMetricKind.heartRate.color,
            WorkoutMetricKind.elevation.title: WorkoutMetricKind.elevation.color,
        ]
    }

    private func toggle(_ kind: WorkoutMetricKind) {
        if selectedKinds.contains(kind), selectedKinds.count == 1 {
            selected = []
            return
        }
        if selected.contains(kind) {
            selected.remove(kind)
        } else {
            selected.insert(kind)
        }
    }

    private func normalizedPoints(for kind: WorkoutMetricKind) -> [WorkoutTimelineChartPoint] {
        let values = rawValues(for: kind)
        guard !values.isEmpty else { return [] }
        let raw = values.map(\.value)
        let minValue = raw.min() ?? 0
        let maxValue = raw.max() ?? minValue
        let span = max(maxValue - minValue, 0.0001)
        return values.map { item in
            WorkoutTimelineChartPoint(date: item.date,
                                      kind: kind,
                                      normalized: (item.value - minValue) / span,
                                      displayValue: displayValue(item.value, for: kind))
        }
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
            let seconds = Int((value * 60).rounded())
            return "\(seconds / 60):" + String(format: "%02d /km", seconds % 60)
        case .speed:
            return String(format: "%.1f km/h", value)
        case .heartRate:
            return "\(Int(value.rounded())) bpm"
        case .elevation:
            return "\(Int(value.rounded())) m"
        }
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
    let id = UUID()
    let date: Date
    let kind: WorkoutMetricKind
    let normalized: Double
    let displayValue: String
}
