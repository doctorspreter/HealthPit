//
//  DashboardMetricEntry.swift
//  Healthpit
//
//  Ein Kennwert der Startseite.
//
//  Hier stand einmal ein Zwischenspeicher: Die Kacheln lasen ihn, damit beim
//  Oeffnen nicht alle gleichzeitig HealthKit befragten. Seit sie aus der
//  Datenbank lesen, wurde er nur noch geschrieben und von niemandem gelesen —
//  eine zweite Kopie desselben Bestands, die bei jedem Abgleich Arbeit machte.
//  Geblieben ist der Typ, in dem die Kacheln ihre Werte halten.
//

import Foundation

struct DashboardMetricCacheEntry: Codable, Sendable {
    let metricID: String
    let value: Double
    let updatedAt: Date
    /// Tatsächliches Messdatum der Probe (nil = heutiger Summenwert ohne Datum).
    var measuredAt: Date?
}
