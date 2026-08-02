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

    /// Reihenfolge der Y-Achse im Hypnogramm (unten → oben).
    private let stageOrder = ["Tief", "Core", "REM", "Wach"]
    private let styleScale: KeyValuePairs<String, Color> = [
        "Tief": .indigo, "Core": .blue, "REM": .cyan, "Wach": .orange
    ]
    private let metricColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Zeitraum", selection: $range) {
                    ForEach([TimeRange.day, .week, .month, .year]) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                periodControls

                if isLoading && sessions.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else if sessions.isEmpty {
                    ContentUnavailableView("Keine Schlafdaten",
                                           systemImage: "bed.double",
                                           description: Text("Für diesen Zeitraum liegen keine Schlafdaten vor."))
                        .frame(maxWidth: .infinity, minHeight: 200)
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
            .padding()
        }
        .navigationTitle("Schlaf")
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
            Text("\(sessions.count) Nacht\(sessions.count == 1 ? "" : "e") im Zeitraum")
                .font(.caption)
                .foregroundStyle(.secondary)
            phaseBar(s)
                .frame(height: 16)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            Text("Schlafphasen")
                .font(.headline)
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
        .padding(14)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Letzte Nacht").font(.headline)
            Chart(s.segments) { seg in
                BarMark(
                    xStart: .value("Start", seg.start),
                    xEnd: .value("Ende", seg.end),
                    y: .value("Phase", seg.stage.title)
                )
                .foregroundStyle(seg.stage.color)
                .cornerRadius(4)
            }
            .chartYScale(domain: stageOrder)
            .chartXScale(domain: s.start...s.end)
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
            }
            .chartForegroundStyleScale(styleScale)
            .id(range.rawValue)
            .frame(height: 220)
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
            Text("Durchschnitt (\(sessions.count) Nächte)").font(.headline)
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
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() async {
        isLoading = true
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
