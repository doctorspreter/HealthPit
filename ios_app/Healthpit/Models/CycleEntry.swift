//
//  CycleEntry.swift
//  Healthpit
//
//  Zyklusdaten: Blutungstage, daraus abgeleitete Zyklen und die uebrigen
//  Ereignisse der Reproduktionsgesundheit.
//
//  Anders als die Mengen-Metriken sind das HKCategoryType-Werte – sie haben
//  keine Einheit, sondern eine Stufe. Deshalb ein eigenes Modell, so wie es
//  Schlaf ebenfalls hat.
//

import Foundation
import HealthKit

/// Blutungsstaerke eines Tages.
///
/// Bildet `HKCategoryValueVaginalBleeding` ab (frueher
/// `HKCategoryValueMenstrualFlow`); die Rohwerte sind zwischen beiden gleich.
enum MenstrualFlow: Int, CaseIterable, Identifiable, Codable, Sendable {
    case unspecified = 1
    case light = 2
    case medium = 3
    case heavy = 4
    case none = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .unspecified: return L10n.string("Ohne Angabe")
        case .light:       return L10n.string("Leicht")
        case .medium:      return L10n.string("Mittel")
        case .heavy:       return L10n.string("Stark")
        case .none:        return L10n.string("Keine Blutung")
        }
    }

    /// Wie viele Tropfen die Stufe in der Uebersicht bekommt.
    var intensity: Int {
        switch self {
        case .none:        return 0
        case .unspecified: return 1
        case .light:       return 1
        case .medium:      return 2
        case .heavy:       return 3
        }
    }

    /// Zaehlt der Tag als Blutungstag?
    var isBleeding: Bool { self != .none }

    /// Die Stufen, die zur Eingabe angeboten werden – ohne "ohne Angabe",
    /// das entsteht nur beim Import aus anderen Apps.
    static var selectable: [MenstrualFlow] { [.none, .light, .medium, .heavy] }
}

/// Ein einzelner erfasster Zyklustag.
struct CycleDayEntry: Identifiable, Hashable, Sendable {
    /// UUID des HealthKit-Samples – noetig, um denselben Tag zu ersetzen.
    let id: UUID
    let date: Date
    let flow: MenstrualFlow
    /// Von Apple Health gefuehrtes Kennzeichen "erster Tag des Zyklus".
    let isCycleStart: Bool
    /// Von Healthpit geschrieben? Nur eigene Eintraege duerfen geaendert werden.
    let isOwnEntry: Bool
}

/// Ein aus den Blutungstagen abgeleiteter Zyklus.
struct MenstrualCycle: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Erster Blutungstag.
    let start: Date
    /// Letzter Blutungstag dieser Periode.
    let periodEnd: Date
    /// Beginn des Folgezyklus – nil beim laufenden Zyklus.
    let nextStart: Date?
    /// Blutungstage in dieser Periode.
    let bleedingDays: Int

    /// Zykluslaenge in Tagen – nur beim abgeschlossenen Zyklus bekannt.
    var lengthInDays: Int? {
        guard let nextStart else { return nil }
        return Calendar.healthApp.dateComponents([.day], from: start, to: nextStart).day
    }

    /// Dauer der Periode in Tagen (erster bis letzter Blutungstag).
    var periodLengthInDays: Int {
        (Calendar.healthApp.dateComponents([.day], from: start, to: periodEnd).day ?? 0) + 1
    }

    var isOngoing: Bool { nextStart == nil }
}

