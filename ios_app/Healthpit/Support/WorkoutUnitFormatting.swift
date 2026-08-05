//
//  WorkoutUnitFormatting.swift
//  Healthpit
//
//  Einheiten fuer den Workout-Bereich – Distanz, Tempo, Gewicht, Hoehe.
//
//  Workouts speichern und synchronisieren durchgaengig metrisch (`distanceKm`,
//  `weightKg`). Umgerechnet wird nur fuer die Anzeige, an dieser einen Stelle.
//  Vorher stand `String(format: "%.1f km", …)` an einem Dutzend Stellen
//  verstreut, was jede Einheitenumstellung unmoeglich gemacht hat.
//

import Foundation

enum WorkoutUnits {

    private static let kmPerMile = 1.609344
    private static let feetPerMeter = 3.280840
    private static let poundsPerKilogram = 2.204623

    static var isImperial: Bool { UnitPreference.active == .imperial }

    // MARK: Distanz

    static var distanceSymbol: String { isImperial ? "mi" : "km" }

    /// Distanz in der Anzeige-Einheit (Eingabe immer in km).
    static func distanceValue(km: Double) -> Double {
        isImperial ? km / kmPerMile : km
    }

    /// Umkehrung – fuer Eingabefelder, die in der Anzeige-Einheit erfasst werden.
    static func kilometers(fromDisplayDistance value: Double) -> Double {
        isImperial ? value * kmPerMile : value
    }

    static func distance(km: Double, fractionDigits: Int = 1) -> String {
        String(format: "%.\(fractionDigits)f %@", distanceValue(km: km), distanceSymbol)
    }

    // MARK: Tempo und Geschwindigkeit

    static var speedSymbol: String { isImperial ? "mph" : "km/h" }

    static func speedValue(kmh: Double) -> Double {
        isImperial ? kmh / kmPerMile : kmh
    }

    static func speed(kmh: Double) -> String {
        String(format: "%.1f %@", speedValue(kmh: kmh), speedSymbol)
    }

    static var paceSymbol: String { isImperial ? "/mi" : "/km" }

    /// Minuten:Sekunden je Kilometer bzw. je Meile.
    static func pace(secondsPerKilometer seconds: Int) -> String {
        let total = isImperial ? Int((Double(seconds) * kmPerMile).rounded()) : seconds
        return "\(total / 60):" + String(format: "%02d %@", total % 60, paceSymbol)
    }

    /// Tempo aus Distanz und Dauer – nil, wenn eines davon fehlt.
    static func pace(km: Double, duration: TimeInterval) -> String? {
        guard km > 0, duration > 0 else { return nil }
        return pace(secondsPerKilometer: Int(duration / km))
    }

    // MARK: Gewicht

    static var weightSymbol: String { isImperial ? "lb" : "kg" }

    static func weightValue(kg: Double) -> Double {
        isImperial ? kg * poundsPerKilogram : kg
    }

    static func kilograms(fromDisplayWeight value: Double) -> Double {
        isImperial ? value / poundsPerKilogram : value
    }

    /// Gewicht mit Tonnen-/Kurztonnen-Sprung bei grossen Volumina.
    static func weight(kg: Double) -> String {
        let value = weightValue(kg: kg)
        if isImperial {
            return value >= 2000
                ? String(format: "%.1f %@", value / 2000, L10n.string("t (US)"))
                : String(format: "%.0f lb", value)
        }
        return value >= 1000
            ? String(format: "%.1f t", value / 1000)
            : String(format: "%.0f kg", value)
    }

    // MARK: Hoehe

    static var elevationSymbol: String { isImperial ? "ft" : "m" }

    static func elevationValue(meters: Double) -> Double {
        isImperial ? meters * feetPerMeter : meters
    }

    static func elevation(meters: Double) -> String {
        String(format: "%.0f %@", elevationValue(meters: meters), elevationSymbol)
    }
}
