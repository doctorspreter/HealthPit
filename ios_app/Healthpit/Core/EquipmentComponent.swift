//
//  EquipmentComponent.swift
//  HealthPitCore
//
//  Was an einem Ausruestungsstueck gewartet oder getauscht wird.
//
//  Ein Fahrrad tauscht man nicht aus, wenn die Kette 3000 km hat — man
//  tauscht die Kette. Deshalb haengt an einem Stueck eine Liste von Teilen,
//  jedes mit eigenem Intervall und eigenem „zuletzt gemacht".
//
//  Die Vorschlaege unten sind Startpunkte, keine Vorschrift: jedes Teil
//  laesst sich im Intervall aendern, und ueber `custom` mit freiem Namen
//  laesst sich alles anlegen, woran hier niemand gedacht hat.
//

import Foundation

/// Ob ein Teil ersetzt oder nur gewartet wird. Der Unterschied steht in der
/// Oberflaeche: „Kette tauschen" liest sich anders als „Kette oelen".
enum ComponentAction: String, CaseIterable, Identifiable, Sendable, Codable {
    case replace = "REPLACE"
    case service = "SERVICE"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .replace: return "Tauschen"
        case .service: return "Warten"
        }
    }
}

enum ComponentKind: String, CaseIterable, Identifiable, Sendable, Codable {
    // Fahrrad
    case chain = "CHAIN"
    case cassette = "CASSETTE"
    case brakePads = "BRAKE_PADS"
    case tyres = "TYRES"
    case cables = "CABLES"
    case chainLube = "CHAIN_LUBE"
    case bikeService = "BIKE_SERVICE"
    // Schuhe
    case insoles = "INSOLES"
    case resole = "RESOLE"
    case laces = "LACES"
    // Allgemein
    case cleaning = "CLEANING"
    case inspection = "INSPECTION"
    /// Freier Name – hierfuer steht `Component.name`.
    case custom = "CUSTOM"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .chain:       return "Kette"
        case .cassette:    return "Kassette"
        case .brakePads:   return "Bremsbeläge"
        case .tyres:       return "Reifen"
        case .cables:      return "Züge"
        case .chainLube:   return "Kette ölen"
        case .bikeService: return "Inspektion"
        case .insoles:     return "Einlagen"
        case .resole:      return "Neubesohlung"
        case .laces:       return "Schnürsenkel"
        case .cleaning:    return "Reinigung"
        case .inspection:  return "Durchsicht"
        case .custom:      return "Eigenes"
        }
    }

    var systemImage: String {
        switch self {
        case .chain, .cassette:  return "link"
        case .brakePads:         return "hand.raised"
        case .tyres:             return "circle.circle"
        case .cables:            return "cable.connector"
        case .chainLube:         return "drop"
        case .bikeService,
             .inspection:        return "wrench.and.screwdriver"
        case .insoles, .resole:  return "shoe"
        case .laces:             return "scribble"
        case .cleaning:          return "sparkles"
        case .custom:            return "plus.circle"
        }
    }

    var defaultAction: ComponentAction {
        switch self {
        case .chainLube, .bikeService, .cleaning, .inspection: return .service
        default: return .replace
        }
    }

    /// Uebliches Intervall in Kilometern. `nil` heisst: laeuft nach Zeit.
    var suggestedKm: Double? {
        switch self {
        case .chain:      return 3000
        case .cassette:   return 9000
        case .brakePads:  return 2000
        case .tyres:      return 4000
        case .cables:     return 6000
        case .chainLube:  return 300
        case .insoles:    return 500
        case .resole:     return 200
        default:          return nil
        }
    }

    /// Uebliches Intervall in Tagen. `nil` heisst: laeuft nach Strecke.
    var suggestedDays: Int? {
        switch self {
        case .bikeService, .inspection: return 365
        case .cleaning:                 return 30
        case .laces:                    return 365
        default:                        return nil
        }
    }

    /// Was an dieser Art Ausruestung ueblicherweise haengt – als Vorschlag
    /// beim Anlegen, nicht als abgeschlossene Liste.
    static func suggestions(for kind: EquipmentKind) -> [ComponentKind] {
        switch kind {
        case .bike:
            return [.chain, .brakePads, .tyres, .cassette, .cables, .chainLube, .bikeService]
        case .indoorBike:
            return [.chainLube, .inspection, .cleaning]
        case .runningShoes, .walkingShoes:
            return [.insoles, .laces]
        case .climbingShoes:
            return [.resole]
        case .swimGear, .mat:
            return [.cleaning]
        case .other:
            return [.inspection, .cleaning]
        }
    }
}

