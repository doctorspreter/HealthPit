//
//  ActivityGoals.swift
//  Healthpit
//
//  Ziele fuer Bewegung: frei zusammenstellbar aus Messwert und Zeitraum.
//  Bewusst eigene Ziele statt der aus Apple Health uebernommenen — die
//  Ringziele gibt Apple nicht als Lesetyp heraus. Was hier eingestellt wird,
//  steht kurz darauf als Entitaet in Home Assistant.
//
//  Zielwerte liegen wie alle Werte in HealthKit-Einheiten (metrisch). Erst die
//  Anzeige rechnet um, genau wie bei den Messwerten selbst.
//

import Foundation
import HealthKit
import SwiftUI

enum GoalPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case day, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return L10n.string("Täglich")
        case .week: return L10n.string("Wöchentlich")
        case .month: return L10n.string("Monatlich")
        case .year: return L10n.string("Jährlich")
        }
    }

    /// Kurzform fuer enge Stellen wie die Zielkarte.
    var shortTitle: String {
        switch self {
        case .day: return L10n.string("Tag")
        case .week: return L10n.string("Woche")
        case .month: return L10n.string("Monat")
        case .year: return L10n.string("Jahr")
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    /// Der laufende Zeitraum, in dem `date` liegt.
    func interval(containing date: Date = .now) -> DateInterval {
        let calendar = Calendar.healthApp
        guard let interval = calendar.dateInterval(of: calendarComponent, for: date) else {
            let start = calendar.startOfDay(for: date)
            return DateInterval(start: start, end: date)
        }
        return interval
    }
}

struct ActivityGoal: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    /// `HealthMetric.id` – der HealthKit-Bezeichner des Messwerts.
    var metricID: String
    var period: GoalPeriod
    /// Zielwert in HealthKit-Einheit.
    var target: Double
    /// Ob das Ziel auf der Aktivitaetsseite als Ring erscheint. Mehr als drei
    /// Ringe sind nicht mehr abzulesen, deshalb begrenzt der Speicher das.
    var showsAsRing: Bool = false

    var metric: HealthMetric? { HealthMetric.metric(id: metricID) }

    var title: String { metric?.title ?? metricID }

    var symbol: String { metric?.systemImage ?? "target" }

    /// Farbe des Rings. Die drei klassischen Ziele behalten ihre gewohnten
    /// Farben, alles Weitere folgt der Kategorie des Messwerts.
    var tint: Color {
        switch HKQuantityTypeIdentifier(rawValue: metricID) {
        case .activeEnergyBurned: return .pink
        case .appleExerciseTime: return .green
        case .stepCount: return .cyan
        case .distanceCycling: return .indigo
        case .distanceSwimming: return .teal
        default: return metric?.category.tint ?? .orange
        }
    }
}

enum ActivityGoalStore {
    nonisolated static let storageKey = "activityGoals.v2"
    nonisolated static let didChangeNotification = Notification.Name("HealthPitActivityGoalsDidChange")

    /// Hoechstzahl gleichzeitiger Ringe.
    nonisolated static let maximumRingCount = 3

    // MARK: Vorgabe

    /// Die drei klassischen Tagesziele. Sie stehen beim ersten Start bereit und
    /// lassen sich wie jedes andere Ziel aendern oder loeschen.
    nonisolated static var defaultGoals: [ActivityGoal] {
        [
            ActivityGoal(metricID: HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                         period: .day,
                         target: 500,
                         showsAsRing: true),
            ActivityGoal(metricID: HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
                         period: .day,
                         target: 30,
                         showsAsRing: true),
            ActivityGoal(metricID: HKQuantityTypeIdentifier.stepCount.rawValue,
                         period: .day,
                         target: 10_000,
                         showsAsRing: true),
        ]
    }

    /// Messwerte, die sich sinnvoll als Ziel eignen: alles, was sich ueber
    /// einen Zeitraum aufsummieren laesst, plus die Bewegungsminuten.
    nonisolated static var selectableMetrics: [HealthMetric] {
        HealthMetric.all.filter { $0.aggregation == .cumulativeSum }
    }

    // MARK: Lesen und Schreiben

    nonisolated static func goals(defaults: UserDefaults = .standard) -> [ActivityGoal] {
        guard let data = defaults.data(forKey: storageKey) else { return defaultGoals }
        guard let stored = try? JSONDecoder().decode([ActivityGoal].self, from: data) else {
            return defaultGoals
        }
        return stored
    }

