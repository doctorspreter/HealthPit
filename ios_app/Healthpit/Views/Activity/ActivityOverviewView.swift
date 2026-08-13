//
//  ActivityOverviewView.swift
//  Healthpit
//
//  Tagesuebersicht und Trends fuer Aktivitaetsdaten.
//

import Charts
import HealthKit
import SwiftUI

struct ActivityOverviewView: View {
    private let health = HealthKitManager.shared

    @State private var today: [String: Double] = [:]
    @State private var trendStats: [String: [DailyStatistic]] = [:]
    @State private var sleepTrendSessions: [SleepSession] = []
    @State private var loaded = false
    @State private var goals: [ActivityGoal] = ActivityGoalStore.goals()
    @State private var goalValues: [UUID: Double] = [:]
    @State private var isEditingGoals = false

    private let primaryMetrics: [HealthMetric] = [
        HealthMetric.metric(.stepCount),
        HealthMetric.metric(.activeEnergyBurned),
        HealthMetric.metric(.distanceWalkingRunning),
        HealthMetric.metric(.appleExerciseTime),
        HealthMetric.metric(.flightsClimbed),
        HealthMetric.metric(.walkingSpeed),
        HealthMetric.metric(.runningPower),
        HealthMetric.metric(.cyclingSpeed),
    ].compactMap { $0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                goalSection
                if !trends.isEmpty {
                    trendSection
                }
                todaySection
                allMetricsLink
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .professionalPageBackground(tint: .orange)
        .navigationTitle("Aktivität")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCached() }
        .refreshable {
            await refreshLive()
            SyncRefreshStatusStore.markLocalRefresh()
        }
        .sheet(isPresented: $isEditingGoals) {
            NavigationStack {
                ActivityGoalSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { isEditingGoals = false }
                        }
                    }
            }
        }
        .onChange(of: isEditingGoals) { _, isOpen in
            if !isOpen { Task { await reloadGoals() } }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfessionalSectionHeader(title: "Ziele",
                                      subtitle: "Was du dir für Tag, Woche, Monat oder Jahr vorgenommen hast")
            ActivityGoalSummary(goals: goals,
                                values: goalValues,
                                onEditGoals: { isEditingGoals = true })
        }
    }

    private func reloadGoals() async {
        goals = ActivityGoalStore.goals()
        goalValues = await health.progressValues(for: goals)
    }

    private var header: some View {
        let steps = primaryMetrics.first(where: { $0.id == HKQuantityTypeIdentifier.stepCount.rawValue })
        let value = steps.map { $0.formattedValueWithUnit(today[$0.id] ?? 0) }
        return ProfessionalPageHero(
            eyebrow: Date.now.formatted(.dateTime.weekday(.wide).day().month()),
            title: "Aktivität",
            subtitle: "Bewegung, Belastung und deine Entwicklung auf einen Blick.",
            symbol: "figure.run.circle.fill",
            tint: .orange,
            value: value,
            detail: "Schritte heute"
        )
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfessionalSectionHeader(title: "Deine Trends",
                                      subtitle: "Letzte 14 Tage im Vergleich zu deinem Normalwert")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(trends.prefix(6)) { trend in
                    trendCard(trend)
                }
            }
            Label("Vergleich mit den vorherigen 90 Tagen", systemImage: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfessionalSectionHeader(title: "Heute",
                                      subtitle: "Aktuelle Werte gegenüber deinem 3-Monats-Schnitt")
            ForEach(primaryMetrics) { metric in
                activityRow(metric)
            }
        }
    }

    private var allMetricsLink: some View {
        NavigationLink {
            CategoryMetricListView(category: .activity)
        } label: {
            Label("Alle Aktivitätswerte", systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .professionalCard(tint: .orange)
        }
        .buttonStyle(.plain)
    }

    private func activityRow(_ metric: HealthMetric) -> some View {
        let current = today[metric.id] ?? 0
        let average = averageForMetric(metric)
        let maxValue = max(current, average, 1)
        return NavigationLink {
            MetricDetailView(metric: metric)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: metric.systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(metric.category.tint)
                        .frame(width: 34, height: 34)
                        .background(metric.category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Text(metric.title)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(metric.formattedValueWithUnit(current))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                ZStack(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.secondary.opacity(0.13))
                            .frame(width: proxy.size.width * min(average / maxValue, 1))
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(LinearGradient(colors: [metric.category.tint, metric.category.tint.opacity(0.65)],
                                                 startPoint: .leading,
                                                 endPoint: .trailing))
                            .frame(width: proxy.size.width * min(current / maxValue, 1))
                    }
                }
                .frame(height: 12)
                Text("3-Monats-Normalwert: \(metric.formattedValueWithUnit(average))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .professionalCard(tint: metric.category.tint)
        }
        .buttonStyle(.plain)
    }

    private func trendCard(_ trend: ActivityTrend) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: trend.symbol)
                .font(.title3)
                .foregroundStyle(trend.color)
                .frame(width: 36, height: 36)
                .background(trend.color.opacity(0.14), in: Circle())
            Text(trend.title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(trend.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .padding(14)
        .professionalCard(tint: trend.color)
    }

    private var trends: [ActivityTrend] {
        (activityTrends + sleepTrends).sorted { $0.score > $1.score }
    }

    private func averageForMetric(_ metric: HealthMetric) -> Double {
        let windows = trendWindows()
        let values = (trendStats[metric.id] ?? [])
            .filter { windows.baseline.contains($0.date) }
            .map(\.value)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private var activityTrends: [ActivityTrend] {
        let windows = trendWindows()
        return primaryMetrics.compactMap { metric in
            let stats = trendStats[metric.id] ?? []
            let recentValues = stats.filter { windows.recent.contains($0.date) }.map(\.value)
            let baselineValues = stats.filter { windows.baseline.contains($0.date) }.map(\.value)
            guard let recent = average(recentValues),
                  let baseline = average(baselineValues),
                  isRelevantChange(recent: recent, baseline: baseline, metric: metric) else {
                return nil
            }
            return trend(title: metric.title,
                         recentText: metric.formattedValueWithUnit(recent),
                         baselineText: metric.formattedValueWithUnit(baseline),
                         recent: recent,
                         baseline: baseline,
                         highIsGood: highValueIsGood(metric),
                         symbol: metric.systemImage)
        }
    }

    private var sleepTrends: [ActivityTrend] {
        let windows = trendWindows()
        return [
            sleepTrend(title: "Schlafdauer",
                       symbol: "bed.double.fill",
                       values: sleepTrendSessions.map { ($0.end, $0.asleep) },
                       baseline: windows.baseline,
                       recent: windows.recent,
                       relativeThreshold: 0.15,
                       absoluteThreshold: 30 * 60,
                       highIsGood: true,
                       format: { $0.hoursMinutes }),
            sleepTrend(title: "Tiefschlaf",
                       symbol: "moon.zzz.fill",
                       values: sleepTrendSessions.map { ($0.end, $0.deep) },
                       baseline: windows.baseline,
                       recent: windows.recent,
                       relativeThreshold: 0.22,
                       absoluteThreshold: 20 * 60,
                       highIsGood: true,
                       format: { $0.hoursMinutes }),
            sleepTrend(title: "REM-Schlaf",
                       symbol: "brain.head.profile",
                       values: sleepTrendSessions.map { ($0.end, $0.rem) },
                       baseline: windows.baseline,
                       recent: windows.recent,
                       relativeThreshold: 0.22,
                       absoluteThreshold: 20 * 60,
                       highIsGood: true,
                       format: { $0.hoursMinutes }),
            sleepTrend(title: "Wachzeit",
                       symbol: "eye.fill",
                       values: sleepTrendSessions.map { ($0.end, $0.awake) },
                       baseline: windows.baseline,
                       recent: windows.recent,
                       relativeThreshold: 0.25,
                       absoluteThreshold: 20 * 60,
                       highIsGood: false,
                       format: { $0.hoursMinutes }),
            sleepTrend(title: "Schlafeffizienz",
                       symbol: "percent",
                       values: sleepTrendSessions.map { ($0.end, $0.efficiency * 100) },
                       baseline: windows.baseline,
                       recent: windows.recent,
                       relativeThreshold: 0.08,
                       absoluteThreshold: 6,
                       highIsGood: true,
                       format: { "\(Int($0.rounded())) %" }),
        ].compactMap { $0 }
    }

    private func loadCached() async {
        today = await DashboardMetricCacheStore.shared.load(metricIDs: primaryMetrics.map(\.id))
        loaded = true
        await reloadGoals()
    }

    private func refreshLive() async {
        let windows = trendWindows()
        for metric in primaryMetrics {
            async let current = try? health.currentValue(for: metric)
            async let stats = try? health.fetchStatistics(for: metric,
                                                          interval: windows.full,
                                                          anchorDate: windows.full.start,
                                                          bucket: DateComponents(day: 1))
            today[metric.id] = await current ?? 0
            trendStats[metric.id] = await stats ?? []
        }
        sleepTrendSessions = (try? await health.fetchSleep(interval: windows.full)) ?? []
        await DashboardMetricCacheStore.shared.save(values: today)
        loaded = true
        await reloadGoals()
    }

    private func trendWindows(referenceDate: Date = .now) -> TrendWindows {
        let calendar = Calendar.healthApp
        let recentEnd = calendar.startOfDay(for: referenceDate)
        let recentStart = calendar.date(byAdding: .day, value: -14, to: recentEnd) ?? recentEnd
        let baselineStart = calendar.date(byAdding: .day, value: -90, to: recentStart) ?? recentStart
        return TrendWindows(baseline: DateInterval(start: baselineStart, end: recentStart),
                            recent: DateInterval(start: recentStart, end: recentEnd),
                            full: DateInterval(start: baselineStart, end: recentEnd))
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func isRelevantChange(recent: Double, baseline: Double, metric: HealthMetric) -> Bool {
        guard baseline > 0 else { return false }
        let relative = abs(recent / baseline - 1)
        let absolute = abs(recent - baseline)
        let threshold = relevanceThreshold(for: metric)
        return relative >= threshold.relative && absolute >= threshold.absolute
    }

    private func relevanceThreshold(for metric: HealthMetric) -> (relative: Double, absolute: Double) {
        switch metric.quantityTypeIdentifier {
        case .stepCount: return (0.18, 1_000)
        case .distanceWalkingRunning: return (0.18, 0.75)
        case .activeEnergyBurned: return (0.18, 100)
        case .appleExerciseTime: return (0.25, 10)
        case .flightsClimbed: return (0.30, 2)
        case .walkingSpeed, .cyclingSpeed: return (0.12, 0.4)
        case .runningPower: return (0.15, 20)
        default: return (0.25, 0)
        }
    }

    private func highValueIsGood(_ metric: HealthMetric) -> Bool {
        switch metric.quantityTypeIdentifier {
        case .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage:
            return false
        default:
            return true
        }
    }

    private func trend(title: String,
                       recentText: String,
                       baselineText: String,
                       recent: Double,
                       baseline: Double,
                       highIsGood: Bool,
                       symbol: String) -> ActivityTrend? {
        guard baseline > 0 else { return nil }
        let ratio = recent / baseline
        let wentUp = ratio >= 1
        let improved = highIsGood ? wentUp : !wentUp
        let percent = Int(abs(ratio - 1) * 100)
        let direction = L10n.string(wentUp ? "über" : "unter")
        return ActivityTrend(title: L10n.string(title),
                             subtitle: L10n.format("%lld%% %@ normal · %@ statt %@",
                                                   Int64(percent),
                                                   direction,
                                                   recentText,
                                                   baselineText),
                             symbol: improved ? "checkmark.circle.fill" : symbolForDirection(up: wentUp, fallback: symbol),
                             color: improved ? .green : .orange,
                             score: abs(ratio - 1))
    }

    private func sleepTrend(title: String,
                            symbol: String,
                            values: [(Date, Double)],
                            baseline: DateInterval,
                            recent: DateInterval,
                            relativeThreshold: Double,
                            absoluteThreshold: Double,
                            highIsGood: Bool,
                            format: (Double) -> String) -> ActivityTrend? {
        let recentValues = values.filter { recent.contains($0.0) }.map(\.1)
        let baselineValues = values.filter { baseline.contains($0.0) }.map(\.1)
        guard recentValues.count >= 3,
              baselineValues.count >= 14,
              let recentAverage = average(recentValues),
              let baselineAverage = average(baselineValues),
              baselineAverage > 0 else {
            return nil
        }
        let relative = abs(recentAverage / baselineAverage - 1)
        let absolute = abs(recentAverage - baselineAverage)
        guard relative >= relativeThreshold && absolute >= absoluteThreshold else {
            return nil
        }
        return trend(title: title,
                     recentText: format(recentAverage),
                     baselineText: format(baselineAverage),
                     recent: recentAverage,
                     baseline: baselineAverage,
                     highIsGood: highIsGood,
                     symbol: symbol)
    }

    private func symbolForDirection(up: Bool, fallback: String) -> String {
        if fallback.isEmpty {
            return up ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
        }
        return up ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
    }
}

private struct ActivityTrend: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let score: Double
}

private struct TrendWindows {
    let baseline: DateInterval
    let recent: DateInterval
    let full: DateInterval
}
