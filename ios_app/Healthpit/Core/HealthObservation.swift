//
//  HealthObservation.swift
//  HealthPitCore
//
//  Ein konkreter Messwert. Genau ein realer Gesundheitswert = genau eine
//  Observation, egal ueber wie viele Anbieter er zusaetzlich hereinkommt.
//

import Foundation

/// Wie der Wert ueber seinen Zeitraum zustande kommt.
enum Aggregation: String, CaseIterable, Sendable, Codable {
    /// Einzelmessung, wie das Geraet sie geliefert hat.
    case raw = "RAW"
    case sum = "SUM"
    case average = "AVG"
    case minimum = "MIN"
    case maximum = "MAX"
    case count = "COUNT"
    /// Vom Anbieter berechneter Score.
    case score = "SCORE"
}

/// Welche Art von Zeitraum der Wert beschreibt.
enum PeriodType: String, CaseIterable, Sendable, Codable {
    case instant = "INSTANT"
    case interval = "INTERVAL"
    case hour = "HOUR"
    case day = "DAY"
    case night = "NIGHT"
    case session = "SESSION"
    case workout = "WORKOUT"

    /// Fasst dieser Typ einen abgeschlossenen Zeitraum zusammen?
    ///
    /// Fuer solche Werte gilt: derselbe Zeitraum, dieselbe Metrik, dieselbe
    /// Herkunft = derselbe Wert. Eine andere Zahl ist dann ein neuer Stand
    /// (der Tag laeuft noch, die Nacht wurde nachtraeglich ausgewertet) und
    /// keine zweite Messung.
    ///
    /// `instant` und `interval` gehoeren bewusst nicht dazu: Das sind
    /// Einzelmessungen und Segmente, und zwei davon duerfen nie
    /// zusammenfallen, nur weil sie zur selben Zeit liegen.
    var summarisesPeriod: Bool {
        switch self {
        case .hour, .day, .night, .session, .workout: return true
        case .instant, .interval: return false
        }
    }
}

/// Merker fuer Werte, die die Migration nicht eindeutig zuordnen konnte.
/// Sie werden trotzdem gespeichert – Wegwerfen waere Datenverlust.
enum ReviewState: String, Sendable, Codable {
    case ok = "OK"
    /// Alter Wert ohne sichere Metric-Zuordnung.
    case unresolvedMetric = "UNRESOLVED_METRIC"
    /// Einheit unklar, Wert wurde unveraendert uebernommen.
    case unresolvedUnit = "UNRESOLVED_UNIT"
}

/// Der eigentliche Datensatz.
///
/// Bewusst ohne zweite technische ID neben der `observationID`: eine
/// Zeile, ein Schluessel. `value`/`unit` sind der normalisierte Wert in der
/// kanonischen Einheit, `sourceValue`/`sourceUnit` das, was der Anbieter
/// geliefert hat.
struct HealthObservation: Hashable, Sendable, Codable, Identifiable {
    var id: ObservationID { observationID }

    let observationID: ObservationID
    var userID: String
    var metricID: MetricID

    var valueType: MetricValueType
    /// Normalisierter Zahlenwert in `unit`.
    var valueNumeric: Double?
    var valueText: String?
    /// Code aus der erlaubten Liste der Metrik (z. B. `DEEP`).
    var valueCode: String?
    var valueBoolean: Bool?
    var unit: UnitCode?

    /// Originalwert des Anbieters, falls umgerechnet wurde.
    var sourceValue: Double?
    var sourceUnit: UnitCode?

    var startTime: Date
    var endTime: Date
    /// IANA-Zeitzonenkennung zum Messzeitpunkt (`Europe/Berlin`).
    var timezone: String?

    var aggregation: Aggregation
    var periodType: PeriodType

    /// Wo der Wert entstanden ist.
    var originProvider: ProviderCode
    /// Ueber welches System er zu HealthPit kam.
    var ingestProvider: ProviderCode
    /// Record-ID beim urspruenglichen Erzeuger, falls die einliefernde
    /// Plattform sie durchreicht.
    var originExternalID: String?

    /// Wie der Anbieter die Metrik selbst nennt – fuer Nachvollziehbarkeit
    /// und spaetere Mapping-Korrekturen.
    var sourceMetric: String?
    var sourceAppID: String?
    var sourceDeviceID: String?
    var sourceDeviceModel: String?

    var workoutID: WorkoutID?
    var sessionID: String?

    /// Interner Stand des Datensatzes. Jede inhaltliche Aenderung zaehlt hoch.
    var version: Int
    var reviewState: ReviewState

