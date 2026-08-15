//
//  ProviderMetricMapping.swift
//  HealthPitCore
//
//  Die Uebersetzungsschicht zwischen dem, wie ein Anbieter seine Werte nennt,
//  und der HealthPit-Metric. Ein neuer Anbieter braucht neue Zeilen hier –
//  nicht ein neues Datenmodell.
//

import Foundation

enum MappingStatus: String, Sendable, Codable {
    case active = "ACTIVE"
    case deprecated = "DEPRECATED"
}

/// Rechenregel fuer Faelle, in denen die reine Einheitenumrechnung nicht
/// reicht.
///
/// Beispiel HealthKit: Prozentwerte kommen als Anteil (0,97), HealthPit
/// speichert Prozent (97). Das ist keine Einheiten-, sondern eine
/// Skalenfrage – deshalb eine eigene, explizite Regel.
struct ConversionRule: Hashable, Sendable {
    var factor: Double
    var offset: Double

    static let identity = ConversionRule(factor: 1, offset: 0)

    func apply(_ value: Double) -> Double { value * factor + offset }

    var isIdentity: Bool { factor == 1 && offset == 0 }

    /// Textform fuer die Datenbankspalte: `FACTOR:100;OFFSET:0`.
    var encoded: String? {
        isIdentity ? nil : "FACTOR:\(factor);OFFSET:\(offset)"
    }

    init(factor: Double = 1, offset: Double = 0) {
        self.factor = factor
        self.offset = offset
    }

    init?(encoded: String?) {
        guard let encoded, !encoded.isEmpty else { return nil }
        var factor = 1.0
        var offset = 0.0
        for part in encoded.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2, let number = Double(pieces[1]) else { continue }
            switch pieces[0].uppercased() {
            case "FACTOR": factor = number
            case "OFFSET": offset = number
            default: continue
            }
        }
        self.init(factor: factor, offset: offset)
    }
}

struct ProviderMetricMapping: Hashable, Sendable {
    var id: Int64?
    var provider: ProviderCode
    /// Bezeichnung beim Anbieter, z. B. `HKQuantityTypeIdentifierStepCount`
    /// oder `dailies.steps`.
    var sourceMetric: String
    var metricID: MetricID
    /// Einheit, in der der Anbieter ueblicherweise liefert.
    var sourceUnit: UnitCode?
    /// Zieleinheit. Normalerweise die kanonische Einheit der Metrik.
    var canonicalUnit: UnitCode?
    var conversionRule: String?
    /// Uebersetzung von Anbieter-Codes in unsere ENUM-Codes
    /// (`"3": "DEEP"`).
    var valueMapping: [String: String]

    var canRead: Bool
    var canWrite: Bool
    var canUpdate: Bool
    var canDelete: Bool

    var mappingVersion: Int
    var status: MappingStatus

    init(id: Int64? = nil,
         provider: ProviderCode,
         sourceMetric: String,
         metricID: MetricID,
         sourceUnit: UnitCode? = nil,
         canonicalUnit: UnitCode? = nil,
         conversionRule: ConversionRule? = nil,
         valueMapping: [String: String] = [:],
         canRead: Bool = true,
         canWrite: Bool = false,
         canUpdate: Bool = false,
         canDelete: Bool = false,
         mappingVersion: Int = 1,
         status: MappingStatus = .active) {
        self.id = id
        self.provider = provider
        self.sourceMetric = sourceMetric
        self.metricID = metricID
        self.sourceUnit = sourceUnit
        self.canonicalUnit = canonicalUnit
        self.conversionRule = conversionRule?.encoded
        self.valueMapping = valueMapping
        self.canRead = canRead
        self.canWrite = canWrite
        self.canUpdate = canUpdate
        self.canDelete = canDelete
        self.mappingVersion = mappingVersion
        self.status = status
    }

    var rule: ConversionRule {
        ConversionRule(encoded: conversionRule) ?? .identity
    }

    init?(row: SQLRow) {
        guard let providerRaw = row.string("provider"),
              let provider = ProviderCode(validating: providerRaw),
              let sourceMetric = row.string("source_metric"),
              let metricRaw = row.string("metric_id"),
              let metricID = MetricID(validating: metricRaw) else {
            return nil
        }
        self.init(id: row.int64("id"),
                  provider: provider,
                  sourceMetric: sourceMetric,
                  metricID: metricID,
                  sourceUnit: row.string("source_unit").map { UnitCode($0) },
                  canonicalUnit: row.string("canonical_unit").map { UnitCode($0) },
                  conversionRule: ConversionRule(encoded: row.string("conversion_rule")),
                  valueMapping: JSONColumn.decode(row.string("value_mapping")),
                  canRead: row.bool("can_read") ?? true,
                  canWrite: row.bool("can_write") ?? false,
                  canUpdate: row.bool("can_update") ?? false,
                  canDelete: row.bool("can_delete") ?? false,
                  mappingVersion: row.int("mapping_version") ?? 1,
                  status: row.string("status").flatMap(MappingStatus.init(rawValue:)) ?? .active)
    }
}
