//
//  ImportPipeline.swift
//  HealthPitCore
//
//  Der Weg eines fremden Datensatzes in die Datenbank – in genau der
//  Reihenfolge, in der Wiedererkennung sicher ist:
//
//  1. eigener HealthPit-Sync-Identifier   (Beweis)
//  2. bekannte externe Record-ID          (Beweis)
//  3. bekannte urspruengliche Herkunft    (Beweis)
//  4. kontrollierte Heuristik             (Indiz, wird als solches vermerkt)
//
//  Erst wenn alle vier nichts finden, entsteht eine neue Observation.
//

import Foundation

/// Wie mit einer Loeschung beim Anbieter umgegangen wird.
enum DeletePolicy: String, Sendable {
    /// Nur der urspruengliche Erzeuger darf die Observation loeschen.
    /// Dass eine Kopie in Apple Health verschwindet, loescht nicht den
    /// Garmin-Wert dahinter.
    case originProviderOnly = "ORIGIN_ONLY"
    /// Jede Loeschmeldung loescht die Observation weich.
    case anyProvider = "ANY"
    /// Loeschungen werden nur an der Referenz vermerkt.
    case referenceOnly = "REFERENCE_ONLY"
}

struct ImportResult: Sendable, Equatable {
    var action: SyncAction
    var observationID: ObservationID?
    var workoutID: WorkoutID?
    /// Bei DEDUPLICATE: worauf die Zuordnung beruht.
    var matchedBy: MatchEvidence?
    var message: String?
}

/// Womit ein eingehender Datensatz wiedererkannt wurde.
enum MatchEvidence: String, Sendable {
    case syncIdentifier = "SYNC_IDENTIFIER"
    case externalRecordID = "EXTERNAL_RECORD_ID"
    case originRecordID = "ORIGIN_RECORD_ID"
    /// Gleiche Metrik, gleiche Herkunft, gleicher abgeschlossener Zeitraum –
    /// also derselbe zusammengefasste Wert in einem neueren Stand.
    case periodAggregate = "PERIOD_AGGREGATE"
    case heuristic = "HEURISTIC"
}

struct ImportOptions: Sendable {
    var deletePolicy: DeletePolicy = .originProviderOnly
    /// Unbekannte Anbieter-Metriken als provisorische Metrik aufnehmen,
    /// statt den Wert zu verwerfen.
    var keepUnmappedAsProvisional: Bool = true
    /// Zeitliche Toleranz der Heuristik.
    var heuristicTimeTolerance: TimeInterval = 1
    /// Relative Toleranz beim Wertvergleich der Heuristik.
    var heuristicValueTolerance: Double = 1e-6

    init() {}
}

struct ImportPipeline: Sendable {
    let store: HealthPitStore
    var options: ImportOptions

    init(store: HealthPitStore, options: ImportOptions = ImportOptions()) {
        self.store = store
        self.options = options
    }

    // MARK: - Observation

