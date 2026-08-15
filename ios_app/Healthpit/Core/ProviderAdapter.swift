//
//  ProviderAdapter.swift
//  HealthPitCore
//
//  Anbieterspezifisches bleibt hier drin. Der Kern kennt nur diese beiden
//  Formen: was hereinkommt (`IncomingObservation`) und was hinausgeht
//  (`ExportPayload`).
//

import Foundation

/// Ein Datensatz, wie ihn ein Adapter aus einer Anbieterantwort formt –
/// bereits mit allem, was HealthPit fuer die Wiedererkennung braucht, aber
/// noch ohne interne ID.
struct IncomingObservation: Hashable, Sendable {
    /// Bezeichnung des Werts beim Anbieter. Wird ueber das Mapping zur
    /// Metric ID; ist `metricID` gesetzt, hat der Adapter schon uebersetzt.
    var sourceMetric: String
    var metricID: MetricID?

    var value: Double?
    var valueText: String?
    /// Roher Code des Anbieters; wird ueber `valueMapping` uebersetzt.
    var valueCode: String?
    var valueBoolean: Bool?
    var unit: UnitCode?

    var startTime: Date
    var endTime: Date
    var timezone: String?
    var aggregation: Aggregation
    var periodType: PeriodType

    /// Wer den Wert erzeugt hat. `nil`, wenn die Plattform nichts darueber
    /// sagt – dann gilt der einliefernde Anbieter als Erzeuger.
    var originProvider: ProviderCode?
    /// Record-ID beim urspruenglichen Erzeuger, falls durchgereicht.
    var originExternalID: String?

    /// ID, unter der der einliefernde Anbieter den Datensatz fuehrt.
    var externalRecordID: String?
    /// Unser eigener Marker, falls der Datensatz von uns stammt.
    var syncIdentifier: String?
    var syncVersion: Int?

    var sourceAppID: String?
    var sourceDeviceID: String?
    var sourceDeviceModel: String?

    var workoutID: WorkoutID?
    var sessionID: String?

    /// Der Anbieter meldet den Datensatz als geloescht.
    var isDeleted: Bool

    var metadata: [String: String]
    var rawPayload: String?

    init(sourceMetric: String,
         metricID: MetricID? = nil,
         value: Double? = nil,
         valueText: String? = nil,
         valueCode: String? = nil,
         valueBoolean: Bool? = nil,
         unit: UnitCode? = nil,
         startTime: Date,
         endTime: Date,
         timezone: String? = TimeZone.current.identifier,
         aggregation: Aggregation = .raw,
         periodType: PeriodType = .instant,
         originProvider: ProviderCode? = nil,
         originExternalID: String? = nil,
         externalRecordID: String? = nil,
         syncIdentifier: String? = nil,
         syncVersion: Int? = nil,
         sourceAppID: String? = nil,
         sourceDeviceID: String? = nil,
         sourceDeviceModel: String? = nil,
         workoutID: WorkoutID? = nil,
         sessionID: String? = nil,
         isDeleted: Bool = false,
         metadata: [String: String] = [:],
         rawPayload: String? = nil) {
        self.sourceMetric = sourceMetric
        self.metricID = metricID
        self.value = value
        self.valueText = valueText
        self.valueCode = valueCode
        self.valueBoolean = valueBoolean
        self.unit = unit
        self.startTime = startTime
        self.endTime = endTime
        self.timezone = timezone
        self.aggregation = aggregation
        self.periodType = periodType
        self.originProvider = originProvider
        self.originExternalID = originExternalID
        self.externalRecordID = externalRecordID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.sourceAppID = sourceAppID
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceModel = sourceDeviceModel
        self.workoutID = workoutID
        self.sessionID = sessionID
        self.isDeleted = isDeleted
        self.metadata = metadata
        self.rawPayload = rawPayload
    }
}

/// Eingehendes Workout eines Anbieters.
struct IncomingWorkout: Hashable, Sendable {
    var sportType: String
    var title: String?
    var notes: String?
    var startTime: Date
    var endTime: Date
    var timezone: String?
    var originProvider: ProviderCode?
    /// Record-ID beim urspruenglichen Erzeuger, falls die einliefernde
    /// Plattform sie durchreicht – in Apple Health etwa
    /// `HKMetadataKeyExternalUUID`.
    var originExternalID: String?
    var externalRecordID: String?
    var syncIdentifier: String?
    var sourceAppID: String?
    var sourceDeviceID: String?
    var sourceDeviceModel: String?
    var isDeleted: Bool
    var metadata: [String: String]
    var rawPayload: String?
    /// Messwerte, die zum Workout gehoeren; bekommen dessen `workout_id`.
    var observations: [IncomingObservation]

