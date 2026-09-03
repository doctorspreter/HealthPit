//
//  Equipment.swift
//  HealthPitCore
//
//  Ausruestung mit Wartung und Austausch: Laufschuhe, Rad, Kette, Matte.
//
//  Ein Stueck Ausruestung gilt ab einem Datum und faellt damit automatisch
//  den Trainings zu, die dazu passen — wer im Maerz neue Schuhe kauft, will
//  nicht jeden Lauf einzeln zuordnen. Ein einzelnes Training laesst sich
//  trotzdem abweichend zuordnen; diese Zuordnung sticht die automatische.
//
//  In der Datenbank stehen englische Codes.
//

import Foundation

enum EquipmentKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case runningShoes = "RUNNING_SHOES"
    case walkingShoes = "WALKING_SHOES"
    case bike = "BIKE"
    case indoorBike = "INDOOR_BIKE"
    case climbingShoes = "CLIMBING_SHOES"
    case swimGear = "SWIM_GEAR"
    case mat = "MAT"
    case other = "OTHER"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .runningShoes:  return "Laufschuhe"
        case .walkingShoes:  return "Wanderschuhe"
        case .bike:          return "Fahrrad"
        case .indoorBike:    return "Indoor-Rad"
        case .climbingShoes: return "Kletterschuhe"
        case .swimGear:      return "Schwimmausrüstung"
        case .mat:           return "Matte"
        case .other:         return "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .runningShoes, .walkingShoes: return "shoe"
        case .bike, .indoorBike:           return "bicycle"
        case .climbingShoes:               return "figure.climbing"
        case .swimGear:                    return "figure.pool.swim"
        case .mat:                         return "square.stack"
        case .other:                       return "shippingbox"
        }
    }

    /// Kanonische Sportarten, denen dieses Stueck von selbst zufaellt.
    /// Leer heisst: nur, wenn es jemand ausdruecklich zuordnet.
    var automaticSportTypes: Set<String> {
        switch self {
        case .runningShoes:  return ["RUNNING"]
        case .walkingShoes:  return ["WALKING", "HIKING"]
        case .bike:          return ["CYCLING", "HAND_CYCLING"]
        case .indoorBike:    return ["CYCLING"]
        case .climbingShoes: return ["CLIMBING"]
        case .swimGear:      return ["SWIMMING"]
        case .mat:           return ["YOGA", "PILATES", "CORE_TRAINING"]
        case .other:         return []
        }
    }

    /// Ob eine Laufleistung in Kilometern ueberhaupt sinnvoll ist. Bei einer
    /// Yogamatte zaehlen Einheiten, keine Strecke.
    var tracksDistance: Bool {
        switch self {
        case .mat, .swimGear, .climbingShoes, .other: return false
        default: return true
        }
    }

    /// Ueblicher Austauschpunkt als Vorschlag, nicht als Vorschrift.
    var suggestedReplacementKm: Double? {
        switch self {
        case .runningShoes: return 800
        case .walkingShoes: return 1000
        case .bike:         return 5000
        default:            return nil
        }
    }
}

struct Equipment: Identifiable, Hashable, Sendable {
    let id: String
    var kind: EquipmentKind
    var name: String
    /// Ab wann es benutzt wird. Trainings davor zaehlen nicht.
    var inUseFrom: Date
    /// Ausgemustert. `nil` heisst: noch im Einsatz.
    var retiredAt: Date?
    /// Ob es den passenden Trainings von selbst zufaellt.
    var isAutomatic: Bool
    /// Austausch nach so vielen Kilometern. `nil` = kein Ziel.
    var replaceAfterKm: Double?
    /// Austausch nach so vielen Tagen. Beides zugleich ist der Regelfall:
    /// Schuhe nach 800 km *oder* nach drei Jahren — der Schaum altert auch
    /// im Schrank, und was zuerst eintritt, gilt.
    var replaceAfterDays: Int?
    /// Wartung alle so viele Kilometer (Kette oelen, Schuhe pruefen).
    var serviceEveryKm: Double?
    /// Kilometerstand bei der letzten Wartung.
    var lastServiceKm: Double
    var lastServiceAt: Date?
    var notes: String

    nonisolated init(id: String = UUID().uuidString,
                     kind: EquipmentKind = .runningShoes,
                     name: String = "",
                     inUseFrom: Date = .now,
                     retiredAt: Date? = nil,
                     isAutomatic: Bool = true,
                     replaceAfterKm: Double? = nil,
                     replaceAfterDays: Int? = nil,
                     serviceEveryKm: Double? = nil,
                     lastServiceKm: Double = 0,
                     lastServiceAt: Date? = nil,
                     notes: String = "") {
        self.id = id
        self.kind = kind
        self.name = name
        self.inUseFrom = inUseFrom
        self.retiredAt = retiredAt
        self.isAutomatic = isAutomatic
        self.replaceAfterKm = replaceAfterKm
        self.replaceAfterDays = replaceAfterDays
        self.serviceEveryKm = serviceEveryKm
        self.lastServiceKm = lastServiceKm
        self.lastServiceAt = lastServiceAt
        self.notes = notes
    }

    nonisolated var isRetired: Bool { retiredAt != nil }

    nonisolated var displayName: String {
        name.isEmpty ? L10n.string(kind.displayKey) : name
    }

    /// Deckt dieses Stueck den Zeitpunkt ab?
    nonisolated func covers(_ date: Date) -> Bool {
        if date < inUseFrom { return false }
        if let retiredAt, date > retiredAt { return false }
        return true
    }
}

/// Was ein Stueck Ausruestung hinter sich hat.
struct EquipmentUsage: Sendable {
    var workoutCount: Int
    var distanceKm: Double
    var duration: TimeInterval
    var lastUsed: Date?

    /// Anteil am Austauschziel, 0…1+. `nil` ohne Ziel.
    ///
    /// Strecke und Zeit zaehlen beide; es gilt, was zuerst eintritt.
    nonisolated func replacementProgress(_ equipment: Equipment, now: Date = .now) -> Double? {
        var values: [Double] = []
        if let target = equipment.replaceAfterKm, target > 0 {
            values.append(distanceKm / target)
        }
        if let days = equipment.replaceAfterDays, days > 0 {
            let age = now.timeIntervalSince(equipment.inUseFrom) / 86_400
            values.append(max(age, 0) / Double(days))
        }
        return values.max()
    }

    /// Kilometer seit der letzten Wartung gegen das Wartungsintervall.
    nonisolated func serviceProgress(_ equipment: Equipment) -> Double? {
        guard let interval = equipment.serviceEveryKm, interval > 0 else { return nil }
        return max(distanceKm - equipment.lastServiceKm, 0) / interval
    }
}