    @discardableResult
    func `import`(_ incoming: IncomingObservation,
                 from ingestProvider: ProviderCode,
                 adapter: ProviderAdapter? = nil,
                 userID: String = HealthPitUser.local) async throws -> ImportResult {

        // Stufe 1: Ist das unser eigener Export?
        if let observationID = SyncIdentifier.observationID(from: incoming.syncIdentifier) {
            return try await confirmOwnExport(observationID: observationID,
                                              incoming: incoming,
                                              ingestProvider: ingestProvider,
                                              userID: userID)
        }
        // Manche Anbieter reichen den Marker nicht als Sync-ID durch, aber der
        // Adapter erkennt die Quelle (z. B. „von dieser App geschrieben“).
        if let adapter, adapter.isSelfWritten(incoming), incoming.externalRecordID == nil {
            try await store.append(SyncEvent(provider: ingestProvider,
                                             direction: .importing,
                                             action: .loopBlocked,
                                             metadata: ["reason": "self_written_without_sync_id"]))
            return ImportResult(action: .loopBlocked,
                                observationID: nil,
                                matchedBy: .syncIdentifier,
                                message: "Von HealthPit geschriebener Datensatz ohne Sync-ID – ignoriert.")
        }

        let resolved = try await resolveMetric(incoming, provider: ingestProvider)
        guard let metricID = resolved.metricID else {
            try await store.append(SyncEvent(provider: ingestProvider,
                                             direction: .importing,
                                             action: .skip,
                                             status: .error,
                                             externalRecordID: incoming.externalRecordID,
                                             errorCode: "UNMAPPED_METRIC",
                                             errorMessage: incoming.sourceMetric))
            return ImportResult(action: .skip, message: "Kein Mapping fuer \(incoming.sourceMetric)")
        }

        // Quellenfreigabe: Was der Nutzer im Entitaetenkatalog abgeschaltet
        // hat, kommt gar nicht erst herein. Bewusst nach der Metrikaufloesung
        // – vorher waere nicht klar, worum es geht – und vor allem anderen,
        // damit auch Updates einer abgeschalteten Quelle draussen bleiben.
        let sourceProvider = incoming.originProvider ?? ingestProvider
        let sourceAllowed = try await store.isSourceEnabled(metricID: metricID,
                                                            provider: sourceProvider,
                                                            sourceAppID: incoming.sourceAppID,
                                                            userID: userID)
        if !sourceAllowed {
            try await store.append(SyncEvent(provider: ingestProvider,
                                             direction: .importing,
                                             action: .skip,
                                             externalRecordID: incoming.externalRecordID,
                                             metadata: [
                                                "reason": "source_disabled",
                                                "metric_id": metricID.rawValue,
                                                "provider": sourceProvider.rawValue,
                                                "source_app_id": incoming.sourceAppID ?? ""
                                             ]))
            return ImportResult(action: .skip,
                                message: "Quelle \(sourceProvider) ist fuer \(metricID) abgeschaltet")
        }

        let candidate = try await makeObservation(from: incoming,
                                                  metricID: metricID,
                                                  mapping: resolved.mapping,
                                                  reviewState: resolved.reviewState,
                                                  ingestProvider: ingestProvider,
                                                  userID: userID)

        // Stufe 2: bekannte externe Record-ID dieses Anbieters.
        if let externalRecordID = incoming.externalRecordID,
           let reference = try await store.reference(provider: ingestProvider,
                                                     externalRecordID: externalRecordID,
                                                     userID: userID),
           let observationID = reference.observationID,
           let existing = try await store.observation(observationID) {
            return try await applyUpdate(existing: existing,
                                         candidate: candidate,
                                         incoming: incoming,
                                         reference: reference,
                                         ingestProvider: ingestProvider,
                                         evidence: .externalRecordID)
        }

        // Stufe 3: derselbe Wert, schon ueber seinen Erzeuger importiert.
        if let originExternalID = incoming.originExternalID,
           let originProvider = incoming.originProvider,
           originProvider != ingestProvider {
            let matches = try await store.observations(originProvider: originProvider,
                                                       originExternalID: originExternalID,
                                                       userID: userID)
            if let existing = matches.first(where: { $0.metricID == metricID }) {
                return try await link(existing: existing,
                                      incoming: incoming,
                                      ingestProvider: ingestProvider,
                                      evidence: .originRecordID,
                                      userID: userID)
            }
        }

        // Stufe 4: Zusammenfassungen eines Zeitraums.
        //
        // Ein Tageswert oder eine Nacht ist durch ihren Zeitraum bestimmt,
        // nicht durch die Zahl darin. Kommt derselbe Zeitraum mit einer
        // anderen Zahl, ist das ein neuer Stand – sonst stuenden am Ende
        // Zwischenstaende und Endstand nebeneinander in der Liste.
        if let existing = try await aggregateMatch(for: candidate, userID: userID) {
            return try await applyUpdate(existing: existing,
                                         candidate: candidate,
                                         incoming: incoming,
                                         reference: nil,
                                         ingestProvider: ingestProvider,
                                         evidence: .periodAggregate)
        }

        // Stufe 5: kontrollierte Heuristik – nur ein Indiz.
        if let existing = try await heuristicMatch(for: candidate, userID: userID) {
            return try await link(existing: existing,
                                  incoming: incoming,
                                  ingestProvider: ingestProvider,
                                  evidence: .heuristic,
                                  userID: userID)
        }

        // Eine Loeschmeldung fuer etwas, das wir nie hatten, legt nichts an.
        if incoming.isDeleted {
            try await store.append(SyncEvent(provider: ingestProvider,
                                             direction: .importing,
                                             action: .skip,
                                             externalRecordID: incoming.externalRecordID,
                                             metadata: ["reason": "delete_for_unknown_record"]))
            return ImportResult(action: .skip, message: "Loeschung fuer unbekannten Datensatz")
        }

        try await store.insert(candidate)
        try await upsertReference(for: candidate,
                                  incoming: incoming,
                                  provider: ingestProvider,
                                  evidence: nil,
                                  userID: userID)
        try await store.append(SyncEvent(entityID: candidate.observationID.rawValue,
                                         provider: ingestProvider,
                                         direction: .importing,
                                         action: .create,
                                         externalRecordID: incoming.externalRecordID))
        return ImportResult(action: .create, observationID: candidate.observationID)
    }

