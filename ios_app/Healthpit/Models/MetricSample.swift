//
//  MetricSample.swift
//  Healthpit
//
//  Eine einzelne Rohmessung aus HealthKit (eine HKQuantitySample-Instanz),
//  aufbereitet für Anzeige, Sortierung und Filterung in der Sample-Liste
//  (PLAN.md Screen 3). Bewusst ein schlankes, Sendable-fähiges Value-Type –
//  losgelöst von den HealthKit-Klassen.
//

import Foundation

/// Eine einzelne, datierte Messung mit Wert, Einheit und Datenquelle.
struct MetricSample: Identifiable, Hashable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    /// Wert in der Einheit der zugehörigen `HealthMetric`.
    let value: Double
    let unitSymbol: String
    /// Name der Quelle (z. B. "Apple Watch", "iPhone", Drittanbieter-App).
    let sourceName: String

    init(id: UUID = UUID(),
         startDate: Date,
         endDate: Date,
         value: Double,
         unitSymbol: String,
         sourceName: String) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.unitSymbol = unitSymbol
        self.sourceName = sourceName
    }
}

struct LatestMetricValue: Hashable, Sendable {
    let value: Double
    let date: Date
}