    init(sportType: String,
         title: String? = nil,
         notes: String? = nil,
         startTime: Date,
         endTime: Date,
         timezone: String? = TimeZone.current.identifier,
         originProvider: ProviderCode? = nil,
         originExternalID: String? = nil,
         externalRecordID: String? = nil,
         syncIdentifier: String? = nil,
         sourceAppID: String? = nil,
         sourceDeviceID: String? = nil,
         sourceDeviceModel: String? = nil,
         isDeleted: Bool = false,
         metadata: [String: String] = [:],
         rawPayload: String? = nil,
         observations: [IncomingObservation] = []) {
        self.sportType = sportType
        self.title = title
        self.notes = notes
        self.startTime = startTime
        self.endTime = endTime
        self.timezone = timezone
        self.originProvider = originProvider
        self.originExternalID = originExternalID
        self.externalRecordID = externalRecordID
        self.syncIdentifier = syncIdentifier
        self.sourceAppID = sourceAppID
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceModel = sourceDeviceModel
        self.isDeleted = isDeleted
        self.metadata = metadata
        self.rawPayload = rawPayload
        self.observations = observations
    }
}

/// Was der Export einem Adapter uebergibt.
struct ExportPayload: Hashable, Sendable {
    let observation: HealthObservation
    /// Bezeichnung der Metrik beim Zielanbieter (aus dem Mapping).
    let targetMetric: String
    /// Wert in der Einheit, die der Zielanbieter erwartet.
    let value: Double?
    let unit: UnitCode?
    let valueCode: String?
    /// `HEALTHPIT:OBS-…` – muss der Adapter mitschreiben, wenn der Anbieter
    /// ein Feld dafuer hat.
    let syncIdentifier: String
    let syncVersion: Int
    /// Beim Update: die ID, unter der der Anbieter den Datensatz fuehrt.
    let externalRecordID: String?
}

/// Ergebnis eines Schreibvorgangs beim Anbieter.
struct ExportOutcome: Hashable, Sendable {
    /// Vom Anbieter vergebene ID – falls er eine zurueckgibt.
    var externalRecordID: String?
    var syncVersion: Int?
    var metadata: [String: String]

    init(externalRecordID: String? = nil, syncVersion: Int? = nil, metadata: [String: String] = [:]) {
        self.externalRecordID = externalRecordID
        self.syncVersion = syncVersion
        self.metadata = metadata
    }
}

/// Was jeder Anbieter koennen muss.
///
/// Absichtlich klein gehalten: Lesen und Schreiben von Datensaetzen plus die
/// Mappings, die der Adapter mitbringt. Alles Weitere – Auth, Pagination,
/// Ratenbegrenzung – bleibt Sache der jeweiligen Implementierung.
protocol ProviderAdapter: Sendable {
    var provider: ProviderCode { get }

    /// Mappings, die dieser Adapter beim Start in die Registry schreibt.
    var mappings: [ProviderMetricMapping] { get }

    /// Zusaetzliche Metriken, die nur dieser Anbieter kennt (proprietaere
    /// Scores). Werden beim Registrieren in die Metric Registry aufgenommen.
    var additionalMetrics: [MetricDefinition] { get }

    /// Erkennt der Adapter den Datensatz als etwas, das HealthPit selbst
    /// dorthin geschrieben hat? Ergaenzt die Sync-Identifier-Pruefung um
    /// anbieterspezifisches Wissen (z. B. die Quell-App in HealthKit).
    func isSelfWritten(_ incoming: IncomingObservation) -> Bool

    /// Schreibt einen Datensatz beim Anbieter an.
    func write(_ payload: ExportPayload, action: SyncAction) async throws -> ExportOutcome

    /// Loescht einen Datensatz beim Anbieter.
    func delete(externalRecordID: String, syncIdentifier: String?) async throws
}

extension ProviderAdapter {
    var additionalMetrics: [MetricDefinition] { [] }

    func isSelfWritten(_ incoming: IncomingObservation) -> Bool {
        SyncIdentifier.isHealthPitOwned(incoming.syncIdentifier)
    }
}