    /// Mehrere Datensaetze am Stueck. Fehler einzelner Werte stoppen den
    /// Rest nicht – sie landen als Fehler-Event im Log.
    @discardableResult
    func `import`(_ batch: [IncomingObservation],
                  from provider: ProviderCode,
                  adapter: ProviderAdapter? = nil,
                  userID: String = HealthPitUser.local) async throws -> [ImportResult] {
        var results: [ImportResult] = []
        for incoming in batch {
            do {
                results.append(try await `import`(incoming, from: provider, adapter: adapter, userID: userID))
            } catch {
                try await store.append(SyncEvent(provider: provider,
                                                 direction: .importing,
                                                 action: .skip,
                                                 status: .error,
                                                 externalRecordID: incoming.externalRecordID,
                                                 errorCode: "IMPORT_FAILED",
                                                 errorMessage: String(describing: error)))
                results.append(ImportResult(action: .skip, message: String(describing: error)))
            }
        }
        return results
    }

    // MARK: - Workout

    @discardableResult
    func `import`(_ incoming: IncomingWorkout,
                  from ingestProvider: ProviderCode,
                  adapter: ProviderAdapter? = nil,
                  userID: String = HealthPitUser.local) async throws -> ImportResult {

        if let workoutID = SyncIdentifier.workoutID(from: incoming.syncIdentifier),
           let existing = try await store.workout(workoutID) {
            try await touchReference(entityType: .workout,
                                     entityID: existing.workoutID.rawValue,
                                     provider: ingestProvider,
                                     externalRecordID: incoming.externalRecordID,
                                     syncIdentifier: incoming.syncIdentifier,
                                     userID: userID)
            try await store.append(SyncEvent(entityType: .workout,
                                             entityID: existing.workoutID.rawValue,
                                             provider: ingestProvider,
                                             direction: .importing,
                                             action: .loopBlocked,
                                             externalRecordID: incoming.externalRecordID))
            return ImportResult(action: .loopBlocked,
                                workoutID: existing.workoutID,
                                matchedBy: .syncIdentifier)
        }

        let origin = incoming.originProvider ?? ingestProvider

        // Dasselbe Training auf einem Umweg: GymPit legt eine Kopie in Apple
        // Health ab und gibt seine eigene ID als HKMetadataKeyExternalUUID
        // mit. Dann gehoert die Kopie zum bereits bekannten Training.
        if let originExternalID = incoming.originExternalID,
           origin != ingestProvider,
           let existing = try await store.workouts(originProvider: origin,
                                                   sourceRecordID: originExternalID,
                                                   userID: userID).first {
            try await touchReference(entityType: .workout,
                                     entityID: existing.workoutID.rawValue,
                                     provider: ingestProvider,
                                     externalRecordID: incoming.externalRecordID,
                                     syncIdentifier: incoming.syncIdentifier,
                                     userID: userID)
            try await store.append(SyncEvent(entityType: .workout,
                                             entityID: existing.workoutID.rawValue,
                                             provider: ingestProvider,
                                             direction: .importing,
                                             action: .deduplicate,
                                             externalRecordID: incoming.externalRecordID,
                                             metadata: ["match": MatchEvidence.originRecordID.rawValue]))
            try await importChildObservations(incoming, workoutID: existing.workoutID,
                                              ingestProvider: ingestProvider, adapter: adapter, userID: userID)
            return ImportResult(action: .deduplicate,
                                workoutID: existing.workoutID,
                                matchedBy: .originRecordID)
        }

        var candidate = StoredWorkout(userID: userID,
                                      sportType: incoming.sportType,
                                      title: incoming.title,
                                      notes: incoming.notes,
                                      startTime: incoming.startTime,
                                      endTime: incoming.endTime,
                                      timezone: incoming.timezone,
                                      originProvider: origin,
                                      ingestProvider: ingestProvider,
                                      sourceRecordID: incoming.externalRecordID,
                                      sourceAppID: incoming.sourceAppID,
                                      sourceDeviceID: incoming.sourceDeviceID,
                                      sourceDeviceModel: incoming.sourceDeviceModel,
                                      deletedAt: incoming.isDeleted ? Date() : nil,
                                      metadata: incoming.metadata,
                                      rawPayload: incoming.rawPayload)

        if let externalRecordID = incoming.externalRecordID,
           let reference = try await store.reference(provider: ingestProvider,
                                                     externalRecordID: externalRecordID,
                                                     userID: userID),
           let workoutID = reference.workoutID,
           var existing = try await store.workout(workoutID) {
            candidate = StoredWorkout(workoutID: existing.workoutID,
                                      userID: existing.userID,
                                      sportType: incoming.sportType,
                                      title: incoming.title ?? existing.title,
                                      notes: incoming.notes ?? existing.notes,
                                      startTime: incoming.startTime,
                                      endTime: incoming.endTime,
                                      timezone: incoming.timezone ?? existing.timezone,
                                      originProvider: existing.originProvider,
                                      ingestProvider: ingestProvider,
                                      sourceRecordID: externalRecordID,
                                      sourceAppID: incoming.sourceAppID ?? existing.sourceAppID,
                                      sourceDeviceID: incoming.sourceDeviceID ?? existing.sourceDeviceID,
                                      sourceDeviceModel: incoming.sourceDeviceModel ?? existing.sourceDeviceModel,
                                      version: existing.version,
                                      createdAt: existing.createdAt,
                                      updatedAt: Date(),
                                      deletedAt: incoming.isDeleted ? (existing.deletedAt ?? Date()) : existing.deletedAt,
                                      metadata: existing.metadata.merging(incoming.metadata) { _, new in new },
                                      rawPayload: incoming.rawPayload ?? existing.rawPayload)

            if candidate.contentHash == existing.contentHash {
                try await touchReference(entityType: .workout,
                                         entityID: existing.workoutID.rawValue,
                                         provider: ingestProvider,
                                         externalRecordID: externalRecordID,
                                         syncIdentifier: reference.syncIdentifier,
                                         userID: userID)
                try await store.append(SyncEvent(entityType: .workout,
                                                 entityID: existing.workoutID.rawValue,
                                                 provider: ingestProvider,
                                                 direction: .importing,
                                                 action: .unchanged,
                                                 externalRecordID: externalRecordID))
                return ImportResult(action: .unchanged,
                                    workoutID: existing.workoutID,
                                    matchedBy: .externalRecordID)
            }

            existing = candidate
            existing.version += 1
            try await store.update(existing)
            try await touchReference(entityType: .workout,
                                     entityID: existing.workoutID.rawValue,
                                     provider: ingestProvider,
                                     externalRecordID: externalRecordID,
                                     syncIdentifier: reference.syncIdentifier,
                                     userID: userID)
            try await store.append(SyncEvent(entityType: .workout,
                                             entityID: existing.workoutID.rawValue,
                                             provider: ingestProvider,
                                             direction: .importing,
                                             action: incoming.isDeleted ? .delete : .update,
                                             externalRecordID: externalRecordID))
            try await importChildObservations(incoming, workoutID: existing.workoutID,
                                              ingestProvider: ingestProvider, adapter: adapter, userID: userID)
            return ImportResult(action: incoming.isDeleted ? .delete : .update,
                                workoutID: existing.workoutID,
                                matchedBy: .externalRecordID)
        }

        try await store.insert(candidate)
        try await store.upsert(ExternalReference(userID: userID,
                                                 entityType: .workout,
                                                 entityID: candidate.workoutID.rawValue,
                                                 provider: ingestProvider,
                                                 externalRecordID: incoming.externalRecordID,
                                                 syncIdentifier: incoming.syncIdentifier,
                                                 importedAt: Date()))
        try await store.append(SyncEvent(entityType: .workout,
                                         entityID: candidate.workoutID.rawValue,
                                         provider: ingestProvider,
                                         direction: .importing,
                                         action: .create,
                                         externalRecordID: incoming.externalRecordID))
        try await importChildObservations(incoming, workoutID: candidate.workoutID,
                                          ingestProvider: ingestProvider, adapter: adapter, userID: userID)
        return ImportResult(action: .create, workoutID: candidate.workoutID)
    }

