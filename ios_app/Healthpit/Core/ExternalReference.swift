//
//  ExternalReference.swift
//  HealthPitCore
//
//  Eine Observation kann bei mehreren Anbietern gleichzeitig existieren.
//  Diese Zuordnung haelt fest, unter welcher fremden ID – und ist damit die
//  Grundlage fuer Idempotenz, Updates und Schleifenschutz.
//

import Foundation

/// Welche interne Entitaet die Referenz beschreibt.
///
/// Eine gemeinsame Tabelle statt je einer fuer Observations und Workouts:
/// Die Felder waeren identisch, und Import wie Export brauchen dieselben
/// Abfragen. Zwei Tabellen waeren doppelte Pflege ohne Gegenwert.
enum ReferenceEntity: String, Sendable, Codable {
    case observation = "OBSERVATION"
    case workout = "WORKOUT"
}

enum ReferenceStatus: String, Sendable, Codable {
    /// Beim Anbieter vorhanden und aktuell.
    case active = "ACTIVE"
    /// Export vorgemerkt, aber noch nicht bestaetigt.
    case pending = "PENDING"
    /// Beim Anbieter geloescht. Die interne Observation bleibt bestehen,
    /// solange die Sync-Policy das nicht ausdruecklich anders vorsieht.
    case deletedRemote = "DELETED_REMOTE"
}

struct ExternalReference: Hashable, Sendable, Codable, Identifiable {
    /// Zeilen-ID der Datenbank (erst nach dem Speichern gesetzt).
    var id: Int64?
    var userID: String
    var entityType: ReferenceEntity
    /// `observation_id` bzw. `workout_id` als Text.
    var entityID: String
    var provider: ProviderCode

    /// ID, die der Anbieter vergeben hat.
    var externalRecordID: String?
    /// Unser eigener Marker, den wir beim Export mitgegeben haben.
    var syncIdentifier: String?
    var syncVersion: Int?

    var status: ReferenceStatus
    /// Inhaltsstand, der zuletzt zu diesem Anbieter geschrieben wurde.
    /// Damit entscheidet der Export SKIP gegen UPDATE, ohne raten zu muessen.
    var exportedContentHash: String?

    var firstSeenAt: Date
    var lastSeenAt: Date
    var importedAt: Date?
    var exportedAt: Date?
    var deletedAt: Date?

    var metadata: [String: String]

    init(id: Int64? = nil,
         userID: String = HealthPitUser.local,
         entityType: ReferenceEntity = .observation,
         entityID: String,
         provider: ProviderCode,
         externalRecordID: String? = nil,
         syncIdentifier: String? = nil,
         syncVersion: Int? = nil,
         status: ReferenceStatus = .active,
         exportedContentHash: String? = nil,
         firstSeenAt: Date = Date(),
         lastSeenAt: Date = Date(),
         importedAt: Date? = nil,
         exportedAt: Date? = nil,
         deletedAt: Date? = nil,
         metadata: [String: String] = [:]) {
        self.id = id
        self.userID = userID
        self.entityType = entityType
        self.entityID = entityID
        self.provider = provider
        self.externalRecordID = externalRecordID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.status = status
        self.exportedContentHash = exportedContentHash
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.importedAt = importedAt
        self.exportedAt = exportedAt
        self.deletedAt = deletedAt
        self.metadata = metadata
    }

    var observationID: ObservationID? {
        entityType == .observation ? ObservationID(entityID) : nil
    }

    var workoutID: WorkoutID? {
        entityType == .workout ? WorkoutID(entityID) : nil
    }
}