    nonisolated static func save(_ goals: [ActivityGoal], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    nonisolated static func upsert(_ goal: ActivityGoal, defaults: UserDefaults = .standard) {
        var all = goals(defaults: defaults)
        if let index = all.firstIndex(where: { $0.id == goal.id }) {
            all[index] = goal
        } else {
            all.append(goal)
        }
        save(limitRings(all, changed: goal.id), defaults: defaults)
    }

    nonisolated static func delete(_ goal: ActivityGoal, defaults: UserDefaults = .standard) {
        save(goals(defaults: defaults).filter { $0.id != goal.id }, defaults: defaults)
    }

    nonisolated static func resetToDefaults(defaults: UserDefaults = .standard) {
        save(defaultGoals, defaults: defaults)
    }

    /// Sorgt dafuer, dass nie mehr Ringe eingeschaltet sind als darstellbar —
    /// das zuletzt geaenderte Ziel behaelt seinen Ring, aeltere weichen.
    nonisolated private static func limitRings(_ goals: [ActivityGoal],
                                               changed: UUID) -> [ActivityGoal] {
        var result = goals
        var ringIDs = result.filter(\.showsAsRing).map(\.id)
        guard ringIDs.count > maximumRingCount else { return result }
        ringIDs.removeAll { $0 == changed }
        let excess = ringIDs.prefix(ringIDs.count - (maximumRingCount - 1))
        for id in excess {
            if let index = result.firstIndex(where: { $0.id == id }) {
                result[index].showsAsRing = false
            }
        }
        return result
    }

    // MARK: Uebertragung nach Home Assistant

    /// Stabile Kennung: sie haengt an Messwert und Zeitraum, nicht an der
    /// zufaelligen UUID — sonst entstuenden drueben bei jeder Aenderung neue
    /// Entitaeten.
    nonisolated static func syncID(for goal: ActivityGoal) -> String {
        let metricPart = goal.metric?.bridgeID ?? goal.metricID.lowercased()
        return "goal_\(metricPart)_\(goal.period.rawValue)"
    }

    nonisolated static func syncTitle(for goal: ActivityGoal) -> String {
        L10n.format("Ziel %@ (%@)", goal.title, goal.period.shortTitle)
    }

    /// Voreinstellung fuer ein neues Ziel: ein runder Wert in der Naehe des
    /// Ueblichen, damit der Regler nicht bei null beginnt.
    nonisolated static func suggestedTarget(for metric: HealthMetric,
                                            period: GoalPeriod) -> Double {
        let daily: Double
        switch metric.quantityTypeIdentifier {
        case .stepCount: daily = 10_000
        case .activeEnergyBurned: daily = 500
        case .appleExerciseTime: daily = 30
        // Werte in HealthKit-Einheit: Gehen/Radfahren in Kilometern,
        // Schwimmen in Metern.
        case .distanceWalkingRunning: daily = 5
        case .distanceCycling: daily = 10
        case .distanceSwimming: daily = 500
        case .distanceWheelchair: daily = 5
        case .distanceDownhillSnowSports: daily = 10
        case .flightsClimbed: daily = 10
        case .swimmingStrokeCount: daily = 500
        case .pushCount: daily = 500
        case .basalEnergyBurned: daily = 1_600
        case .appleStandTime: daily = 240
        default: daily = 1
        }
        switch period {
        case .day: return daily
        case .week: return daily * 5
        case .month: return daily * 20
        case .year: return daily * 240
        }
    }

    /// Spannweite und Schrittweite fuer den Regler, in Anzeigeeinheit.
    nonisolated static func editorRange(for metric: HealthMetric,
                                        period: GoalPeriod) -> (range: ClosedRange<Double>, step: Double) {
        let suggestion = metric.displayValue(suggestedTarget(for: metric, period: period))
        let upper = max(suggestion * 4, suggestion + 10)
        let step = editorStep(for: suggestion)
        let lower = step
        return (lower...max(upper, lower + step), step)
    }

    nonisolated private static func editorStep(for suggestion: Double) -> Double {
        switch suggestion {
        case ..<20: return 1
        case ..<200: return 5
        case ..<2_000: return 50
        case ..<20_000: return 250
        default: return 1_000
        }
    }
}