    private func importChildObservations(_ incoming: IncomingWorkout,
                                         workoutID: WorkoutID,
                                         ingestProvider: ProviderCode,
                                         adapter: ProviderAdapter?,
                                         userID: String) async throws {
        for var child in incoming.observations {
            child.workoutID = workoutID
            if child.originProvider == nil { child.originProvider = incoming.originProvider }
            _ = try await `import`(child, from: ingestProvider, adapter: adapter, userID: userID)
        }
    }

    // MARK: - Stufe 1

    private func confirmOwnExport(observationID: ObservationID,
                                  incoming: IncomingObservation,
                                  ingestProvider: ProviderCode,
                                  userID: String) async throws -> ImportResult {
        guard let existing = try await store.observation(observationID) else {
            // Der Marker zeigt auf etwas, das es hier nicht mehr gibt – etwa
            // nach einem Zuruecksetzen der App. Dann ist es ein normaler
            // fremder Datensatz, aber ohne unseren Marker.
            var cleaned = incoming
            cleaned.syncIdentifier = nil
            cleaned.metadata["healthpit_orphan_sync_id"] = incoming.syncIdentifier ?? ""
            return try await `import`(cleaned, from: ingestProvider, userID: userID)
        }
        try await touchReference(entityType: .observation,
                                 entityID: existing.observationID.rawValue,
                                 provider: ingestProvider,
                                 externalRecordID: incoming.externalRecordID,
                                 syncIdentifier: incoming.syncIdentifier,
                                 syncVersion: incoming.syncVersion,
                                 userID: userID)
        try await store.append(SyncEvent(entityID: existing.observationID.rawValue,
                                         provider: ingestProvider,
                                         direction: .importing,
                                         action: .loopBlocked,
                                         externalRecordID: incoming.externalRecordID,
                                         metadata: ["reason": "own_sync_identifier"]))
        return ImportResult(action: .loopBlocked,
                            observationID: existing.observationID,
                            matchedBy: .syncIdentifier)
    }

