//
//  ExportPipeline.swift
//  HealthPitCore
//
//  Der Weg einer Observation zu einem Anbieter. Vor jedem Schreiben steht
//  dieselbe Frage: Gibt es fuer diese observation_id und diesen Provider
//  schon eine External Reference?
//
//      nein                      → CREATE
//      ja, gleicher Stand        → SKIP
//      ja, Observation geaendert → UPDATE
//      Observation geloescht     → DELETE
//
//  Damit laeuft derselbe Exportjob beliebig oft, ohne beim Ziel Kopien
//  anzulegen.
//

import Foundation

struct ExportResult: Sendable, Equatable {
    var action: SyncAction
    var observationID: ObservationID?
    var externalRecordID: String?
    var message: String?
}

struct ExportPipeline: Sendable {
    let store: HealthPitStore

    init(store: HealthPitStore) {
        self.store = store
    }

    @discardableResult
    func export(_ observation: HealthObservation,
                to adapter: ProviderAdapter) async throws -> ExportResult {
        let provider = adapter.provider
        let reference = try await store.reference(entityType: .observation,
                                                  entityID: observation.observationID.rawValue,
                                                  provider: provider)

        // Loeschung zuerst: fuer einen geloeschten Wert gibt es nichts mehr
        // anzulegen oder zu aktualisieren.
        if observation.isDeleted {
            return try await exportDeletion(observation, reference: reference, adapter: adapter)
        }

        // Erst der direkte Treffer auf die Metric ID als Quellbezeichnung,
        // dann die Suche ueber alle Mappings des Anbieters.
        var resolvedMapping = try await store.mapping(provider: provider,
                                                      sourceMetric: observation.metricID.rawValue)
        if resolvedMapping == nil {
            resolvedMapping = try await store.mappings(for: provider)
                .first { $0.metricID == observation.metricID }
        }
        guard let mapping = resolvedMapping else {
            try await store.append(SyncEvent(entityID: observation.observationID.rawValue,
                                             provider: provider,
                                             direction: .exporting,
                                             action: .skip,
                                             status: .error,
                                             errorCode: "NO_MAPPING",
                                             errorMessage: observation.metricID.rawValue))
            return ExportResult(action: .skip,
                                observationID: observation.observationID,
                                message: "Kein Schreib-Mapping fuer \(observation.metricID)")
        }

        guard mapping.canWrite else {
            try await store.append(SyncEvent(entityID: observation.observationID.rawValue,
                                             provider: provider,
                                             direction: .exporting,
                                             action: .skip,
                                             metadata: ["reason": "mapping_read_only"]))
            return ExportResult(action: .skip,
                                observationID: observation.observationID,
                                message: "Mapping erlaubt kein Schreiben")
        }

        // Was von diesem Anbieter kam, wird nicht dorthin zurueckgeschrieben.
        if observation.ingestProvider == provider, reference?.importedAt != nil {
            try await store.append(SyncEvent(entityID: observation.observationID.rawValue,
                                             provider: provider,
                                             direction: .exporting,
                                             action: .skip,
                                             externalRecordID: reference?.externalRecordID,
                                             metadata: ["reason": "originates_from_target"]))
            return ExportResult(action: .skip,
                                observationID: observation.observationID,
                                externalRecordID: reference?.externalRecordID,
                                message: "Wert stammt von diesem Anbieter")
        }

        if let reference,
           reference.status == .active,
           reference.exportedContentHash == observation.contentHash {
            try await store.append(SyncEvent(entityID: observation.observationID.rawValue,
                                             provider: provider,
                                             direction: .exporting,
                                             action: .skip,
                                             externalRecordID: reference.externalRecordID,
                                             metadata: ["reason": "unchanged"]))
            return ExportResult(action: .skip,
                                observationID: observation.observationID,
                                externalRecordID: reference.externalRecordID)
        }

        // Sobald die Anbieter-ID bekannt ist, wird aktualisiert – egal ob wir
        // den Datensatz selbst angelegt oder ihn von dort importiert haben.
        // Sonst entstuende beim Ziel eine zweite Kopie.
        let isUpdate = reference?.externalRecordID != nil
        let payload = try await makePayload(observation,
                                            mapping: mapping,
                                            externalRecordID: reference?.externalRecordID)
        let outcome = try await adapter.write(payload, action: isUpdate ? .update : .create)

        var stored = reference ?? ExternalReference(userID: observation.userID,
                                                    entityType: .observation,
                                                    entityID: observation.observationID.rawValue,
                                                    provider: provider)
        stored.externalRecordID = outcome.externalRecordID ?? stored.externalRecordID
        stored.syncIdentifier = payload.syncIdentifier
        stored.syncVersion = outcome.syncVersion ?? payload.syncVersion
        stored.status = .active
        stored.exportedContentHash = observation.contentHash
        stored.exportedAt = Date()
        stored.lastSeenAt = Date()
        stored.deletedAt = nil
        stored.metadata.merge(outcome.metadata) { _, new in new }
        try await store.upsert(stored)

        let action: SyncAction = isUpdate ? .update : .create
        try await store.append(SyncEvent(entityID: observation.observationID.rawValue,
                                         provider: provider,
                                         direction: .exporting,
                                         action: action,
                                         externalRecordID: stored.externalRecordID))
        return ExportResult(action: action,
                            observationID: observation.observationID,
                            externalRecordID: stored.externalRecordID)
    }

