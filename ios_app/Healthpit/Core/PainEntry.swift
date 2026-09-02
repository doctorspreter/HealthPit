//
//  PainEntry.swift
//  HealthPitCore
//
//  Schmerzen und Verletzungen als eigener Bestand.
//
//  In der Datenbank stehen englische Codes (`KNEE_LEFT`, `SHARP`), niemals
//  Anzeigetexte. Das Training speichert seine Verletzung bis heute als
//  deutschen Text („Knie links"); `BodyRegion.from(legacy:)` holt die
//  Altbestaende ein, damit beide Quellen in derselben Liste stehen.
//

import Foundation

/// Woher ein Eintrag kommt und was er beschreibt.
enum PainEntryKind: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Ein Schmerz, der kommt und geht.
    case pain = "PAIN"
    /// Eine Verletzung mit Verlauf – hat in der Regel ein Ende.
    case injury = "INJURY"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .pain:   return "Schmerz"
        case .injury: return "Verletzung"
        }
    }

    var systemImage: String {
        switch self {
        case .pain:   return "bolt.horizontal.circle"
        case .injury: return "bandage"
        }
    }
}

/// Koerperregion. Der Code steht in der Datenbank, der Schluessel in der App.
enum BodyRegion: String, CaseIterable, Identifiable, Sendable, Codable {
    case head = "HEAD"
    case neck = "NECK"
    case shoulderLeft = "SHOULDER_LEFT"
    case shoulderRight = "SHOULDER_RIGHT"
    case elbowLeft = "ELBOW_LEFT"
    case elbowRight = "ELBOW_RIGHT"
    case wrist = "WRIST"
    case back = "BACK"
    case hip = "HIP"
    case kneeLeft = "KNEE_LEFT"
    case kneeRight = "KNEE_RIGHT"
    case ankle = "ANKLE"
    case foot = "FOOT"
    case other = "OTHER"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .head:          return "Kopf"
        case .neck:          return "Nacken"
        case .shoulderLeft:  return "Schulter links"
        case .shoulderRight: return "Schulter rechts"
        case .elbowLeft:     return "Ellbogen links"
        case .elbowRight:    return "Ellbogen rechts"
        case .wrist:         return "Handgelenk"
        case .back:          return "Rücken"
        case .hip:           return "Hüfte"
        case .kneeLeft:      return "Knie links"
        case .kneeRight:     return "Knie rechts"
        case .ankle:         return "Sprunggelenk"
        case .foot:          return "Fuß"
        case .other:         return "Sonstiges"
        }
    }

    /// Die deutschen Texte, die das manuelle Training bisher gespeichert hat.
    /// Ohne diese Bruecke stuenden Alteintraege ohne Region da.
    static func from(legacy text: String) -> BodyRegion? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "kopf":            return .head
        case "nacken":          return .neck
        case "schulter links":  return .shoulderLeft
        case "schulter rechts": return .shoulderRight
        case "ellbogen", "ellbogen links":  return .elbowLeft
        case "ellbogen rechts": return .elbowRight
        case "handgelenk":      return .wrist
        case "rücken", "ruecken": return .back
        case "hüfte", "huefte": return .hip
        case "knie links":      return .kneeLeft
        case "knie rechts":     return .kneeRight
        case "sprunggelenk":    return .ankle
        case "fuß", "fuss":     return .foot
        default:                return .other
        }
    }
}

/// Art des Schmerzes.
enum PainQuality: String, CaseIterable, Identifiable, Sendable, Codable {
    case pulling = "PULLING"
    case sharp = "SHARP"
    case dull = "DULL"
    case pressure = "PRESSURE"
    case burning = "BURNING"
    case throbbing = "THROBBING"
    case unstable = "UNSTABLE"
    case numb = "NUMB"
    case other = "OTHER"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .pulling:   return "Ziehend"
        case .sharp:     return "Stechend"
        case .dull:      return "Dumpf"
        case .pressure:  return "Druck"
        case .burning:   return "Brennend"
        case .throbbing: return "Pochend"
        case .unstable:  return "Instabil"
        case .numb:      return "Taub"
        case .other:     return "Sonstiges"
        }
    }

    static func from(legacy text: String) -> PainQuality? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "leichtes ziehen", "ziehend": return .pulling
        case "stechend":                   return .sharp
        case "dumpf":                      return .dull
        case "druck":                      return .pressure
        case "brennen", "brennend":        return .burning
        case "pochend":                    return .throbbing
        case "instabil":                   return .unstable
        case "taub":                       return .numb
        default:                           return .other
        }
    }
}

/// Ein Eintrag im Schmerz- und Verletzungsbestand.
struct PainEntry: Identifiable, Hashable, Sendable {
    let id: String
    var kind: PainEntryKind
    var region: BodyRegion
    var quality: PainQuality?
    /// 0…10. Null heisst „nicht angegeben".
    var severity: Int
    var startedAt: Date
    /// Offen, solange nichts eingetragen ist – die Beschwerde besteht noch.
    var endedAt: Date?
    var notes: String
    /// Gesetzt, wenn der Eintrag aus einem Training stammt. Solche Eintraege
    /// werden hier gezeigt, aber nicht hier bearbeitet.
    var workoutID: String?

    nonisolated init(id: String = UUID().uuidString,
                     kind: PainEntryKind = .pain,
                     region: BodyRegion = .other,
                     quality: PainQuality? = nil,
                     severity: Int = 0,
                     startedAt: Date = .now,
                     endedAt: Date? = nil,
                     notes: String = "",
                     workoutID: String? = nil) {
        self.id = id
        self.kind = kind
        self.region = region
        self.quality = quality
        self.severity = severity
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.workoutID = workoutID
    }

    /// Aus einem Training uebernommen. Die Kennung haengt am Training, damit
    /// derselbe Eintrag nicht bei jedem Neuladen ein zweites Mal erscheint.
    nonisolated init(workoutID: String, injury: WorkoutInjury, start: Date) {
        self.init(id: "workout:\(workoutID)",
                  kind: .pain,
                  region: BodyRegion.from(legacy: injury.location) ?? .other,
                  quality: PainQuality.from(legacy: injury.painType),
                  severity: injury.severity,
                  startedAt: start,
                  endedAt: nil,
                  notes: "",
                  workoutID: workoutID)
    }

    nonisolated var isFromWorkout: Bool { workoutID != nil }

    nonisolated var isOngoing: Bool { endedAt == nil }
}