    // MARK: - Stufe 2/3/4 – Hilfen

    /// Aktualisiert eine bestehende Observation.
    ///
    /// `reference` ist optional: Bei einem Treffer ueber den Zeitraum gibt es
    /// noch keine externe Referenz, wohl aber eine bestehende Observation.
    private func applyUpdate(existing: HealthObservation,
                             candidate: HealthObservation,
                             incoming: IncomingObservation,
                             reference: ExternalReference?,
                             ingestProvider: ProviderCode,
                             evidence: MatchEvidence) async throws -> ImportResult {
        var updated = existing
        updated.metricID = candidate.metricID
        updated.valueType = candidate.valueType
        updated.valueNumeric = candidate.valueNumeric
        updated.valueText = candidate.valueText
        updated.valueCode = candidate.valueCode
        updated.valueBoolean = candidate.valueBoolean
        updated.unit = candidate.unit
        updated.sourceValue = candidate.sourceValue
        updated.sourceUnit = candidate.sourceUnit
        updated.startTime = candidate.startTime
        updated.endTime = candidate.endTime
        updated.timezone = candidate.timezone ?? existing.timezone
        updated.aggregation = candidate.aggregation
        updated.periodType = candidate.periodType
        updated.sourceMetric = candidate.sourceMetric ?? existing.sourceMetric
        updated.sourceAppID = candidate.sourceAppID ?? existing.sourceAppID
        updated.sourceDeviceID = candidate.sourceDeviceID ?? existing.sourceDeviceID
        updated.sourceDeviceModel = candidate.sourceDeviceModel ?? existing.sourceDeviceModel
        updated.workoutID = candidate.workoutID ?? existing.workoutID
        updated.metadata.merge(candidate.metadata) { _, new in new }
        updated.rawPayload = candidate.rawPayload ?? existing.rawPayload

        if incoming.isDeleted, let reference {
            return try await applyDelete(existing: updated,
                                         reference: reference,
                                         ingestProvider: ingestProvider)
        }

        guard updated.contentHash != existing.contentHash else {
            try await touchReference(entityType: .observation,
                                     entityID: existing.observationID.rawValue,
                                     provider: ingestProvider,
                                     externalRecordID: incoming.externalRecordID,
                                     syncIdentifier: reference?.syncIdentifier,
                                     syncVersion: incoming.syncVersion,
                                     userID: existing.userID)
            try await store.append(SyncEvent(entityID: existing.observationID.rawValue,
                                             provider: ingestProvider,
                                             direction: .importing,
                                             action: .unchanged,
                                             externalRecordID: incoming.externalRecordID))
            return ImportResult(action: .unchanged,
                                observationID: existing.observationID,
                                matchedBy: evidence)
        }

        updated.version += 1
        updated.updatedAt = Date()
        try await store.update(updated)
        try await touchReference(entityType: .observation,
                                 entityID: existing.observationID.rawValue,
                                 provider: ingestProvider,
                                 externalRecordID: incoming.externalRecordID,
                                 syncIdentifier: reference?.syncIdentifier,
                                 syncVersion: incoming.syncVersion,
                                 userID: existing.userID)
        try await store.append(SyncEvent(entityID: existing.observationID.rawValue,
                                         provider: ingestProvider,
                                         direction: .importing,
                                         action: .update,
                                         externalRecordID: incoming.externalRecordID))
        return ImportResult(action: .update,
                            observationID: existing.observationID,
                            matchedBy: evidence)
    }

