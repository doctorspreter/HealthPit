//
//  MetricRegistry.swift
//  HealthPitCore
//
//  Die zentrale Stelle, an der jede in HealthPit bekannte Metrik genau einmal
//  definiert ist. Alles andere – Anbieter-Mappings, Observations, Anzeige –
//  verweist nur noch auf die Metric ID.
//

import Foundation

/// Fachliche Kategorie einer Metrik. Der Code ist zugleich das Praefix der
/// Metric ID (`ACT` → `ACT_STEPS`).
enum MetricCategory: String, CaseIterable, Sendable, Codable {
    case activity = "ACT"
    case heart = "HRT"
    case sleep = "SLP"
    case body = "BDY"
    case energy = "NRG"
    case respiratory = "RSP"
    case temperature = "TMP"
    case vitals = "VTL"
    case nutrition = "NUT"
    case workout = "WRK"
    /// Zyklus – in HealthPit eine eigene Dashboard-Kategorie.
    case cycle = "CYC"
    /// Umgebung (Laerm, UV). Getrennt von VTL, weil es nichts ueber den
    /// Koerper aussagt, sondern ueber das, was auf ihn einwirkt.
    case environment = "ENV"
    /// Herstellereigene Scores, die keiner fachlichen Kategorie sauber
    /// zuzuordnen sind.
    case proprietary = "PRP"
}

/// Welche Art von Wert eine Metrik traegt.
enum MetricValueType: String, CaseIterable, Sendable, Codable {
    case number = "NUMBER"
    case string = "STRING"
    case boolean = "BOOLEAN"
    /// Feste, in der Registry definierte Codeliste (Schlafphase, Zyklusfluss).
    case enumerated = "ENUM"
    /// Offene Codeliste des Anbieters (Wetterlage, Sportart).
    case category = "CATEGORY"
    /// Zeitreihe, die als Ganzes zu einem Messwert gehoert (Routen, Splits).
    case series = "SERIES"
    case json = "JSON"
}

/// Lebenszyklus einer Definition. Ein produktiv genutzter Identifier wird
/// niemals umgedeutet – er wird hoechstens `deprecated`.
enum MetricStatus: String, Sendable, Codable {
    case active = "ACTIVE"
    case deprecated = "DEPRECATED"
    /// Nur beim Import angelegt, fachlich noch nicht geklaert.
    case provisional = "PROVISIONAL"
}

/// Eine Zeile der Metric Registry.
struct MetricDefinition: Hashable, Sendable, Codable {
    let metricID: MetricID
    let category: MetricCategory
    /// Englischer, technischer Name. Die Uebersetzung fuer die Oberflaeche
    /// bleibt in der App – die Registry ist keine Lokalisierungsdatei.
    let name: String
    let description: String
    let valueType: MetricValueType
    /// Bevorzugte interne Einheit. `nil` bei Werten ohne Einheit (ENUM/JSON).
    let canonicalUnit: UnitCode?
    /// Erlaubte Codes bei `valueType == .enumerated`.
    let allowedCodes: [String]
    let isProprietary: Bool
    let proprietaryProvider: ProviderCode?
    var status: MetricStatus
    /// Version der Definition. Aendert sich, wenn Einheit oder Wertebereich
    /// praezisiert werden – die Bedeutung bleibt gleich.
    var version: Int

    init(_ metricID: MetricID,
         category: MetricCategory,
         name: String,
         description: String = "",
         valueType: MetricValueType = .number,
         canonicalUnit: UnitCode?,
         allowedCodes: [String] = [],
         isProprietary: Bool = false,
         proprietaryProvider: ProviderCode? = nil,
         status: MetricStatus = .active,
         version: Int = 1) {
        self.metricID = metricID
        self.category = category
        self.name = name
        self.description = description
        self.valueType = valueType
        self.canonicalUnit = canonicalUnit
        self.allowedCodes = allowedCodes
        self.isProprietary = isProprietary
        self.proprietaryProvider = proprietaryProvider
        self.status = status
        self.version = version
    }
}

/// Nachschlagewerk ueber alle bekannten Metriken.
///
/// Der eingebaute Katalog steht im Code (`MetricCatalog.builtIn`), damit
/// Fehler beim Bauen auffallen. Zur Laufzeit koennen weitere Definitionen
/// dazukommen – etwa ein proprietaerer Score eines neuen Anbieters –, die
/// dann in der Datenbank landen.
struct MetricRegistry: Sendable {
    private(set) var definitionsByID: [MetricID: MetricDefinition]

    init(definitions: [MetricDefinition] = MetricCatalog.builtIn) {
        var byID: [MetricID: MetricDefinition] = [:]
        for definition in definitions {
            precondition(byID[definition.metricID] == nil,
                         "Doppelte Metric ID in der Registry: \(definition.metricID)")
            byID[definition.metricID] = definition
        }
        definitionsByID = byID
    }

    var all: [MetricDefinition] {
        definitionsByID.values.sorted { $0.metricID < $1.metricID }
    }

    func definition(_ metricID: MetricID) -> MetricDefinition? {
        definitionsByID[metricID]
    }

    func definition(id rawValue: String) -> MetricDefinition? {
        guard let metricID = MetricID(validating: rawValue) else { return nil }
        return definitionsByID[metricID]
    }

    func contains(_ metricID: MetricID) -> Bool {
        definitionsByID[metricID] != nil
    }

    func metrics(in category: MetricCategory) -> [MetricDefinition] {
        all.filter { $0.category == category }
    }

    func canonicalUnit(for metricID: MetricID) -> UnitCode? {
        definitionsByID[metricID]?.canonicalUnit
    }

    /// Neue Definition aufnehmen (z. B. proprietaerer Score eines Anbieters,
    /// der erst zur Laufzeit bekannt wird).
    mutating func register(_ definition: MetricDefinition) {
        definitionsByID[definition.metricID] = definition
    }

    /// Zwei proprietaere Werte verschiedener Anbieter sind nie derselbe Wert,
    /// auch wenn beide 0–100 liefern.
    func areComparable(_ lhs: MetricID, _ rhs: MetricID) -> Bool {
        if lhs == rhs {
            guard let definition = definitionsByID[lhs] else { return false }
            return !definition.isProprietary || definition.proprietaryProvider != nil
        }
        return false
    }

    /// Sanity-Check, den die Tests fahren: valide IDs, Praefix passt zur
    /// Kategorie, Einheit ist bekannt, ENUM hat Codes.
    func validate() -> [String] {
        var problems: [String] = []
        for definition in all {
            let id = definition.metricID
            if !MetricID.isValid(id.rawValue) {
                problems.append("\(id): ungueltige Schreibweise")
            }
            let expectedPrefix = definition.isProprietary
                ? definition.proprietaryProvider?.rawValue
                : definition.category.rawValue
            if let expectedPrefix, id.categoryCode != expectedPrefix {
                problems.append("\(id): Praefix passt nicht zu \(expectedPrefix)")
            }
            if let unit = definition.canonicalUnit, !UnitConverter.isKnown(unit) {
                problems.append("\(id): unbekannte Einheit \(unit)")
            }
            switch definition.valueType {
            case .enumerated where definition.allowedCodes.isEmpty:
                problems.append("\(id): ENUM ohne erlaubte Codes")
            case .number where definition.canonicalUnit == nil:
                problems.append("\(id): NUMBER ohne kanonische Einheit")
            default:
                break
            }
            if definition.isProprietary && definition.proprietaryProvider == nil {
                problems.append("\(id): proprietaer, aber ohne Anbieter")
            }
        }
        return problems
    }
}
