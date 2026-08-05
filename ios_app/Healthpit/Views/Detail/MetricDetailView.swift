//
//  MetricDetailView.swift
//  Healthpit
//
//  Screen 3 – Detail einer Metrik mit Verlaufsdiagramm (Swift Charts) und
//  Zeitraum-Umschaltung (Tag/Woche/Monat/Jahr, Default Monat) sowie einer
//  Statistik-Zusammenfassung (Ø / Min / Max bzw. Summe).
//

import SwiftUI
import Charts

struct MetricDetailView: View {
    let metric: HealthMetric
    private let health = HealthKitManager.shared

    @State private var range: TimeRange = .month
    @State private var referenceDate = Date()
    @State private var stats: [DailyStatistic] = []
    @State private var isLoading = false
    @State private var showingValues = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Zeitraum", selection: $range) {
                    ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                periodControls
                chartSection
                summarySection
                valueTableSection
            }
            .padding()
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadKey) { await load() }
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
        .padding(10)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Diagramm

    @ViewBuilder
    private var chartSection: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if scaledPoints.isEmpty {
            ContentUnavailableView("Keine Daten",
                                   systemImage: "chart.xyaxis.line",
                                   description: Text("Für diesen Zeitraum liegen keine Werte vor."))
                .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Verlauf")
                    .font(.headline)
                Chart {
                    ForEach(scaledPoints) { point in
                        if metric.aggregation == .cumulativeSum {
                            BarMark(
                                x: .value("Datum", point.date, unit: range.chartComponent),
                                y: .value(metric.title, point.value)
                            )
                            .foregroundStyle(metric.category.tint)
                        } else {
                            AreaMark(
                                x: .value("Datum", point.date, unit: range.chartComponent),
                                y: .value(metric.title, point.value)
                            )
                            .foregroundStyle(metric.category.tint.opacity(0.18))

                            LineMark(
                                x: .value("Datum", point.date, unit: range.chartComponent),
                                y: .value(metric.title, point.value)
                            )
                            .foregroundStyle(metric.category.tint)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Datum", point.date, unit: range.chartComponent),
                                y: .value(metric.title, point.value)
                            )
                            .foregroundStyle(metric.category.tint)
                        }
                    }

                    RuleMark(y: .value("Durchschnitt", averageValue))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Ø \(formattedScaled(averageValue))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(height: 240)
            }
        }
    }

    // MARK: Statistik

    @ViewBuilder
    private var summarySection: some View {
        if !scaledPoints.isEmpty {
            let values = scaledPoints.map(\.value)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if metric.aggregation == .cumulativeSum {
                        stat("Summe", values.reduce(0, +))
                        stat("Ø/Tag", dailyAverageValue)
                        stat("Max", values.max() ?? 0)
                    } else {
                        stat("Ø", values.reduce(0, +) / Double(values.count))
                        stat("Min", values.min() ?? 0)
                        stat("Max", values.max() ?? 0)
                    }
                }
                statusLegend
            }
        }
    }

    @ViewBuilder
    private var statusLegend: some View {
        if let guide = BodyMetricStatus.guide(for: metric) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(guide.bands) { band in
                        Rectangle()
                            .fill(band.status.color.opacity(band.status == .caution ? 0.72 : 0.82))
                            .frame(height: 5)
                    }
                }
                .clipShape(Capsule())

                HStack {
                    ForEach(Array(guide.transitionValues.enumerated()), id: \.offset) { index, value in
                        if index > 0 { Spacer(minLength: 4) }
                        Text(metric.formattedValueWithUnit(value))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var valueTableSection: some View {
        if !scaledPoints.isEmpty {
            let rows = scaledPoints.sorted { $0.date > $1.date }
            DisclosureGroup("Einzelwerte", isExpanded: $showingValues) {
                VStack(spacing: 0) {
                    ForEach(rows) { point in
                        HStack {
                            Text(point.date, format: .dateTime.day().month().year().hour().minute())
                                .font(.subheadline)
                            Spacer()
                            Text(formattedScaled(point.value))
                                .font(.subheadline.bold())
                        }
                        .padding(.vertical, 9)
                        if point.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .font(.headline)
        }
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        // Die Schwellwerte sind in HealthKit-Einheiten definiert, der Wert liegt
        // hier schon in der Anzeige-Einheit vor – deshalb zurueckrechnen.
        let status = BodyMetricStatus.evaluate(metric: metric, value: metric.rawValue(fromDisplay: value))
        return VStack(spacing: 4) {
            Text(L10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formattedScaled(value))
                .font(.headline)
                .foregroundStyle(status.color)
            if !metric.displaySymbol.isEmpty {
                Text(metric.displaySymbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(status.color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(status.color.opacity(0.22), lineWidth: 1)
        }
    }

    // MARK: Daten

    /// Datenpunkte in der Anzeige-Einheit (Prozent-Skalierung, mi statt km …).
    private var scaledPoints: [DailyStatistic] {
        stats.map { DailyStatistic(id: $0.id, date: $0.date, value: metric.displayValue($0.value)) }
    }

    private var averageValue: Double {
        let values = scaledPoints.map(\.value)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private var dailyAverageValue: Double {
        let total = scaledPoints.map(\.value).reduce(0, +)
        return total / Double(daysForAverage)
    }

    private var daysForAverage: Int {
        let interval = range.dateInterval(referenceDate: referenceDate)
        let effectiveEnd = min(interval.end, Date())
        guard effectiveEnd > interval.start else { return 1 }
        let start = Calendar.healthApp.startOfDay(for: interval.start)
        let end = Calendar.healthApp.startOfDay(for: effectiveEnd)
        let days = Calendar.healthApp.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, effectiveEnd == interval.end ? days : days + 1)
    }

    /// Formatiert einen Wert, der bereits in der Anzeige-Einheit vorliegt.
    private func formattedScaled(_ value: Double) -> String {
        metric.formattedDisplayValue(value)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        stats = (try? await health.fetchStatistics(for: metric, in: range, referenceDate: referenceDate)) ?? []
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
            let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
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
        return Calendar.current.date(byAdding: component, value: value, to: referenceDate) ?? referenceDate
    }
}
