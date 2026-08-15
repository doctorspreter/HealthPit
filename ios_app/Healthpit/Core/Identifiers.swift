//
//  Identifiers.swift
//  HealthPitCore
//
//  Die zwei Kennungen, die nie vermischt werden duerfen:
//
//  MetricID       – WAS fuer ein Gesundheitswert ist es?  (HRT_RATE)
//  ObservationID  – WELCHER konkrete Messwert ist es?     (UUIDv7)
//
//  Dazu die Provider-Codes (welches externe System ist beteiligt) und der
//  Sync-Identifier, mit dem HealthPit eigene Exporte spaeter wiedererkennt.
//

import Foundation

// MARK: - Metric ID

/// Fachliche Kennung eines Gesundheitswerts, global gueltig und
/// providerunabhaengig.
///
/// Form: `<KATEGORIE>_<NAME>`, ausschliesslich `A-Z`, `0-9` und `_`.
/// Ein einmal produktiv verwendeter Identifier behaelt seine Bedeutung –
/// Umbenennungen laufen ueber eine neue ID plus Mapping, nie ueber eine
/// Neudeutung der alten.
struct MetricID: Hashable, Sendable, Codable, CustomStringConvertible,
                 ExpressibleByStringLiteral, Comparable {
    let rawValue: String

    init?(validating rawValue: String) {
        guard MetricID.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// Fuer die statisch im Code gepflegte Registry: ein Tippfehler soll beim
    /// ersten Start auffallen, nicht still eine kaputte ID anlegen.
    init(stringLiteral value: StringLiteralType) {
        precondition(MetricID.isValid(value), "Ungueltige Metric ID: \(value)")
        rawValue = value
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Unbekannte oder kuenftige IDs duerfen das Dekodieren nicht sprengen;
        // die Registry entscheidet spaeter, ob sie bekannt sind.
        rawValue = raw
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        guard let first = value.first, first.isUppercase else { return false }
        guard !value.hasSuffix("_"), !value.contains("__") else { return false }
        return value.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
    }

    /// Kategorie-Praefix, z. B. `HRT` in `HRT_RATE`.
    var categoryCode: String {
        String(rawValue.prefix(while: { $0 != "_" }))
    }

    var description: String { rawValue }

    static func < (lhs: MetricID, rhs: MetricID) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Provider

/// Fester interner Code eines Health-/Fitness-Anbieters.
///
/// Drei Buchstaben, zentral vergeben. Neue Anbieter kommen ueber
/// `ProviderRegistry` dazu; das Datenmodell aendert sich dafuer nicht.
struct ProviderCode: Hashable, Sendable, Codable, CustomStringConvertible,
                     ExpressibleByStringLiteral, Comparable {
    let rawValue: String

    init(stringLiteral value: StringLiteralType) {
        precondition(ProviderCode.isValid(value), "Ungueltiger Provider-Code: \(value)")
        rawValue = value
    }

    init?(validating rawValue: String) {
        guard ProviderCode.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func isValid(_ value: String) -> Bool {
        value.count == 3 && value.allSatisfy { $0.isUppercase && $0.isLetter }
    }

    var description: String { rawValue }

    static func < (lhs: ProviderCode, rhs: ProviderCode) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension ProviderCode {
    /// HealthPit selbst – Werte, die in dieser App entstanden sind
    /// (manuelle Eingabe, Dateiimport ohne fremde Herkunft).
    static let healthPit: ProviderCode = "HPT"
    static let appleHealth: ProviderCode = "APP"
    static let garmin: ProviderCode = "GAR"
    static let huawei: ProviderCode = "HUA"
    static let samsung: ProviderCode = "SAM"
    static let fitbit: ProviderCode = "FIT"
    static let oura: ProviderCode = "OUR"
    static let polar: ProviderCode = "POL"
    /// Home-Assistant-Bridge – kein Messgeraet, aber ein Ziel- und
    /// Quellsystem, das eigene Record-IDs vergibt.
    static let homeAssistant: ProviderCode = "HAS"
    /// GymPit – die Schwester-App, die Krafttrainings liefert.
    static let gymPit: ProviderCode = "GYM"
}

// MARK: - Observation ID (UUIDv7)

/// Eindeutige, zeitlich sortierbare ID genau einer Messung.
///
/// UUIDv7 nach RFC 9562: 48 Bit Unix-Millisekunden, dann Version/Variante,
/// dann Zufall. Damit sortiert die ID nach Entstehungszeit – praktisch fuer
/// Indexe, Paging und Debugging – und bleibt global eindeutig.
struct ObservationID: Hashable, Sendable, Codable, CustomStringConvertible, Comparable {
    let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(uuid: UUID) {
        rawValue = uuid.uuidString.lowercased()
    }

    /// Bereits vergebene ID aus Datenbank oder Fremdsystem uebernehmen.
    init?(_ rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: normalized) != nil else { return nil }
        self.rawValue = normalized
    }

    static func generate(at date: Date = Date(), random: () -> UInt8 = { UInt8.random(in: 0...255) }) -> ObservationID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<16 { bytes[index] = random() }

        let milliseconds = UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
        bytes[0] = UInt8((milliseconds >> 40) & 0xFF)
        bytes[1] = UInt8((milliseconds >> 32) & 0xFF)
        bytes[2] = UInt8((milliseconds >> 24) & 0xFF)
        bytes[3] = UInt8((milliseconds >> 16) & 0xFF)
        bytes[4] = UInt8((milliseconds >> 8) & 0xFF)
        bytes[5] = UInt8(milliseconds & 0xFF)
        // Version 7 in den oberen vier Bit von Byte 6, Variante 0b10 in Byte 8.
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                               bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11],
                               bytes[12], bytes[13], bytes[14], bytes[15]))
        return ObservationID(uuid: uuid)
    }

    /// Zeitstempel, der in der ID steckt (nur fuer v7 sinnvoll).
    var embeddedTimestamp: Date? {
        guard let uuid = UUID(uuidString: rawValue) else { return nil }
        let bytes = uuid.uuid
        guard (bytes.6 & 0xF0) == 0x70 else { return nil }
        var milliseconds: UInt64 = 0
        for byte in [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5] {
            milliseconds = (milliseconds << 8) | UInt64(byte)
        }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    var description: String { rawValue }

    static func < (lhs: ObservationID, rhs: ObservationID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Eindeutige ID eines Workouts – gleiche Bauart wie die Observation ID.
struct WorkoutID: Hashable, Sendable, Codable, CustomStringConvertible, Comparable {
    let rawValue: String

    init?(_ rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: normalized) != nil else { return nil }
        self.rawValue = normalized
    }

    init(uuid: UUID) {
        rawValue = uuid.uuidString.lowercased()
    }

    static func generate(at date: Date = Date()) -> WorkoutID {
        WorkoutID(uuid: UUID(uuidString: ObservationID.generate(at: date).rawValue)!)
    }

    var description: String { rawValue }

    static func < (lhs: WorkoutID, rhs: WorkoutID) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Sync Identifier

/// Der Marker, den HealthPit beim Export mitgibt und beim Import wiedererkennt.
///
/// `HEALTHPIT:OBS-<observation_id>` – bewusst mit Praefix, damit ein fremdes
/// System denselben String nicht zufaellig erzeugt und damit ein Blick in die
/// Health-App sofort zeigt, woher der Datensatz stammt.
enum SyncIdentifier {
    static let prefix = "HEALTHPIT:OBS-"
    static let workoutPrefix = "HEALTHPIT:WRK-"

    static func make(for observationID: ObservationID) -> String {
        prefix + observationID.rawValue
    }

    static func make(for workoutID: WorkoutID) -> String {
        workoutPrefix + workoutID.rawValue
    }

    /// Liefert die Observation ID zurueck, wenn der String von uns stammt.
    static func observationID(from value: String?) -> ObservationID? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        return ObservationID(String(trimmed.dropFirst(prefix.count)))
    }

    static func workoutID(from value: String?) -> WorkoutID? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(workoutPrefix) else { return nil }
        return WorkoutID(String(trimmed.dropFirst(workoutPrefix.count)))
    }

    static func isHealthPitOwned(_ value: String?) -> Bool {
        observationID(from: value) != nil || workoutID(from: value) != nil
    }
}

// MARK: - User

/// HealthPit ist heute eine Ein-Personen-App auf dem eigenen Geraet. Die
/// Spalte bleibt trotzdem im Modell: Alle Unique Constraints haengen daran,
/// und ein spaeterer Mehrbenutzerbetrieb waere sonst wieder eine Migration.
enum HealthPitUser {
    static let local = "local"
}
