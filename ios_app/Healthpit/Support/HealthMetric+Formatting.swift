//
//  HealthMetric+Formatting.swift
//  Healthpit
//
//  Anzeige-Formatierung für Metrik-Werte: Umrechnung in die eingestellte
//  Maßeinheit und korrekte Nachkommastellen je Typ.
//
//  Prozentwerte werden hier nicht mehr skaliert. Sie kommen aus der Datenbank
//  und stehen dort in der kanonischen Einheit — 96,2 heisst 96,2 %. Nur wer
//  unmittelbar aus HealthKit liest, bekommt den Bruch 0…1 und muss
//  `healthKitScale` anwenden.
//
//  Umgerechnet wird ausschliesslich hier, an der Anzeigegrenze. Alles dahinter
//  – Abfragen, Zwischenspeicher, Schwellwerte, Bridge-Payload – bleibt in den
//  HealthKit-Einheiten und damit metrisch.
//

import Foundation
import HealthKit

extension HealthMetric {

    /// Die Anzeige-Einheit für das aktuell eingestellte Maßsystem.
    var displayUnit: MetricDisplayUnit {
        Self.displayUnit(canonicalSymbol: canonicalUnitSymbol,
                         identifier: quantityTypeIdentifier,
                         aggregation: aggregation,
                         system: UnitPreference.active)
    }

    /// Symbol der Anzeige-Einheit, übersetzt (z. B. "km" oder "mi").
    var displaySymbol: String { displayUnit.symbol }

    /// HealthKit liefert Prozente als Bruch (0,962) → kanonisch sind 96,2.
    ///
    /// Gilt ausschliesslich fuer Werte, die unmittelbar aus HealthKit kommen.
    /// Alles, was aus der Datenbank gelesen wird, steht dort bereits in der
    /// kanonischen Einheit – dort noch einmal zu multiplizieren ergab die
    /// 9620 %, die in der Anzeige standen.
    var healthKitScale: Double { canonicalUnitSymbol == "%" ? 100 : 1 }

    /// Ein HealthKit-Wert in der Anzeige-Einheit.
    func displayValue(_ value: Double) -> Double {
        displayUnit.conversion.apply(value)
    }

    /// Umkehrung von `displayValue` – für Vergleiche gegen Schwellwerte, die
    /// in HealthKit-Einheiten definiert sind.
    func rawValue(fromDisplay value: Double) -> Double {
        displayUnit.conversion.invert(value)
    }

    /// Sinnvolle Nachkommastellen je nach Metrik und Maßsystem.
    var fractionDigits: Int { displayUnit.fractionDigits }

    /// Reiner Zahlenwert, schön formatiert (ohne Einheit), umgerechnet.
    func formattedValue(_ value: Double) -> String {
        formattedDisplayValue(displayValue(value))
    }

    /// Formatiert einen bereits umgerechneten Wert.
    func formattedDisplayValue(_ value: Double) -> String {
        let digits = fractionDigits
        let nf = NumberFormatter()
        nf.locale = .autoupdatingCurrent
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = digits
        nf.minimumFractionDigits = 0
        return nf.string(from: NSNumber(value: value))
            ?? String(format: "%.\(digits)f", value)
    }

    /// Wert inkl. Einheit, z. B. "10.907 Schritte" oder "72 bpm".
    func formattedValueWithUnit(_ value: Double) -> String {
        let symbol = displaySymbol
        let text = formattedValue(value)
        return symbol.isEmpty ? text : "\(text) \(symbol)"
    }

    /// Wert inkl. Einheit, wenn der Wert schon umgerechnet vorliegt.
    func formattedDisplayValueWithUnit(_ value: Double) -> String {
        let symbol = displaySymbol
        let text = formattedDisplayValue(value)
        return symbol.isEmpty ? text : "\(text) \(symbol)"
    }
}

// MARK: - Zuordnung metrisch → imperial

private extension HealthMetric {

    /// Die Zuordnung an genau einer Stelle.
    ///
    /// Geschaltet wird auf `canonicalUnitSymbol`, nicht auf `unitSymbol`: das
    /// uebersetzte Symbol heisst in anderen Sprachen anders und wuerde die
    /// Nachkommastellen still auf 0 fallen lassen.
    static func displayUnit(canonicalSymbol: String,
                            identifier: HKQuantityTypeIdentifier,
                            aggregation: AggregationStyle,
                            system: MeasurementSystem) -> MetricDisplayUnit {

        // Prozente sind maßsystem-unabhängig und kommen aus der Datenbank
        // bereits als Prozent. Eine Nachkommastelle, weil eine Sauerstoff-
        // saettigung von 96,2 % nicht als 96 % gelesen werden soll.
        if canonicalSymbol == "%" {
            return MetricDisplayUnit(symbolKey: "%", conversion: .identity, fractionDigits: 1)
        }

        guard system == .imperial else {
            return MetricDisplayUnit(symbolKey: canonicalSymbol,
                                     conversion: .identity,
                                     fractionDigits: metricFractionDigits(canonicalSymbol: canonicalSymbol,
                                                                          aggregation: aggregation))
        }

        switch canonicalSymbol {
        case "km":
            return MetricDisplayUnit(symbolKey: "mi", conversion: .factor(0.621371), fractionDigits: 2)
        case "m":
            // Schrittlänge liest sich in Fuß, Strecken in Yard.
            if identifier == .runningStrideLength {
                return MetricDisplayUnit(symbolKey: "ft", conversion: .factor(3.280840), fractionDigits: 2)
            }
            return MetricDisplayUnit(symbolKey: "yd", conversion: .factor(1.093613), fractionDigits: 0)
        case "cm":
            return MetricDisplayUnit(symbolKey: "in", conversion: .factor(0.393701), fractionDigits: 1)
        case "kg":
            return MetricDisplayUnit(symbolKey: "lb", conversion: .factor(2.204623), fractionDigits: 1)
        case "km/h":
            return MetricDisplayUnit(symbolKey: "mph", conversion: .factor(0.621371), fractionDigits: 1)
        case "m/s":
            return MetricDisplayUnit(symbolKey: "ft/s", conversion: .factor(3.280840), fractionDigits: 1)
        case "ml":
            return MetricDisplayUnit(symbolKey: "fl oz", conversion: .factor(0.033814), fractionDigits: 1)
        case "°C":
            return MetricDisplayUnit(symbolKey: "°F", conversion: .celsiusToFahrenheit, fractionDigits: 1)
        default:
            // Kalorien, Gramm, Milligramm, bpm, mmHg, Watt, dB, L, mg/dL … sind
            // in den USA dieselben Einheiten.
            return MetricDisplayUnit(symbolKey: canonicalSymbol,
                                     conversion: .identity,
                                     fractionDigits: metricFractionDigits(canonicalSymbol: canonicalSymbol,
                                                                          aggregation: aggregation))
        }
    }

    static func metricFractionDigits(canonicalSymbol: String, aggregation: AggregationStyle) -> Int {
        // Summen sind grundsätzlich ganzzahlig – außer Distanzen in km.
        if aggregation == .cumulativeSum {
            return canonicalSymbol == "km" ? 2 : 0
        }
        // Diskrete Werte: einige Einheiten brauchen eine Nachkommastelle.
        switch canonicalSymbol {
        case "km":                                              return 2
        case "km/h", "m/s", "°C", "kg", "cm", "m",
             "ml/kg·min", "L", "L/min", "":                     return 1
        default:                                                return 0   // bpm, mmHg, %, W, dB, ms, µg, mg, IE …
        }
    }
}
