//
//  MeasurementSystem.swift
//  Healthpit
//
//  Welche Maßeinheiten die Oberflaeche zeigt.
//
//  Betrifft ausschliesslich die Anzeige. Gelesen, zwischengespeichert und an
//  die Bridge geschickt wird weiterhin metrisch – ein Home-Assistant-Sensor,
//  dessen Einheit sich mit einer App-Einstellung aendert, verliert seine
//  Historie.
//

import Foundation
import HealthKit

/// Das System, in dem Werte angezeigt werden.
enum MeasurementSystem: String, Sendable {
    case metric
    case imperial
}

/// Die Einstellung, die der Anwender waehlt.
enum MeasurementSystemSetting: String, CaseIterable, Identifiable, Sendable {
    /// Folgt dem, was in Apple Health eingestellt ist.
    case automatic
    case metric
    case imperial

    nonisolated static let storageKey = "measurementSystem"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return L10n.string("Wie in Apple Health")
        case .metric:    return L10n.string("Metrisch (km, kg, °C)")
        case .imperial:  return L10n.string("Imperial (mi, lb, °F)")
        }
    }
}

enum UnitPreference {

    /// Was Apple Health zuletzt als Vorliebe gemeldet hat.
    ///
    /// Gepuffert, weil `preferredUnits(for:)` asynchron ist, die Formatierung
    /// aber synchron aus Dutzenden von Views heraus laeuft.
    private nonisolated static let resolvedKey = "measurementSystemResolved"

    nonisolated static var setting: MeasurementSystemSetting {
        UserDefaults.standard.string(forKey: MeasurementSystemSetting.storageKey)
            .flatMap(MeasurementSystemSetting.init(rawValue:)) ?? .automatic
    }

    /// Das aktuell gueltige System.
    nonisolated static var active: MeasurementSystem {
        switch setting {
        case .metric:   return .metric
        case .imperial: return .imperial
        case .automatic:
            guard let raw = UserDefaults.standard.string(forKey: resolvedKey),
                  let system = MeasurementSystem(rawValue: raw) else {
                return localeDefault
            }
            return system
        }
    }

    /// Fallback, solange Apple Health noch nicht gefragt wurde.
    nonisolated static var localeDefault: MeasurementSystem {
        Locale.autoupdatingCurrent.measurementSystem == .metric ? .metric : .imperial
    }

    /// Uebernimmt die in der Health-App eingestellten Einheiten.
    ///
    /// Apple fuehrt die Vorliebe pro Datentyp; imperial erkennt man daran, dass
    /// Gewicht in Pfund/Stone, Groesse in Zoll oder Distanz in Meilen kommt.
    /// Ein einziger imperialer Typ genuegt – wer sein Gewicht in lb pflegt,
    /// will keine Kilometer daneben.
    static func refreshFromAppleHealth(store: HKHealthStore) async {
        let types: Set<HKQuantityType> = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKQuantityType(.distanceWalkingRunning),
        ]
        guard let preferred = try? await store.preferredUnits(for: types) else { return }

        let imperialUnits: Set<HKUnit> = [
            .pound(), .stone(), .inch(), .foot(), .yard(), .mile(),
        ]
        let isImperial = preferred.values.contains { imperialUnits.contains($0) }

        UserDefaults.standard.set(isImperial ? MeasurementSystem.imperial.rawValue
                                             : MeasurementSystem.metric.rawValue,
                                  forKey: resolvedKey)
    }
}

/// Wie ein gespeicherter Wert in die Anzeige-Einheit kommt.
///
/// Bewusst kein reiner Faktor: Temperatur ist affin (×9/5 + 32).
enum UnitConversion: Sendable {
    case identity
    case factor(Double)
    case celsiusToFahrenheit

    func apply(_ value: Double) -> Double {
        switch self {
        case .identity:             return value
        case .factor(let f):        return value * f
        case .celsiusToFahrenheit:  return value * 9 / 5 + 32
        }
    }

    /// Rueckweg – fuer Schwellwerte, die in HealthKit-Einheiten definiert sind.
    func invert(_ value: Double) -> Double {
        switch self {
        case .identity:             return value
        case .factor(let f):        return f == 0 ? value : value / f
        case .celsiusToFahrenheit:  return (value - 32) * 5 / 9
        }
    }
}

/// Einheit, Umrechnung und Nachkommastellen fuer die Anzeige einer Metrik.
struct MetricDisplayUnit: Sendable {
    let symbolKey: String
    let conversion: UnitConversion
    let fractionDigits: Int

    var symbol: String { L10n.string(symbolKey) }
}