    private func applyDelete(existing: HealthObservation,
                             reference: ExternalReference,
                             ingestProvider: ProviderCode) async throws -> ImportResult {
        var updatedReference = reference
        updatedReference.status = .deletedRemote
        updatedReference.deletedAt = Date()
        updatedReference.lastSeenAt = Date()
        try await store.upsert(updatedReference)

        let deletesObservation: Bool
        switch options.deletePolicy {
        case .anyProvider:
            deletesObservation = true
        case .originProviderOnly:
            deletesObservation = existing.originProvider == ingestProvider
        case .referenceOnly:
            deletesObservation = false
        }

        if deletesObservation, existing.deletedAt == nil {
            var deleted = existing
            deleted.deletedAt = Date()
            deleted.updatedAt = Date()
            deleted.version += 1
            try await store.update(deleted)
        }

        try await store.append(SyncEvent(entityID: existing.observationID.rawValue,
                                         provider: ingestProvider,
                                         direction: .importing,
                                         action: .delete,
                                         externalRecordID: reference.externalRecordID,
                                         metadata: [
                                            "policy": options.deletePolicy.rawValue,
                                            "observation_deleted": deletesObservation ? "1" : "0"
                                         ]))
        return ImportResult(action: .delete,
                            observationID: existing.observationID,
                            matchedBy: .externalRecordID,
                            message: deletesObservation
                                ? "Observation weich geloescht"
                                : "Nur die Referenz beim Anbieter wurde geloescht")
    }

    /// Bestehende Observation mit einem weiteren Anbieter verknuepfen.
    private func link(existing: HealthObservation,
                      incoming: IncomingObservation,
                      ingestProvider: ProviderCode,
                      evidence: MatchEvidence,
                      userID: String) async throws -> ImportResult {
        var metadata: [String: String] = ["match": evidence.rawValue]
        if evidence == .heuristic {
            // Ausdruecklich als Indiz gekennzeichnet: Wer die Daten spaeter
            // prueft, soll sehen, dass hier keine ID im Spiel war.
            metadata["confidence"] = "heuristic"
        }
        try await store.upsert(ExternalReference(userID: userID,
                                                 entityType: .observation,
                                                 entityID: existing.observationID.rawValue,
                                                 provider: ingestProvider,
                                                 externalRecordID: incoming.externalRecordID,
                                                 syncIdentifier: incoming.syncIdentifier,
                                                 syncVersion: incoming.syncVersion,
                                                 importedAt: Date(),
                                                 metadata: metadata))
        try await store.append(SyncEvent(entityID: existing.observationID.rawValue,
                                         provider: ingestProvider,
                                         direction: .importing,
                                         action: .deduplicate,
                                         externalRecordID: incoming.externalRecordID,
                                         metadata: metadata))
        return ImportResult(action: .deduplicate,
                            observationID: existing.observationID,
                            matchedBy: evidence)
    }

    /// Sucht dieselbe Zusammenfassung: gleiche Metrik, gleiche Herkunft,
    /// gleicher Zeitraum. Der Wert bleibt bewusst aussen vor – genau er darf
    /// sich ja aendern.
    private func aggregateMatch(for candidate: HealthObservation,
                                userID: String) async throws -> HealthObservation? {
        guard candidate.periodType.summarisesPeriod else { return nil }

        let window = options.heuristicTimeTolerance
        let neighbours = try await store.observations(metricID: candidate.metricID,
                                                      from: candidate.startTime.addingTimeInterval(-window),
                                                      to: candidate.endTime.addingTimeInterval(window),
                                                      userID: userID)
        return neighbours.first { existing in
            guard existing.originProvider == candidate.originProvider,
                  existing.aggregation == candidate.aggregation,
                  existing.periodType == candidate.periodType,
                  // Zwei Workouts zur selben Zeit sind zwei Workouts.
                  existing.workoutID == candidate.workoutID,
                  abs(existing.startTime.timeIntervalSince(candidate.startTime)) <= window,
                  abs(existing.endTime.timeIntervalSince(candidate.endTime)) <= window else {
                return false
            }
            // Zwei Geraete duerfen denselben Tag getrennt zusammenfassen.
            if let left = existing.sourceDeviceID, let right = candidate.sourceDeviceID, left != right {
                return false
            }
            return true
        }
    }

    private func heuristicMatch(for candidate: HealthObservation,
                                userID: String) async throws -> HealthObservation? {
        // Erst der exakte Schluessel – gleiche Metrik, Herkunft, Geraet, Zeit,
        // Wert und Einheit.
        let strict = try await store.observations(heuristicKey: candidate.heuristicKey, userID: userID)
        if let match = strict.first {
            return match
        }

        // Dann der Fall „derselbe Wert ueber einen anderen Weg“: Herkunft und
        // Metrik muessen stimmen, Zeitpunkt und Wert praktisch identisch sein.
        // Ohne gleiche Herkunft wird hier nichts zusammengefuehrt.
        let window = options.heuristicTimeTolerance
        let neighbours = try await store.observations(metricID: candidate.metricID,
                                                      from: candidate.startTime.addingTimeInterval(-window),
                                                      to: candidate.endTime.addingTimeInterval(window),
                                                      userID: userID)
        return neighbours.first { existing in
            guard existing.originProvider == candidate.originProvider,
                  existing.aggregation == candidate.aggregation,
                  existing.periodType == candidate.periodType,
                  existing.unit == candidate.unit,
                  abs(existing.startTime.timeIntervalSince(candidate.startTime)) <= window,
                  abs(existing.endTime.timeIntervalSince(candidate.endTime)) <= window else {
                return false
            }
            // Geraetekennungen duerfen fehlen (die Plattform reicht sie nicht
            // immer durch), aber zwei verschiedene Geraete sind zwei Messungen.
            if let left = existing.sourceDeviceID, let right = candidate.sourceDeviceID, left != right {
                return false
            }
            return valuesMatch(existing, candidate)
        }
    }

