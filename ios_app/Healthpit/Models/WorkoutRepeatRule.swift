//
//  WorkoutRepeatRule.swift
//  Healthpit
//
//  Wiederholungsrhythmus fuer manuell angelegte Trainings.
//

import Foundation

/// Wie oft sich ein manuell angelegtes Training wiederholt.
///
/// Die Termine werden beim Speichern einmal ausgerechnet und als normale
/// Workouts abgelegt. Das ist absichtlich so: ein Hintergrunddienst, der spaeter
/// Eintraege nachtraegt, wuerde Trainings erfinden, die nie stattgefunden haben.
enum WorkoutRepeatRule: String, CaseIterable, Identifiable, Sendable {
    case none
    case daily
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L10n.string("Einmalig")
        case .daily: return L10n.string("Täglich")
        case .weekly: return L10n.string("Wöchentlich")
        case .biweekly: return L10n.string("Alle 2 Wochen")
        case .monthly: return L10n.string("Monatlich")
        }
    }

    /// Abstand zweier Termine als Kalenderkomponenten.
    var step: DateComponents? {
        switch self {
        case .none: return nil
        case .daily: return DateComponents(day: 1)
        case .weekly: return DateComponents(weekOfYear: 1)
        case .biweekly: return DateComponents(weekOfYear: 2)
        case .monthly: return DateComponents(month: 1)
        }
    }

    /// Ein sinnvolles Enddatum, wenn der Anwender das Feld noch nicht angefasst hat.
    func defaultEnd(from start: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .none: return start
        case .daily: return calendar.date(byAdding: .weekOfYear, value: 4, to: start) ?? start
        case .weekly, .biweekly: return calendar.date(byAdding: .month, value: 3, to: start) ?? start
        case .monthly: return calendar.date(byAdding: .year, value: 1, to: start) ?? start
        }
    }

    /// Obergrenze, damit ein weit entferntes Enddatum nicht tausende Eintraege erzeugt.
    static let maximumOccurrences = 200

    /// Alle Starttermine von `start` bis einschliesslich `end`.
    func occurrences(from start: Date, until end: Date, calendar: Calendar = .current) -> [Date] {
        guard let step else { return [start] }
        guard end >= start else { return [start] }

        var dates = [start]
        var current = start
        while dates.count < Self.maximumOccurrences {
            guard let next = calendar.date(byAdding: step, to: current) else { break }
            // Der letzte Termin darf auf das Enddatum fallen, aber nicht darueber
            // hinaus; verglichen wird auf den Tag genau, damit eine spaetere
            // Uhrzeit den letzten Termin nicht verschluckt.
            guard calendar.startOfDay(for: next) <= calendar.startOfDay(for: end) else { break }
            dates.append(next)
            current = next
        }
        return dates
    }
}
