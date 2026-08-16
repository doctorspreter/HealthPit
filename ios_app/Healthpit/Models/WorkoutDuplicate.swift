//
//  WorkoutDuplicate.swift
//  Healthpit
//
//  Zwei Aufzeichnungen, die dieselbe Einheit sein koennten. Die Integration
//  schlaegt sie vor, entschieden wird hier.
//

import Foundation

/// Was mit einem Vorschlag geschehen soll.
enum WorkoutDuplicateAction: String, Codable, Sendable {
    /// Beide sind dieselbe Einheit und erscheinen ab jetzt als eine.
    case merge
    /// Es sind zwei verschiedene Einheiten; nicht noch einmal vorschlagen.
    case separate
}

/// Eine Seite eines Vorschlags.
struct WorkoutDuplicateSide: Decodable, Hashable, Sendable {
    /// Woran eine Entscheidung haengt. Bleibt gueltig, auch wenn dasselbe
    /// Training erneut hochgeladen wird.
    let key: String
    /// Alle Kennungen dieser Aufzeichnung, je Quelle eine. Nach einer
    /// Zusammenfuehrung traegt eine Seite mehrere davon.
    let keys: [String]
    let sport: String
    let title: String
    let source: String
    let sources: [String]
    let deviceID: String
    let start: String
    let durationSeconds: Double
    let distanceKm: Double?
    let energyKcal: Double?
    let exerciseCount: Int
    let setCount: Int
    let routePoints: Int

    enum CodingKeys: String, CodingKey {
        case key, keys, sport, title, source, sources, start
        case deviceID = "device_id"
        case durationSeconds = "duration_seconds"
        case distanceKm = "distance_km"
        case energyKcal = "energy_kcal"
        case exerciseCount = "exercise_count"
        case setCount = "set_count"
        case routePoints = "route_points"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        keys = (try? container.decodeIfPresent([String].self, forKey: .keys)) as? [String] ?? []
        sport = (try? container.decodeIfPresent(String.self, forKey: .sport)) as? String ?? ""
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) as? String ?? ""
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) as? String ?? ""
        sources = (try? container.decodeIfPresent([String].self, forKey: .sources)) as? [String] ?? []
        deviceID = (try? container.decodeIfPresent(String.self, forKey: .deviceID)) as? String ?? ""
        start = (try? container.decodeIfPresent(String.self, forKey: .start)) as? String ?? ""
        durationSeconds = (try? container.decodeIfPresent(Double.self, forKey: .durationSeconds)) as? Double ?? 0
        distanceKm = try? container.decodeIfPresent(Double.self, forKey: .distanceKm)
        energyKcal = try? container.decodeIfPresent(Double.self, forKey: .energyKcal)
        exerciseCount = (try? container.decodeIfPresent(Int.self, forKey: .exerciseCount)) as? Int ?? 0
        setCount = (try? container.decodeIfPresent(Int.self, forKey: .setCount)) as? Int ?? 0
        routePoints = (try? container.decodeIfPresent(Int.self, forKey: .routePoints)) as? Int ?? 0
    }

    /// Datum und Uhrzeit, sonst der rohe Wert. Die Zeitangabe kommt als Text
    /// herein, damit ein unerwartetes Format nicht die ganze Liste kippt.
    var startDate: Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: start) ?? ISO8601DateFormatter().date(from: start)
    }

    /// Lesbarer Sportname. GymPit sendet Bezeichner wie `strength_training`,
    /// Apple Health einen Anzeigenamen — beides landet hier nebeneinander.
    var sportLabel: String {
        let raw = sport.isEmpty ? title : sport
        let lower = raw.lowercased()
        if lower.contains("kraft") || lower.contains("strength") {
            return L10n.string("Krafttraining")
        }
        if lower.contains("lauf") || lower.contains("run") {
            return L10n.string("Laufen")
        }
        if lower.contains("rad") || lower.contains("cycl") || lower.contains("bike") {
            return L10n.string("Radfahren")
        }
        if lower.contains("geh") || lower.contains("walk") {
            return L10n.string("Gehen")
        }
        if lower.contains("schwimm") || lower.contains("swim") {
            return L10n.string("Schwimmen")
        }
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return L10n.stringResolvingStoredTranslation(spaced)
    }

    /// Der Apple-Health-Eintrag hinter dieser Seite.
    ///
    /// Die Schluessel sind `quelle:id`, und fuer Apple Health ist diese ID die
    /// UUID des HKWorkout — dieselbe, mit der die App das Training hochgeladen
    /// hat. Damit laesst sich der Eintrag in Apple Health wiederfinden.
    var appleHealthUUID: UUID? {
        let prefix = "\(LocalWorkout.Source.appleHealth.rawValue):"
        for candidate in (keys.isEmpty ? [key] : keys) where candidate.hasPrefix(prefix) {
            if let uuid = UUID(uuidString: String(candidate.dropFirst(prefix.count))) {
                return uuid
            }
        }
        return nil
    }

    /// „GymPit" statt „gympit", „Apple Health" statt „apple_health".
    var sourceLabel: String {
        let names = sources.isEmpty ? [source] : sources
        return names
            .map { LocalWorkout.Source(rawValue: $0)?.displayName ?? $0 }
            .joined(separator: " + ")
    }
}

