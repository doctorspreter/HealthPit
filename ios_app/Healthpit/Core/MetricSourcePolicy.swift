//
//  MetricSourcePolicy.swift
//  HealthPitCore
//
//  Wer darf welchen Wert liefern?
//
//  Beispiel: Schritte kommen von Garmin und Huawei, aber nicht mehr aus
//  Apple Health – sonst zaehlt das iPhone in der Hosentasche mit. Die
//  Entscheidung faellt je Metrik und Quelle, nicht pauschal je Anbieter.
//

import Foundation

/// Eine Regel: diese Metrik von dieser Quelle annehmen – oder eben nicht.
struct MetricSourcePolicy: Hashable, Sendable, Codable {
    var userID: String
    var metricID: MetricID
    var provider: ProviderCode
    /// Genauere Quelle innerhalb des Anbieters, etwa die App-Bundle-ID in
    /// Apple Health (`com.garmin.connect.mobile`). Leer = alle Quellen
    /// dieses Anbieters.
    var sourceAppID: String
    var enabled: Bool
    var updatedAt: Date

    init(userID: String = HealthPitUser.local,
         metricID: MetricID,
         provider: ProviderCode,
         sourceAppID: String = "",
         enabled: Bool,
         updatedAt: Date = Date()) {
        self.userID = userID
        self.metricID = metricID
        self.provider = provider
        self.sourceAppID = sourceAppID
        self.enabled = enabled
        self.updatedAt = updatedAt
    }

    /// Gilt fuer alle Quellen des Anbieters.
    var isProviderWide: Bool { sourceAppID.isEmpty }

    init?(row: SQLRow) {
        guard let metricRaw = row.string("metric_id"),
              let metricID = MetricID(validating: metricRaw),
              let providerRaw = row.string("provider"),
              let provider = ProviderCode(validating: providerRaw) else {
            return nil
        }
        self.init(userID: row.string("user_id") ?? HealthPitUser.local,
                  metricID: metricID,
                  provider: provider,
                  sourceAppID: row.string("source_app_id") ?? "",
                  enabled: row.bool("enabled") ?? true,
                  updatedAt: row.date("updated_at") ?? Date())
    }
}

/// Eine Zeile des Entitaetenkatalogs: welche Quelle liefert welche Metrik –
/// und wie viel davon ist bereits angekommen.
struct MetricSourceUsage: Hashable, Sendable, Identifiable {
    var id: String { "\(metricID)|\(originProvider)|\(ingestProvider)|\(sourceAppID ?? "")" }

    let metricID: MetricID
    /// Wo der Wert entstanden ist.
    let originProvider: ProviderCode
    /// Ueber welchen Weg er hereinkam.
    let ingestProvider: ProviderCode
    /// App/Geraet, so wie die Plattform sie nennt.
    let sourceAppID: String?
    let sourceDeviceModel: String?
    let observationCount: Int
    let firstSeen: Date?
    let lastSeen: Date?
    let unit: UnitCode?

    init?(row: SQLRow) {
        guard let metricRaw = row.string("metric_id"),
              let metricID = MetricID(validating: metricRaw),
              let originRaw = row.string("origin_provider"),
              let origin = ProviderCode(validating: originRaw),
              let ingestRaw = row.string("ingest_provider"),
              let ingest = ProviderCode(validating: ingestRaw) else {
            return nil
        }
        self.metricID = metricID
        originProvider = origin
        ingestProvider = ingest
        sourceAppID = row.string("source_app_id")
        sourceDeviceModel = row.string("source_device_model")
        observationCount = row.int("observation_count") ?? 0
        firstSeen = row.date("first_seen")
        lastSeen = row.date("last_seen")
        unit = row.string("unit").map { UnitCode($0) }
    }
}

/// Ein zusammengefuehrter Wert – und das, worin er aufgegangen ist.
struct MergedObservation: Sendable, Identifiable {
    var id: ObservationID { duplicate.observationID }
    let duplicate: HealthObservation
    /// `nil`, wenn der verbleibende Wert inzwischen selbst geloescht wurde.
    let survivor: HealthObservation?
    let reason: String
}

/// Mehrere Quellen beliefern denselben Wert und denselben Zeitraum.
///
/// Fachlich in Ordnung – Garmin und Apple duerfen beide einen Tagesschritt-
/// wert haben. Gefaehrlich wird es erst beim Addieren.
struct OverlappingSourceWarning: Sendable, Identifiable, Hashable {
    var id: String { "\(metricID)|\(periodType.rawValue)" }
    let metricID: MetricID
    let periodType: PeriodType
    let providers: [ProviderCode]
    let observationCount: Int
}
