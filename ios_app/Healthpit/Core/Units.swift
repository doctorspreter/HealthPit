//
//  Units.swift
//  HealthPitCore
//
//  Einheiten werden getrennt vom Wert gespeichert. Die Registry legt je
//  Metrik eine kanonische Einheit fest; liefert ein Anbieter etwas anderes,
//  normalisiert HealthPit – behaelt aber Originalwert und Originaleinheit.
//

import Foundation

/// Interner Einheitencode, immer Grossbuchstaben (`KG`, `BPM`, `PCT`).
struct UnitCode: Hashable, Sendable, Codable, CustomStringConvertible,
                 ExpressibleByStringLiteral {
    let rawValue: String

    init(stringLiteral value: StringLiteralType) {
        precondition(!value.isEmpty, "Leerer Einheitencode")
        rawValue = value
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }
}

extension UnitCode {
    /// Dimensionslos (BMI, Index-Werte, Scores).
    static let none: UnitCode = "NONE"
    static let count: UnitCode = "CNT"
    static let percent: UnitCode = "PCT"

    static let meter: UnitCode = "M"
    static let kilometer: UnitCode = "KM"
    static let centimeter: UnitCode = "CM"
    static let mile: UnitCode = "MI"
    static let foot: UnitCode = "FT"
    static let inch: UnitCode = "IN"

    static let kilogram: UnitCode = "KG"
    static let gram: UnitCode = "G"
    static let milligram: UnitCode = "MG"
    static let microgram: UnitCode = "UG"
    static let pound: UnitCode = "LB"
    static let stone: UnitCode = "ST"

    static let second: UnitCode = "S"
    static let millisecond: UnitCode = "MS"
    static let minute: UnitCode = "MIN"
    static let hour: UnitCode = "H"
    static let day: UnitCode = "D"

    static let beatsPerMinute: UnitCode = "BPM"
    static let revolutionsPerMinute: UnitCode = "RPM"
    static let breathsPerMinute: UnitCode = "BRPM"

    static let kilocalorie: UnitCode = "KCAL"
    static let kilojoule: UnitCode = "KJ"

    static let milliliter: UnitCode = "ML"
    static let liter: UnitCode = "L"
    static let fluidOunce: UnitCode = "FLOZ"
    static let litersPerMinute: UnitCode = "LPM"

    static let celsius: UnitCode = "CEL"
    static let fahrenheit: UnitCode = "FAH"

    static let millimeterOfMercury: UnitCode = "MMHG"
    static let milligramPerDeciliter: UnitCode = "MGDL"
    static let millimolePerLiter: UnitCode = "MMOLL"

    static let watt: UnitCode = "W"
    static let metersPerSecond: UnitCode = "MPS"
    static let kilometersPerHour: UnitCode = "KMH"
    static let milesPerHour: UnitCode = "MPH"

    static let decibel: UnitCode = "DB"
    static let internationalUnit: UnitCode = "IU"
    static let milliliterPerKilogramMinute: UnitCode = "MLKGMIN"
    static let index: UnitCode = "IDX"
    static let score: UnitCode = "SCORE"
}

/// Rechnet Anbieter-Einheiten in die kanonische Einheit einer Metrik um.
///
/// Bewusst eine flache Faktortabelle statt einer Dimensionsalgebra: Es geht um
/// eine ueberschaubare Menge realer Einheiten, und eine Tabelle laesst sich
/// pruefen, ohne den Kopf zu verrenken.
enum UnitConverter {