/// Ein Paar, das dieselbe Einheit sein koennte.
struct WorkoutDuplicateCandidate: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let reason: String
    let confidence: Double
    let left: WorkoutDuplicateSide
    let right: WorkoutDuplicateSide

    /// Warum das Paar vorgeschlagen wurde, in der Sprache der App.
    var reasonText: String {
        switch reason {
        case "same_source": return L10n.string("Zweimal aus derselben Quelle")
        case "same_start": return L10n.string("Gleiche Startzeit")
        case "same_duration": return L10n.string("Gleiche Startzeit und Dauer")
        case "same_distance": return L10n.string("Gleiche Strecke")
        case "close_start": return L10n.string("Fast gleiche Startzeit")
        default: return L10n.string("Ähnliche Einheit")
        }
    }
}

/// Eine bereits getroffene Entscheidung.
struct WorkoutDuplicateDecision: Decodable, Identifiable, Hashable, Sendable {
    let primary: String
    let linked: String
    let action: String
    /// Die beiden Trainings, um die es ging.
    ///
    /// Ohne sie stand in der Liste nur „Als ein Training" und ein Knopf zum
    /// Zuruecknehmen — richtig, aber niemandem zuzuordnen. Die Integration
    /// schickt die Beschreibung neben den Schluesseln mit; sie fehlt nur,
    /// wenn das Training inzwischen geloescht wurde.
    let primarySide: WorkoutDuplicateSide?
    let linkedSide: WorkoutDuplicateSide?

    var id: String { "\(primary)|\(linked)" }

    var isMerge: Bool { action == WorkoutDuplicateAction.merge.rawValue }

    /// Beide Seiten, soweit bekannt.
    var sides: [WorkoutDuplicateSide] { [primarySide, linkedSide].compactMap { $0 } }

    enum CodingKeys: String, CodingKey {
        case primary, linked, action
        case primarySide = "primary_side"
        case linkedSide = "linked_side"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decode(String.self, forKey: .primary)
        linked = try container.decode(String.self, forKey: .linked)
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) as? String ?? ""
        // Eine unerwartete Seite darf die ganze Liste nicht kippen: dann steht
        // die Entscheidung eben ohne Beschreibung da und laesst sich weiterhin
        // zuruecknehmen.
        primarySide = try? container.decodeIfPresent(WorkoutDuplicateSide.self, forKey: .primarySide)
        linkedSide = try? container.decodeIfPresent(WorkoutDuplicateSide.self, forKey: .linkedSide)
    }
}

/// Was der Endpunkt liefert.
struct WorkoutDuplicateReport: Decodable, Sendable {
    let candidates: [WorkoutDuplicateCandidate]
    let decisions: [WorkoutDuplicateDecision]

    static let empty = WorkoutDuplicateReport(candidates: [], decisions: [])

    init(candidates: [WorkoutDuplicateCandidate], decisions: [WorkoutDuplicateDecision]) {
        self.candidates = candidates
        self.decisions = decisions
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidates = (try? container.decodeIfPresent([WorkoutDuplicateCandidate].self, forKey: .candidates)) as? [WorkoutDuplicateCandidate] ?? []
        decisions = (try? container.decodeIfPresent([WorkoutDuplicateDecision].self, forKey: .decisions)) as? [WorkoutDuplicateDecision] ?? []
    }

    enum CodingKeys: String, CodingKey {
        case candidates, decisions
    }
}