    @discardableResult
    func export(_ observations: [HealthObservation],
                to adapter: ProviderAdapter) async throws -> [ExportResult] {
        var results: [ExportResult] = []
        for observation in observations {
            do {
                results.append(try await export(observation, to: adapter))
            } catch {
                try await store.append(SyncEvent(entityID: observation.observationID.rawValue,
                                                 provider: adapter.provider,
                                                 direction: .exporting,
                                                 action: .skip,
                                                 status: .error,
                                                 errorCode: "EXPORT_FAILED",
                                                 errorMessage: String(describing: error)))
                results.append(ExportResult(action: .skip,
                                            observationID: observation.observationID,
                                            message: String(describing: error)))
            }
        }
        return results
    }

    private func exportDeletion(_ observation: HealthObservation,
                                reference: ExternalReference?,
                                adapter: ProviderAdapter) async throws -> ExportResult {
        guard var reference, reference.status != .deletedRemote else {
            try await store.append(SyncEvent(entityID: observation.observationID.rawValue,
                                             provider: adapter.provider,
                                             direction: .exporting,
                                             action: .skip,
                                             metadata: ["reason": "nothing_to_delete"]))
            return ExportResult(action: .skip, observationID: observation.observationID)
        }
        if let externalRecordID = reference.externalRecordID {
            try await adapter.delete(externalRecordID: externalRecordID,
                                     syncIdentifier: reference.syncIdentifier)
        }
        reference.status = .deletedRemote
        reference.deletedAt = Date()
        reference.lastSeenAt = Date()
        try await store.upsert(reference)
        try await store.append(SyncEvent(entityID: observation.observationID.rawValue,
                                         provider: adapter.provider,
                                         direction: .exporting,
                                         action: .delete,
                                         externalRecordID: reference.externalRecordID))
        return ExportResult(action: .delete,
                            observationID: observation.observationID,
                            externalRecordID: reference.externalRecordID)
    }

    private func makePayload(_ observation: HealthObservation,
                             mapping: ProviderMetricMapping,
                             externalRecordID: String?) async throws -> ExportPayload {
        var value = observation.valueNumeric
        var unit = observation.unit

        // Zurueck in die Einheit, die der Anbieter erwartet – und die
        // Skalenregel rueckwaerts (Prozent zurueck in Anteile).
        if let targetUnit = mapping.sourceUnit, let current = unit, let numeric = value,
           targetUnit != current, let converted = try? UnitConverter.convert(numeric, from: current, to: targetUnit) {
            value = converted
            unit = targetUnit
        }
        let rule = mapping.rule
        if !rule.isIdentity, let numeric = value, rule.factor != 0 {
            value = (numeric - rule.offset) / rule.factor
        }

        let reverseCodes = Dictionary(mapping.valueMapping.map { ($0.value, $0.key) },
                                      uniquingKeysWith: { first, _ in first })
        let code = observation.valueCode.map { reverseCodes[$0] ?? $0 }

        return ExportPayload(observation: observation,
                             targetMetric: mapping.sourceMetric,
                             value: value,
                             unit: unit,
                             valueCode: code,
                             syncIdentifier: SyncIdentifier.make(for: observation.observationID),
                             syncVersion: observation.version,
                             externalRecordID: externalRecordID)
    }
}