/// Ein Teil an einem Ausruestungsstueck.
struct EquipmentComponent: Identifiable, Hashable, Sendable {
    let id: String
    var equipmentID: String
    var kind: ComponentKind
    /// Nur bei `.custom` gefuellt; sonst steht der Name in `kind`.
    var name: String
    var action: ComponentAction
    /// Faellig nach so vielen Kilometern seit dem letzten Mal.
    var intervalKm: Double?
    /// Faellig nach so vielen Tagen seit dem letzten Mal.
    ///
    /// Beides zugleich ist erlaubt und das haeufigste: Schuhe nach 800 km
    /// *oder* nach drei Jahren, je nachdem, was zuerst eintritt.
    var intervalDays: Int?
    /// Kilometerstand des Stuecks beim letzten Mal.
    var lastDoneKm: Double
    var lastDoneAt: Date?
    var notes: String

    nonisolated init(id: String = UUID().uuidString,
                     equipmentID: String,
                     kind: ComponentKind = .chain,
                     name: String = "",
                     action: ComponentAction? = nil,
                     intervalKm: Double? = nil,
                     intervalDays: Int? = nil,
                     lastDoneKm: Double = 0,
                     lastDoneAt: Date? = nil,
                     notes: String = "") {
        self.id = id
        self.equipmentID = equipmentID
        self.kind = kind
        self.name = name
        self.action = action ?? kind.defaultAction
        self.intervalKm = intervalKm ?? kind.suggestedKm
        self.intervalDays = intervalDays ?? kind.suggestedDays
        self.lastDoneKm = lastDoneKm
        self.lastDoneAt = lastDoneAt
        self.notes = notes
    }

    nonisolated var displayName: String {
        name.isEmpty ? L10n.string(kind.displayKey) : name
    }

    /// Wie weit das Teil ist, 0…1+. Zaehlt beides, entscheidet das, was
    /// zuerst faellig wird — sonst faehrt man auf einer verschlissenen Kette
    /// weiter, weil das Datum noch Luft hat.
    nonisolated func progress(distanceKm: Double, since inUseFrom: Date, now: Date = .now) -> Double? {
        var values: [Double] = []
        if let intervalKm, intervalKm > 0 {
            values.append(max(distanceKm - lastDoneKm, 0) / intervalKm)
        }
        if let intervalDays, intervalDays > 0 {
            let start = lastDoneAt ?? inUseFrom
            let days = now.timeIntervalSince(start) / 86_400
            values.append(max(days, 0) / Double(intervalDays))
        }
        return values.max()
    }

    /// Welche der beiden Grenzen zuerst greift – fuer den Text darunter.
    nonisolated func limitingReason(distanceKm: Double,
                                    since inUseFrom: Date,
                                    now: Date = .now) -> String? {
        guard let intervalKm, intervalKm > 0 else {
            return intervalDays != nil ? "nach Zeit" : nil
        }
        guard let intervalDays, intervalDays > 0 else { return "nach Strecke" }
        let byDistance = max(distanceKm - lastDoneKm, 0) / intervalKm
        let start = lastDoneAt ?? inUseFrom
        let byTime = max(now.timeIntervalSince(start) / 86_400, 0) / Double(intervalDays)
        return byDistance >= byTime ? "nach Strecke" : "nach Zeit"
    }
}