    private func valuesMatch(_ lhs: HealthObservation, _ rhs: HealthObservation) -> Bool {
        if let left = lhs.valueNumeric, let right = rhs.valueNumeric {
            let scale = max(abs(left), abs(right), 1)
            return abs(left - right) <= options.heuristicValueTolerance * scale
        }
        if lhs.valueCode != nil || rhs.valueCode != nil { return lhs.valueCode == rhs.valueCode }
        if lhs.valueText != nil || rhs.valueText != nil { return lhs.valueText == rhs.valueText }
        if lhs.valueBoolean != nil || rhs.valueBoolean != nil { return lhs.valueBoolean == rhs.valueBoolean }
        return false
    }

    // MARK: - Aufbereitung

    private struct ResolvedMetric {
        var metricID: MetricID?
        var mapping: ProviderMetricMapping?
        var reviewState: ReviewState = .ok
    }

    private func resolveMetric(_ incoming: IncomingObservation,
                               provider: ProviderCode) async throws -> ResolvedMetric {
        if let metricID = incoming.metricID {
            let mapping = try await store.mapping(provider: provider, sourceMetric: incoming.sourceMetric)
            return ResolvedMetric(metricID: metricID, mapping: mapping)
        }
        if let mapping = try await store.mapping(provider: provider, sourceMetric: incoming.sourceMetric) {
            return ResolvedMetric(metricID: mapping.metricID, mapping: mapping)
        }
        guard options.keepUnmappedAsProvisional,
              let provisional = ProvisionalMetric.make(provider: provider, sourceMetric: incoming.sourceMetric) else {
            return ResolvedMetric(metricID: nil, mapping: nil)
        }
        // Lieber ein provisorischer Eintrag als ein verlorener Messwert. Der
        // Wert bleibt sichtbar als ungeklaert markiert.
        if await store.metricDefinition(provisional.metricID) == nil {
            try await store.registerMetric(provisional)
        }
        return ResolvedMetric(metricID: provisional.metricID,
                              mapping: nil,
                              reviewState: .unresolvedMetric)
    }

    private func makeObservation(from incoming: IncomingObservation,
                                 metricID: MetricID,
                                 mapping: ProviderMetricMapping?,
                                 reviewState: ReviewState,
                                 ingestProvider: ProviderCode,
                                 userID: String) async throws -> HealthObservation {
        let definition = await store.metricDefinition(metricID)
        let valueType = definition?.valueType ?? (incoming.value != nil ? .number : .string)
        let canonicalUnit = mapping?.canonicalUnit ?? definition?.canonicalUnit
        let sourceUnit = incoming.unit ?? mapping?.sourceUnit

        var normalizedValue = incoming.value
        var normalizedUnit = canonicalUnit
        var keptSourceValue: Double?
        var keptSourceUnit: UnitCode?
        var normalizationState = reviewState

        if let rawValue = incoming.value {
            let ruled = (mapping?.rule ?? .identity).apply(rawValue)
            if let sourceUnit, let canonicalUnit, sourceUnit != canonicalUnit {
                if let converted = try? UnitConverter.convert(ruled, from: sourceUnit, to: canonicalUnit) {
                    normalizedValue = converted
                    keptSourceValue = rawValue
                    keptSourceUnit = sourceUnit
                } else {
                    // Nicht umrechenbar: Originalwert behalten und den Fall
                    // sichtbar machen, statt eine falsche Zahl zu speichern.
                    normalizedValue = ruled
                    normalizedUnit = sourceUnit
                    keptSourceValue = rawValue
                    keptSourceUnit = sourceUnit
                    normalizationState = .unresolvedUnit
                }
            } else {
                normalizedValue = ruled
                normalizedUnit = canonicalUnit ?? sourceUnit
                if ruled != rawValue {
                    keptSourceValue = rawValue
                    keptSourceUnit = sourceUnit
                }
            }
        }

        let valueCode = incoming.valueCode.map { code in
            mapping?.valueMapping[code] ?? code
        }

        return HealthObservation(userID: userID,
                                 metricID: metricID,
                                 valueType: valueType,
                                 valueNumeric: normalizedValue,
                                 valueText: incoming.valueText,
                                 valueCode: valueCode,
                                 valueBoolean: incoming.valueBoolean,
                                 unit: normalizedValue == nil ? nil : normalizedUnit,
                                 sourceValue: keptSourceValue,
                                 sourceUnit: keptSourceUnit,
                                 startTime: incoming.startTime,
                                 endTime: incoming.endTime,
                                 timezone: incoming.timezone,
                                 aggregation: incoming.aggregation,
                                 periodType: incoming.periodType,
                                 originProvider: incoming.originProvider ?? ingestProvider,
                                 ingestProvider: ingestProvider,
                                 originExternalID: incoming.originExternalID,
                                 sourceMetric: incoming.sourceMetric,
                                 sourceAppID: incoming.sourceAppID,
                                 sourceDeviceID: incoming.sourceDeviceID,
                                 sourceDeviceModel: incoming.sourceDeviceModel,
                                 workoutID: incoming.workoutID,
                                 sessionID: incoming.sessionID,
                                 reviewState: normalizationState,
                                 metadata: incoming.metadata,
                                 rawPayload: incoming.rawPayload)
    }

