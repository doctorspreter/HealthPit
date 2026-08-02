//
//  HealthMetric+Formatting.swift
//  Healthpit
//
//  Anzeige-Formatierung für Metrik-Werte: korrekte Nachkommastellen je Typ und
//  Skalierung von Prozentwerten (HealthKit liefert Prozente als Bruch 0…1).
//

import Foundation
import HealthKit

extension HealthMetric {

    /// Prozentwerte kommen als Bruch (0…1) aus HealthKit → für Anzeige ×100.
    var displayScale: Double { unitSymbol == "%" ? 100 : 1 }

    /// Sinnvolle Nachkommastellen je nach Metrik.
    var fractionDigits: Int {
        // Summen sind grundsätzlich ganzzahlig – außer Distanzen in km.
        if aggregation == .cumulativeSum {
            return unitSymbol == "km" ? 2 : 0
        }
        // Diskrete Werte: einige Einheiten brauchen eine Nachkommastelle.
        switch unitSymbol {
        case "km":                                              return 2
        case "km/h", "m/s", "°C", "kg", "cm", "m",
             "ml/kg·min", "L", "L/min", "":                     return 1
        default:                                                return 0   // bpm, mmHg, %, W, dB, ms, µg, mg, IE …
        }
    }

    /// Reiner Zahlenwert, schön formatiert (ohne Einheit), inkl. Prozent-Skalierung.
    func formattedValue(_ value: Double) -> String {
        let scaled = value * displayScale
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = fractionDigits
        nf.minimumFractionDigits = 0
        return nf.string(from: NSNumber(value: scaled))
            ?? String(format: "%.\(fractionDigits)f", scaled)
    }

    /// Wert inkl. Einheit, z. B. "10.907 Schritte" oder "72 bpm".
    func formattedValueWithUnit(_ value: Double) -> String {
        let text = formattedValue(value)
        return unitSymbol.isEmpty ? text : "\(text) \(unitSymbol)"
    }
}