    /// Faktor auf die Basiseinheit der jeweiligen Dimension.
    private static let factors: [String: (base: UnitCode, factor: Double)] = [
        // Laenge → M
        "M": (.meter, 1), "KM": (.meter, 1000), "CM": (.meter, 0.01),
        "MI": (.meter, 1609.344), "FT": (.meter, 0.3048), "IN": (.meter, 0.0254),
        // Masse → KG
        "KG": (.kilogram, 1), "G": (.kilogram, 0.001), "MG": (.kilogram, 1e-6),
        "UG": (.kilogram, 1e-9), "LB": (.kilogram, 0.45359237), "ST": (.kilogram, 6.35029318),
        // Zeit → S
        "S": (.second, 1), "MS": (.second, 0.001), "MIN": (.second, 60),
        "H": (.second, 3600), "D": (.second, 86400),
        // Energie → KCAL
        "KCAL": (.kilocalorie, 1), "KJ": (.kilocalorie, 0.239005736),
        // Volumen → L
        "L": (.liter, 1), "ML": (.liter, 0.001), "FLOZ": (.liter, 0.0295735296),
        // Geschwindigkeit → MPS
        "MPS": (.metersPerSecond, 1), "KMH": (.metersPerSecond, 1.0 / 3.6),
        "MPH": (.metersPerSecond, 0.44704),
        // Frequenzen: bpm, rpm und Atemzuege/min sind fachlich verschieden,
        // teilen sich aber die Zahl pro Minute. Getrennte Basen halten sie
        // auseinander – eine Trittfrequenz ist kein Puls.
        "BPM": (.beatsPerMinute, 1), "RPM": (.revolutionsPerMinute, 1),
        "BRPM": (.breathsPerMinute, 1),
        // Dimensionslos / direkt
        "NONE": (.none, 1), "CNT": (.count, 1), "PCT": (.percent, 1),
        "MMHG": (.millimeterOfMercury, 1), "MGDL": (.milligramPerDeciliter, 1),
        "W": (.watt, 1), "DB": (.decibel, 1), "IU": (.internationalUnit, 1),
        "MLKGMIN": (.milliliterPerKilogramMinute, 1), "IDX": (.index, 1),
        "SCORE": (.score, 1), "LPM": (.litersPerMinute, 1)
    ]

    /// Umrechnungen, die kein reiner Faktor sind.
    private static let offsets: [String: (from: UnitCode, to: UnitCode, convert: @Sendable (Double) -> Double)] = [
        "CEL>FAH": (.celsius, .fahrenheit, { $0 * 9 / 5 + 32 }),
        "FAH>CEL": (.fahrenheit, .celsius, { ($0 - 32) * 5 / 9 }),
        "MGDL>MMOLL": (.milligramPerDeciliter, .millimolePerLiter, { $0 / 18.0182 }),
        "MMOLL>MGDL": (.millimolePerLiter, .milligramPerDeciliter, { $0 * 18.0182 })
    ]

    enum ConversionError: Error, Equatable {
        case unknownUnit(UnitCode)
        case incompatible(from: UnitCode, to: UnitCode)
    }

    /// Wandelt einen Wert um. Gleiche Einheit → unveraendert.
    static func convert(_ value: Double, from source: UnitCode, to target: UnitCode) throws -> Double {
        if source == target { return value }
        if let direct = offsets["\(source.rawValue)>\(target.rawValue)"] {
            return direct.convert(value)
        }
        guard let sourceEntry = factors[source.rawValue] else {
            throw ConversionError.unknownUnit(source)
        }
        guard let targetEntry = factors[target.rawValue] else {
            throw ConversionError.unknownUnit(target)
        }
        guard sourceEntry.base == targetEntry.base else {
            throw ConversionError.incompatible(from: source, to: target)
        }
        return value * sourceEntry.factor / targetEntry.factor
    }

    /// Prueft, ob eine Umrechnung ueberhaupt moeglich waere.
    static func canConvert(from source: UnitCode, to target: UnitCode) -> Bool {
        (try? convert(1, from: source, to: target)) != nil
    }

    static func isKnown(_ unit: UnitCode) -> Bool {
        factors[unit.rawValue] != nil || unit == .celsius || unit == .fahrenheit
            || unit == .millimolePerLiter
    }
}
