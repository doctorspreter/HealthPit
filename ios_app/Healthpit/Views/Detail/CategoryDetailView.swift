//
//  CategoryDetailView.swift
//  Healthpit
//
//  Screen 2 – Liste aller Metriken einer Kategorie mit aktuellem Wert.
//  Metriken MIT Daten stehen oben (antippbar, mit Verlaufsdiagramm); Metriken,
//  zu denen es nie Daten gab, stehen ausgegraut am Ende.
//

import SwiftUI

struct CategoryDetailView: View {
    let category: HealthCategory
    private let health = HealthKitManager.shared

    @State private var withData: [HealthMetric] = []
    @State private var withoutData: [HealthMetric] = []
    @State private var loaded = false

    var body: some View {
        if category == .activity {
            ActivityOverviewView()
        } else {
            CategoryMetricListView(category: category)
        }
    }
}

struct CategoryMetricListView: View {
    let category: HealthCategory
    private let health = HealthKitManager.shared

    @State private var withData: [HealthMetric] = []
    @State private var withoutData: [HealthMetric] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded {
                List {
                    if category == .body {
                        Section {
                            bodyLegend
                        }
                    }

                    Section {
                        ForEach(withData) { metric in
                            NavigationLink {
                                MetricDetailView(metric: metric)
                            } label: {
                                MetricRow(metric: metric)
                            }
                        }
                    }

                    if !withoutData.isEmpty {
                        Section("Keine Daten") {
                            ForEach(withoutData) { metric in
                                emptyRow(metric)
                            }
                        }
                    }
                }
            } else {
                ProgressView("Lade …")
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var bodyLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Einordnung")
                .font(.subheadline.bold())
            HStack(spacing: 12) {
                legendItem(.good)
                legendItem(.caution)
                legendItem(.bad)
                legendItem(.neutral)
            }
        }
        .padding(.vertical, 4)
    }

    private func legendItem(_ status: BodyMetricStatus) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Ausgegraute Zeile für Metriken ohne jegliche Daten.
    private func emptyRow(_ metric: HealthMetric) -> some View {
        HStack {
            Image(systemName: metric.systemImage)
                .frame(width: 28)
            Text(metric.title)
            Spacer()
            Text("–")
        }
        .foregroundStyle(.tertiary)
    }

    private func load() async {
        let metrics = HealthMetric.metrics(for: category)
        withData = metrics
        withoutData = []
        loaded = true
    }
}

/// Eine Zeile in der Kategorie-Liste: Icon, Name, aktueller Wert.
struct MetricRow: View {
    let metric: HealthMetric
    private let health = HealthKitManager.shared

    @State private var value: Double?
    @State private var latestDate: Date?
    @State private var loaded = false

    var body: some View {
        let status = BodyMetricStatus.evaluate(metric: metric, value: value)
        HStack {
            Image(systemName: metric.systemImage)
                .foregroundStyle(metric.category == .body ? status.color : metric.category.tint)
                .frame(width: 28)
            Text(metric.title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(valueText)
                    .foregroundStyle(metric.category == .body ? status.color : .secondary)
                if metric.category == .body, value != nil {
                    Text(status.title)
                        .font(.caption2)
                        .foregroundStyle(status.color)
                }
                if let latestDate, !Calendar.healthApp.isDateInToday(latestDate) {
                    Text(latestDate.formatted(.dateTime.day().month().year()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task {
            if metric.aggregation == .discreteAverage {
                let latest = try? await health.latestValue(for: metric)
                value = latest?.value
                latestDate = latest?.date
            } else {
                value = try? await health.currentValue(for: metric)
                latestDate = nil
            }
            loaded = true
        }
    }

    private var valueText: String {
        if let value { return metric.formattedValueWithUnit(value) }
        return loaded ? "–" : "…"
    }
}
