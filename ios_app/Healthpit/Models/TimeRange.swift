//
//  TimeRange.swift
//  Healthpit
//
//  Die vier Zeiträume aus PLAN.md (Tag/Woche/Monat/Jahr). Liefert sowohl das
//  abzufragende Datumsintervall als auch die Bucket-Größe für die
//  HKStatisticsCollectionQuery (Stunde/Tag/Monat). Damit ist die Aggregation
//  zentral definiert und in Manager wie UI identisch nutzbar.
//

import Foundation

extension Calendar {
    nonisolated static var healthApp: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // Systemsprache: Wochentagsnamen und Datumsangaben richten sich nach
        // dem iPhone, nicht nach der in der App gewaehlten Sprache.
        calendar.locale = .autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Der Monatsanfang, auf den ein Kalenderraster aufsetzt.
    nonisolated func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}

/// Vordefinierter Auswertungszeitraum für Diagramme und Abfragen.
enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:   return L10n.string("Tag")
        case .week:  return L10n.string("Woche")
        case .month: return L10n.string("Monat")
        case .year:  return L10n.string("Jahr")
        }
    }

    /// Das abzufragende Datumsintervall, relativ zu `now`.
    nonisolated func dateInterval(referenceDate now: Date = .now,
                                  calendar: Calendar = .healthApp) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)

        switch self {
        case .day:
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            return DateInterval(start: startOfToday, end: end)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
                ?? DateInterval(start: startOfToday, end: calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
                ?? DateInterval(start: startOfToday, end: calendar.date(byAdding: .month, value: 1, to: startOfToday) ?? now)
        case .year:
            let year = calendar.component(.year, from: now)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? startOfToday
            let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
                ?? calendar.date(byAdding: .year, value: 1, to: start)
                ?? now
            return DateInterval(start: start, end: end)
        }
    }

    /// Größe eines Diagramm-Balkens / einer Aggregationsstufe.
    nonisolated var bucketComponents: DateComponents {
        switch self {
        case .day:   return DateComponents(hour: 1)
        case .week:  return DateComponents(day: 1)
        case .month: return DateComponents(day: 1)
        case .year:  return DateComponents(month: 1)
        }
    }

    /// Sinnvoller Ankerpunkt für die Collection-Query.
    nonisolated func anchorDate(referenceDate now: Date = .now, calendar: Calendar = .healthApp) -> Date {
        calendar.startOfDay(for: dateInterval(referenceDate: now, calendar: calendar).start)
    }

    /// Zeiteinheit eines Diagramm-Balkens (für Swift Charts `.value(..., unit:)`).
    nonisolated var chartComponent: Calendar.Component {
        switch self {
        case .day:           return .hour
        case .week, .month:  return .day
        case .year:          return .month
        }
    }
}
