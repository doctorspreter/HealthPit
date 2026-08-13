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
        ScrollView {
            if loaded {
                VStack(alignment: .leading, spacing: 24) {
                    ProfessionalPageHero(
                        eyebrow: "Gesundheitsbereich",
                        title: category.title,
                        subtitle: categorySubtitle,
                        symbol: category.systemImage,
                        tint: category.tint,
                        value: "\(withData.count)",
                        detail: "Messwerte"
                    )

                    if category == .body {
                        bodyLegend
                    }

                    ProfessionalSectionHeader(title: "Übersicht",
                                              subtitle: "Aktuelle Werte und persönliche Verläufe")

                    LazyVStack(spacing: 12) {
                        ForEach(withData) { metric in
                            NavigationLink {
                                MetricDetailView(metric: metric)
                            } label: {
                                MetricRow(metric: metric)
                                    .padding(14)
                                    .professionalCard(tint: category.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !withoutData.isEmpty {
                        ProfessionalSectionHeader(title: "Noch ohne Daten",
                                                  subtitle: "Diese Werte wurden bisher nicht erfasst")
                        LazyVStack(spacing: 10) {
                            ForEach(withoutData) { metric in
                                emptyRow(metric)
                                    .padding(14)
                                    .professionalCard(tint: .gray)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            } else {
                ProgressView("Lade …")
                    .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
        .professionalPageBackground(tint: category.tint)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var bodyLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfessionalSectionHeader(title: "Einordnung",
                                      subtitle: "Unverbindliche Orientierung deiner Körperwerte")
            HStack(spacing: 12) {
                legendItem(.good)
                legendItem(.caution)
                legendItem(.bad)
                legendItem(.neutral)
            }
        }
        .padding(16)
        .professionalCard(tint: category.tint)
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

    private var categorySubtitle: String {
        switch category {
        case .heart: return "Herzfrequenz, Erholung und kardiovaskuläre Entwicklung."
        case .body: return "Körperzusammensetzung und langfristige Veränderungen."
        case .nutrition: return "Energie, Nährstoffe und deine tägliche Versorgung."
        case .vitals: return "Wichtige Vitalzeichen kompakt und verständlich eingeordnet."
        case .activity: return "Bewegung, Belastung und deine Entwicklung."
        case .workouts: return "Trainingseinheiten und Leistungsentwicklung."
        case .sleep: return "Schlafdauer, Phasen und Regeneration."
        case .cycle: return "Zyklusverlauf und protokollierte Symptome."
        }
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
        HStack(spacing: 12) {
            Image(systemName: metric.systemImage)
                .foregroundStyle(metric.category == .body ? status.color : metric.category.tint)
                .font(.subheadline.weight(.bold))
                .frame(width: 36, height: 36)
                .background((metric.category == .body ? status.color : metric.category.tint).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(metric.title)
                .font(.subheadline.weight(.semibold))
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
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
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
