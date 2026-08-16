//
//  DuplicateRepair.swift
//  HealthPitCore
//
//  Aufraeumen nach der ersten Uebernahme.
//
//  Bis die Regel „ein Zeitraum, ein Wert“ stand, konnte derselbe Tag oder
//  dieselbe Nacht mehrfach ankommen – einmal je Zwischenstand aus den alten
//  Caches. Diese Reparatur fasst solche Gruppen wieder zusammen.
//
//  Sie loescht nichts hart: Die unterlegenen Zeilen bekommen `deleted_at` und
//  einen Vermerk, ihre externen Referenzen ziehen zum verbleibenden Wert um.
//  Damit bleibt jede Zeile nachvollziehbar, und ein Fehlgriff waere
//  zurueckdrehbar.
//

import Foundation

struct DuplicateRepairReport: Sendable, Equatable {
    /// Gruppen, in denen mehr als eine Zeile denselben Zeitraum beschrieb.
    var groups = 0
    /// Zeilen, die dabei weich geloescht wurden.
    var mergedObservations = 0
    /// Externe Referenzen, die auf den verbleibenden Wert umgezogen sind.
    var movedReferences = 0
    /// Trainings, die dieselbe Einheit beschrieben.
    var mergedWorkouts = 0

    var didChangeAnything: Bool { mergedObservations > 0 || mergedWorkouts > 0 }
}

struct DuplicateRepair: Sendable {
    static let flagKey = "aggregate_duplicate_repair"
    static let flagValue = "v2"

    let store: HealthPitStore
    var userID: String = HealthPitUser.local

    init(store: HealthPitStore, userID: String = HealthPitUser.local) {
        self.store = store
        self.userID = userID
    }

    /// Laeuft einmal. Danach verhindert die Import-Regel neue Duplikate.
    @discardableResult
    func runIfNeeded() async throws -> DuplicateRepairReport {
        if try await store.migrationFlag(Self.flagKey) == Self.flagValue {
            return DuplicateRepairReport()
        }
        let report = try await run()
        try await store.setMigrationFlag(Self.flagKey, value: Self.flagValue)
        return report
    }

    @discardableResult
    func run() async throws -> DuplicateRepairReport {
        var report = DuplicateRepairReport()

        for group in try await store.duplicatePeriodAggregates(userID: userID) {
            guard group.count > 1 else { continue }
            report.groups += 1

            // Der juengste Stand bleibt. Bei gleichem Zeitstempel entscheidet
            // die hoehere Version, danach die groessere Observation ID – so
            // faellt die Wahl immer gleich aus, egal in welcher Reihenfolge
            // die Zeilen gelesen wurden.
            let sorted = group.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                if lhs.version != rhs.version { return lhs.version > rhs.version }
                return lhs.observationID > rhs.observationID
            }
            guard let survivor = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                for reference in try await store.references(entityType: .observation,
                                                            entityID: duplicate.observationID.rawValue) {
                    var moved = reference
                    moved.entityID = survivor.observationID.rawValue
                    moved.metadata["merged_from"] = duplicate.observationID.rawValue
                    try await store.upsert(moved)
                    report.movedReferences += 1
                }

                var retired = duplicate
                retired.deletedAt = Date()
                retired.updatedAt = Date()
                retired.version += 1
                retired.metadata["merged_into"] = survivor.observationID.rawValue
                retired.metadata["merge_reason"] = "duplicate_period_aggregate"
                try await store.update(retired)
                report.mergedObservations += 1

                try await store.append(SyncEvent(entityID: duplicate.observationID.rawValue,
                                                 provider: duplicate.ingestProvider,
                                                 direction: .importing,
                                                 action: .deduplicate,
                                                 metadata: [
                                                    "reason": "duplicate_period_aggregate",
                                                    "merged_into": survivor.observationID.rawValue,
                                                    "metric_id": duplicate.metricID.rawValue
                                                 ]))
            }
        }

        report.mergedWorkouts = try await mergeSameSessionWorkouts()
        return report
    }

    /// Trainings zusammenfuehren, die dieselbe Einheit beschreiben.
    ///
    /// Health Sync, die Huawei-App und Apple legen denselben Lauf je einmal in
    /// Apple Health ab. Fuer neue Importe faengt das die Erkennung im Import
    /// ab – was vorher schon dreifach in der Datenbank stand, muss einmal
    /// aufgeraeumt werden.
    ///
    /// Behalten wird die aussagekraeftigste Zeile: die mit der genaueren
    /// Sportart, danach die mit den meisten Messwerten. „Sonstiges“ zu
    /// behalten und „Laufen“ zu verwerfen waere die schlechtere Wahl.
    private func mergeSameSessionWorkouts() async throws -> Int {
        let workouts = try await store.workouts(userID: userID)
        var retired = Set<String>()
        var merged = 0

        for workout in workouts {
            let id = workout.workoutID.rawValue
            guard !retired.contains(id) else { continue }

            let overlapping = try await store.workouts(overlapping: workout.startTime,
                                                       end: workout.endTime,
                                                       userID: userID)
            let group = overlapping.filter { candidate in
                guard candidate.workoutID.rawValue != id,
                      !retired.contains(candidate.workoutID.rawValue) else { return false }
                let overlapStart = max(candidate.startTime, workout.startTime)
                let overlapEnd = min(candidate.endTime, workout.endTime)
                let overlap = overlapEnd.timeIntervalSince(overlapStart)
                let shorter = min(candidate.duration, workout.duration)
                guard overlap > 0, shorter > 0 else { return false }
                return overlap / shorter >= 0.8
            }
            guard !group.isEmpty else { continue }

            let all = [workout] + group
            let survivor = try await best(of: all)
            for duplicate in all where duplicate.workoutID != survivor.workoutID {
                for reference in try await store.references(entityType: .workout,
                                                            entityID: duplicate.workoutID.rawValue) {
                    var moved = reference
                    moved.entityID = survivor.workoutID.rawValue
                    moved.metadata["merged_from"] = duplicate.workoutID.rawValue
                    try await store.upsert(moved)
                }
                var gone = duplicate
                gone.deletedAt = Date()
                gone.updatedAt = Date()
                gone.version += 1
                gone.metadata["merged_into"] = survivor.workoutID.rawValue
                gone.metadata["merge_reason"] = "same_session"
                try await store.update(gone)
                retired.insert(duplicate.workoutID.rawValue)
                merged += 1
            }
        }
        return merged
    }

    /// Die aussagekraeftigste Zeile einer Gruppe.
    private func best(of workouts: [StoredWorkout]) async throws -> StoredWorkout {
        var scored: [(StoredWorkout, Int)] = []
        for workout in workouts {
            let values = try await store.observations(workoutID: workout.workoutID).count
            let named = workout.sportType == "OTHER" ? 0 : 1_000
            scored.append((workout, named + values))
        }
        return scored.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.workoutID.rawValue < rhs.0.workoutID.rawValue
        }?.0 ?? workouts[0]
    }
}