    private func upsertReference(for observation: HealthObservation,
                                 incoming: IncomingObservation,
                                 provider: ProviderCode,
                                 evidence: MatchEvidence?,
                                 userID: String) async throws {
        guard incoming.externalRecordID != nil || incoming.syncIdentifier != nil else { return }
        var metadata: [String: String] = [:]
        if let evidence { metadata["match"] = evidence.rawValue }
        try await store.upsert(ExternalReference(userID: userID,
                                                 entityType: .observation,
                                                 entityID: observation.observationID.rawValue,
                                                 provider: provider,
                                                 externalRecordID: incoming.externalRecordID,
                                                 syncIdentifier: incoming.syncIdentifier,
                                                 syncVersion: incoming.syncVersion,
                                                 importedAt: Date(),
                                                 metadata: metadata))
    }

    private func touchReference(entityType: ReferenceEntity,
                                entityID: String,
                                provider: ProviderCode,
                                externalRecordID: String?,
                                syncIdentifier: String?,
                                syncVersion: Int? = nil,
                                userID: String) async throws {
        let existing = try await store.reference(entityType: entityType,
                                                 entityID: entityID,
                                                 provider: provider)
        var reference = existing ?? ExternalReference(userID: userID,
                                                      entityType: entityType,
                                                      entityID: entityID,
                                                      provider: provider)
        reference.externalRecordID = externalRecordID ?? reference.externalRecordID
        reference.syncIdentifier = syncIdentifier ?? reference.syncIdentifier
        reference.syncVersion = syncVersion ?? reference.syncVersion
        reference.lastSeenAt = Date()
        reference.importedAt = Date()
        if reference.status == .deletedRemote { reference.status = .active }
        try await store.upsert(reference)
    }
}

/// Baut eine provisorische Metrik fuer einen Anbieterwert, den noch niemand
/// gemappt hat.
enum ProvisionalMetric {
    static func make(provider: ProviderCode, sourceMetric: String) -> MetricDefinition? {
        let sanitized = sourceMetric
            .uppercased()
            .map { character -> Character in
                (character.isUppercase || character.isNumber) ? character : "_"
            }
            .reduce(into: "") { result, character in
                if character == "_", result.last == "_" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        let raw = "\(provider.rawValue)_\(sanitized)".prefix(64).description
        guard let metricID = MetricID(validating: raw) else { return nil }
        return MetricDefinition(metricID: metricID,
                                category: .proprietary,
                                name: sourceMetric,
                                description: "Automatisch angelegt beim Import von \(provider).",
                                valueType: .number,
                                canonicalUnit: UnitCode.none,
                                isProprietary: true,
                                proprietaryProvider: provider,
                                status: .provisional)
    }
}

private extension MetricDefinition {
    init(metricID: MetricID,
         category: MetricCategory,
         name: String,
         description: String,
         valueType: MetricValueType,
         canonicalUnit: UnitCode?,
         isProprietary: Bool,
         proprietaryProvider: ProviderCode?,
         status: MetricStatus) {
        self.init(metricID,
                  category: category,
                  name: name,
                  description: description,
                  valueType: valueType,
                  canonicalUnit: canonicalUnit,
                  isProprietary: isProprietary,
                  proprietaryProvider: proprietaryProvider,
                  status: status)
    }
}
