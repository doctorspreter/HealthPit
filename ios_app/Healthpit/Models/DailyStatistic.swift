//
//  DailyStatistic.swift
//  Healthpit
//
//  Ein aggregierter Wert pro Bucket (Stunde/Tag/Monat) – das, was die
//  HKStatisticsCollectionQuery zurückgibt. Direkt als Datenpunkt für
//  Swift-Charts-Diagramme verwendbar.
//

import Foundation

/// Ein zusammengefasster Messwert für genau ein Zeitintervall.
struct DailyStatistic: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Beginn des Buckets (z. B. 08:00 Uhr bzw. der Tag).
    let date: Date
    /// Aggregierter Wert in der Einheit der zugehörigen `HealthMetric`.
    let value: Double

    init(id: UUID = UUID(), date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}