    var receivedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var metadata: [String: String]
    /// Unveraenderter Anbieter-Datensatz als JSON-Text.
    var rawPayload: String?

    init(observationID: ObservationID = .generate(),
         userID: String = HealthPitUser.local,
         metricID: MetricID,
         valueType: MetricValueType = .number,
         valueNumeric: Double? = nil,
         valueText: String? = nil,
         valueCode: String? = nil,
         valueBoolean: Bool? = nil,
         unit: UnitCode? = nil,
         sourceValue: Double? = nil,
         sourceUnit: UnitCode? = nil,
         startTime: Date,
         endTime: Date,
         timezone: String? = TimeZone.current.identifier,
         aggregation: Aggregation = .raw,
         periodType: PeriodType = .instant,
         originProvider: ProviderCode,
         ingestProvider: ProviderCode,
         originExternalID: String? = nil,
         sourceMetric: String? = nil,
         sourceAppID: String? = nil,
         sourceDeviceID: String? = nil,
         sourceDeviceModel: String? = nil,
         workoutID: WorkoutID? = nil,
         sessionID: String? = nil,
         version: Int = 1,
         reviewState: ReviewState = .ok,
         receivedAt: Date = Date(),
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         deletedAt: Date? = nil,
         metadata: [String: String] = [:],
         rawPayload: String? = nil) {
        self.observationID = observationID
        self.userID = userID
        self.metricID = metricID
        self.valueType = valueType
        self.valueNumeric = valueNumeric
        self.valueText = valueText
        self.valueCode = valueCode
        self.valueBoolean = valueBoolean
        self.unit = unit
        self.sourceValue = sourceValue
        self.sourceUnit = sourceUnit
        self.startTime = startTime
        self.endTime = endTime
        self.timezone = timezone
        self.aggregation = aggregation
        self.periodType = periodType
        self.originProvider = originProvider
        self.ingestProvider = ingestProvider
        self.originExternalID = originExternalID
        self.sourceMetric = sourceMetric
        self.sourceAppID = sourceAppID
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceModel = sourceDeviceModel
        self.workoutID = workoutID
        self.sessionID = sessionID
        self.version = version
        self.reviewState = reviewState
        self.receivedAt = receivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.metadata = metadata
        self.rawPayload = rawPayload
    }

    var isDeleted: Bool { deletedAt != nil }

    /// Fingerabdruck des fachlichen Inhalts.
    ///
    /// Entscheidet beim Import zwischen UPDATE und UNCHANGED und beim Export
    /// zwischen UPDATE und SKIP. Bewusst ohne Zeitstempel wie `updatedAt`:
    /// ein erneuter Abruf desselben Werts soll nicht als Aenderung gelten.
    var contentHash: String {
        let parts: [String] = [
            metricID.rawValue,
            valueType.rawValue,
            valueNumeric.map { String(format: "%.6f", $0) } ?? "-",
            valueText ?? "-",
            valueCode ?? "-",
            valueBoolean.map { $0 ? "1" : "0" } ?? "-",
            unit?.rawValue ?? "-",
            String(format: "%.3f", startTime.timeIntervalSince1970),
            String(format: "%.3f", endTime.timeIntervalSince1970),
            aggregation.rawValue,
            periodType.rawValue,
            originProvider.rawValue,
            sourceDeviceID ?? "-",
            workoutID?.rawValue ?? "-",
            deletedAt == nil ? "live" : "deleted"
        ]
        return ContentHash.of(parts.joined(separator: "|"))
    }

    /// Schluessel fuer die kontrollierte heuristische Erkennung.
    ///
    /// Absichtlich mit Herkunft und Geraet: zwei echte Pulsmessungen mit
    /// demselben Wert zur selben Sekunde von verschiedenen Geraeten bleiben
    /// damit zwei Messungen.
    var heuristicKey: String {
        [
            userID,
            metricID.rawValue,
            originProvider.rawValue,
            sourceDeviceID ?? "-",
            String(Int(startTime.timeIntervalSince1970.rounded())),
            String(Int(endTime.timeIntervalSince1970.rounded())),
            aggregation.rawValue,
            periodType.rawValue,
            valueNumeric.map { String(format: "%.4f", $0) } ?? valueCode ?? valueText ?? "-",
            unit?.rawValue ?? "-"
        ].joined(separator: "|")
    }
}

/// Kleiner, stabiler Hash ohne CryptoKit – der Core soll ohne zusaetzliche
/// Frameworks auskommen. FNV-1a genuegt, es geht um Gleichheit, nicht um
/// Faelschungssicherheit.
enum ContentHash {
    static func of(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
