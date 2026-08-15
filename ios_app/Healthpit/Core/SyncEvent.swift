//
//  SyncEvent.swift
//  HealthPitCore
//
//  Protokoll dessen, was eine Synchronisation mit einem Datensatz gemacht
//  hat. Ohne das laesst sich spaeter nicht klaeren, warum ein Wert fehlt,
//  doppelt ist oder nicht beim Anbieter ankam.
//

import Foundation

enum SyncDirection: String, Sendable, Codable {
    case importing = "IMPORT"
    case exporting = "EXPORT"
}

/// Was mit dem Datensatz passiert ist.
enum SyncAction: String, Sendable, Codable {
    case create = "CREATE"
    case update = "UPDATE"
    case unchanged = "UNCHANGED"
    case delete = "DELETE"
    case skip = "SKIP"
    /// Eingehender Datensatz wurde einer bestehenden Observation zugeordnet.
    case deduplicate = "DEDUPLICATE"
    /// Eingehender Datensatz war ein eigener Export – Schleife gestoppt.
    case loopBlocked = "LOOP_BLOCKED"
}

enum SyncStatus: String, Sendable, Codable {
    case ok = "OK"
    case error = "ERROR"
}

struct SyncEvent: Hashable, Sendable, Codable, Identifiable {
    var id: Int64?
    var entityType: ReferenceEntity
    /// Leer, wenn ein eingehender Datensatz verworfen wurde, bevor er eine
    /// interne ID bekommen konnte.
    var entityID: String?
    var provider: ProviderCode
    var direction: SyncDirection
    var action: SyncAction
    var status: SyncStatus
    var externalRecordID: String?
    var createdAt: Date
    var completedAt: Date?
    var errorCode: String?
    var errorMessage: String?
    var metadata: [String: String]

    init(id: Int64? = nil,
         entityType: ReferenceEntity = .observation,
         entityID: String? = nil,
         provider: ProviderCode,
         direction: SyncDirection,
         action: SyncAction,
         status: SyncStatus = .ok,
         externalRecordID: String? = nil,
         createdAt: Date = Date(),
         completedAt: Date? = Date(),
         errorCode: String? = nil,
         errorMessage: String? = nil,
         metadata: [String: String] = [:]) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.provider = provider
        self.direction = direction
        self.action = action
        self.status = status
        self.externalRecordID = externalRecordID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}