/// Weitere Ereignisse der Reproduktionsgesundheit, die Healthpit anzeigt.
enum CycleEventKind: String, CaseIterable, Identifiable, Sendable {
    case intermenstrualBleeding
    case ovulationTest
    case cervicalMucus
    case sexualActivity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intermenstrualBleeding: return L10n.string("Zwischenblutung")
        case .ovulationTest:          return L10n.string("Ovulationstest")
        case .cervicalMucus:          return L10n.string("Zervixschleim")
        case .sexualActivity:         return L10n.string("Sexuelle Aktivität")
        }
    }

    var systemImage: String {
        switch self {
        case .intermenstrualBleeding: return "drop"
        case .ovulationTest:          return "testtube.2"
        case .cervicalMucus:          return "drop.triangle"
        case .sexualActivity:         return "heart"
        }
    }

    var categoryIdentifier: HKCategoryTypeIdentifier {
        switch self {
        case .intermenstrualBleeding: return .intermenstrualBleeding
        case .ovulationTest:          return .ovulationTestResult
        case .cervicalMucus:          return .cervicalMucusQuality
        case .sexualActivity:         return .sexualActivity
        }
    }

    /// Klartext fuer den Rohwert des Samples.
    func valueTitle(_ rawValue: Int) -> String {
        switch self {
        case .intermenstrualBleeding, .sexualActivity:
            return title
        case .ovulationTest:
            switch HKCategoryValueOvulationTestResult(rawValue: rawValue) {
            case .negative:                 return L10n.string("Negativ")
            case .luteinizingHormoneSurge:  return L10n.string("LH-Anstieg")
            case .indeterminate:            return L10n.string("Nicht eindeutig")
            case .estrogenSurge:            return L10n.string("Östrogen-Anstieg")
            default:                        return L10n.string("Ohne Angabe")
            }
        case .cervicalMucus:
            switch HKCategoryValueCervicalMucusQuality(rawValue: rawValue) {
            case .dry:      return L10n.string("Trocken")
            case .sticky:   return L10n.string("Klebrig")
            case .creamy:   return L10n.string("Cremig")
            case .watery:   return L10n.string("Wässrig")
            case .eggWhite: return L10n.string("Eiweißartig")
            default:        return L10n.string("Ohne Angabe")
            }
        }
    }
}

/// Ein einzelnes Ereignis mit Datum und Auspraegung.
struct CycleEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: CycleEventKind
    let date: Date
    let rawValue: Int

    var valueTitle: String { kind.valueTitle(rawValue) }
}

/// Alles, was die Zyklusansicht braucht – in einem Rutsch geladen.
struct CycleOverview: Sendable {
    var days: [CycleDayEntry] = []
    var cycles: [MenstrualCycle] = []
    var events: [CycleEvent] = []

    var hasData: Bool { !days.isEmpty || !events.isEmpty }

    /// Der laufende oder zuletzt begonnene Zyklus.
    var currentCycle: MenstrualCycle? { cycles.last }

    /// Tag im laufenden Zyklus, 1-basiert.
    var currentCycleDay: Int? {
        guard let start = currentCycle?.start else { return nil }
        let today = Calendar.healthApp.startOfDay(for: Date())
        guard let days = Calendar.healthApp.dateComponents([.day], from: start, to: today).day,
              days >= 0 else {
            return nil
        }
        return days + 1
    }

    /// Mittlere Zykluslaenge der abgeschlossenen Zyklen.
    var averageCycleLength: Int? {
        let lengths = cycles.compactMap(\.lengthInDays)
        guard !lengths.isEmpty else { return nil }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    /// Mittlere Dauer der Periode.
    var averagePeriodLength: Int? {
        // Der laufende Zyklus zaehlt nicht mit – seine Periode kann noch andauern.
        let finished = cycles.filter { !$0.isOngoing }
        guard !finished.isEmpty else { return nil }
        let total = finished.map(\.periodLengthInDays).reduce(0, +)
        return Int((Double(total) / Double(finished.count)).rounded())
    }

    /// Der Eintrag zu einem Tag, falls vorhanden.
    func entry(on date: Date) -> CycleDayEntry? {
        let day = Calendar.healthApp.startOfDay(for: date)
        return days.first { Calendar.healthApp.startOfDay(for: $0.date) == day }
    }
}
