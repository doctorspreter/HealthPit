//
//  HealthKitManager+Goals.swift
//  Healthpit
//
//  Erfuellungsgrad der Ziele. Eine Stelle fuer beides: die Ringe auf der
//  Aktivitaetsseite und die Werte, die nach Home Assistant gehen.
//

import Foundation

extension HealthKitManager {

    /// Der bislang erreichte Wert eines Ziels im laufenden Zeitraum,
    /// in HealthKit-Einheit.
    func progressValue(for goal: ActivityGoal, referenceDate now: Date = .now) async -> Double {
        guard let metric = goal.metric else { return 0 }
        // Der Tag hat eine eigene, guenstigere Abfrage — sie liefert dieselbe
        // Summe, ohne den Umweg ueber eine Sammelabfrage.
        if goal.period == .day {
            return (try? await currentValue(for: metric, referenceDate: now)) ?? 0
        }

        let interval = goal.period.interval(containing: now)
        let clipped = DateInterval(start: interval.start, end: min(interval.end, now))
        guard clipped.duration > 0 else { return 0 }
        let statistics = (try? await fetchStatistics(for: metric,
                                                     interval: clipped,
                                                     anchorDate: clipped.start,
                                                     bucket: DateComponents(day: 1))) ?? []
        let values = statistics.map(\.value)
        guard !values.isEmpty else { return 0 }
        switch metric.aggregation {
        case .cumulativeSum:
            return values.reduce(0, +)
        case .discreteAverage:
            return values.reduce(0, +) / Double(values.count)
        }
    }

    /// Erreichte Werte fuer mehrere Ziele auf einmal.
    func progressValues(for goals: [ActivityGoal],
                        referenceDate now: Date = .now) async -> [UUID: Double] {
        var out: [UUID: Double] = [:]
        for goal in goals {
            out[goal.id] = await progressValue(for: goal, referenceDate: now)
        }
        return out
    }
}
