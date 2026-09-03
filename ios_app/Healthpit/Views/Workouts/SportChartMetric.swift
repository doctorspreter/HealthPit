//
//  SportChartMetric.swift
//  Healthpit
//
//  Welche Kennzahl das Diagramm einer Sportart zeigt.
//
//  Mehrere gleichzeitig lassen sich nur vergleichen, wenn jede auf ihr
//  eigenes Maximum bezogen wird — Kilometer und Kalorien auf derselben Achse
//  ergaeben ein Bild, in dem die Strecke immer flach am Boden liegt. Das
//  Diagramm zeigt deshalb den Verlauf, nicht die Hoehe; die echten Werte
//  stehen beim Antippen darunter.
//

import SwiftUI

enum SportChartMetric: String, CaseIterable, Identifiable, Sendable {
    case duration
    case distance
    case calories
    case pace
    case heartRate
    case volume
    case sets
    case reps

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .duration:  return "Dauer"
        case .distance:  return "Distanz"
        case .calories:  return "Kalorien"
        case .pace:      return "Ø Tempo"
        case .heartRate: return "Ø Puls"
        case .volume:    return "Volumen"
        case .sets:      return "Sätze"
        case .reps:      return "Wiederholungen"
        }
    }

    var color: Color {
        switch self {
        case .duration:  return .green
        case .distance:  return .blue
        case .calories:  return .orange
        case .pace:      return .purple
        case .heartRate: return .pink
        case .volume:    return .brown
        case .sets:      return .teal
        case .reps:      return .indigo
        }
    }

    /// Der Tageswert dieser Kennzahl. `nil`, wenn an dem Tag nichts dazu
    /// erfasst wurde — dann faellt der Punkt aus, statt als Null zu erscheinen.
    func value(for workouts: [UnifiedWorkout]) -> Double? {
        switch self {
        case .duration:
            let seconds = workouts.map(\.duration).reduce(0, +)
            return seconds > 0 ? seconds / 60 : nil
        case .distance:
            let km = workouts.compactMap(\.distanceKm).reduce(0, +)
            return km > 0 ? WorkoutUnits.distanceValue(km: km) : nil
        case .calories:
            let kcal = workouts.compactMap(\.energyKcal).reduce(0, +)
            return kcal > 0 ? kcal : nil
        case .pace:
            let km = workouts.compactMap(\.distanceKm).reduce(0, +)
            let seconds = workouts.filter { ($0.distanceKm ?? 0) > 0 }.map(\.duration).reduce(0, +)
            guard km > 0, seconds > 0 else { return nil }
            // Minuten je Kilometer bzw. je Meile, damit die Kurve zur
            // Anzeigeeinheit passt.
            return seconds / 60 / WorkoutUnits.distanceValue(km: km)
        case .heartRate:
            let rates = workouts.compactMap(\.averageHeartRate).filter { $0 > 0 }
            guard !rates.isEmpty else { return nil }
            return rates.reduce(0, +) / Double(rates.count)
        case .volume:
            let kg = workouts.compactMap(\.volumeKg).reduce(0, +)
            return kg > 0 ? WorkoutUnits.weightValue(kg: kg) : nil
        case .sets:
            let count = workouts.compactMap(\.setCount).reduce(0, +)
            return count > 0 ? Double(count) : nil
        case .reps:
            let count = workouts.compactMap(\.repCount).reduce(0, +)
            return count > 0 ? Double(count) : nil
        }
    }

    /// Der Wert, wie er beim Antippen dasteht — mit Einheit.
    func formatted(_ value: Double) -> String {
        switch self {
        case .duration:
            return formatWorkoutDuration(value * 60)
        case .distance:
            return String(format: "%.2f %@", value, WorkoutUnits.distanceSymbol)
        case .calories:
            return "\(Int(value.rounded())) kcal"
        case .pace:
            let seconds = Int((value * 60).rounded())
            return "\(seconds / 60):" + String(format: "%02d %@", seconds % 60, WorkoutUnits.paceSymbol)
        case .heartRate:
            return "\(Int(value.rounded())) bpm"
        case .volume:
            return String(format: "%.0f %@", value, WorkoutUnits.weightSymbol)
        case .sets, .reps:
            return "\(Int(value.rounded()))"
        }
    }

    /// Kennzahlen, zu denen im Bestand ueberhaupt Werte stehen.
    static func available(in workouts: [UnifiedWorkout]) -> [SportChartMetric] {
        allCases.filter { $0.value(for: workouts) != nil }
    }

    /// Hoechstens drei auf einmal — mehr Kurven liest niemand mehr
    /// auseinander, erst recht nicht ohne gemeinsame Achse.
    static let maximumSelection = 3
}

/// Ein Tageswert einer Kennzahl, roh und auf ihr Maximum bezogen.
struct SportChartSample: Identifiable {
    let metric: SportChartMetric
    let day: Date
    let value: Double
    /// 0…1, bezogen auf das Maximum dieser Kennzahl im Zeitraum.
    let relative: Double

    var id: String { "\(metric.rawValue)-\(day.timeIntervalSince1970)" }
}
