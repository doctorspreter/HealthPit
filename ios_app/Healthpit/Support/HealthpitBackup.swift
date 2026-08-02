//
//  HealthpitBackup.swift
//  Healthpit
//
//  Export und Import der lokalen Daten als Sicherungsdatei.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Everything a Healthpit backup carries.
///
/// Credentials are deliberately absent: a backup is meant to be moved through
/// Files, AirDrop or a cloud folder, and an API token or TOTP secret in a
/// plain file would travel with it. The bridge connection is re-entered after
/// a restore.
nonisolated struct HealthpitBackup: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var deviceID: String
    var username: String
    var workouts: [LocalWorkout]

    init(deviceID: String, username: String, workouts: [LocalWorkout]) {
        self.version = Self.currentVersion
        self.exportedAt = Date()
        self.deviceID = deviceID
        self.username = username
        self.workouts = workouts
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A stable, sortable file name so several backups stay distinguishable.
    var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "healthpit-backup-\(formatter.string(from: exportedAt))"
    }
}

nonisolated enum HealthpitBackupError: LocalizedError {
    case unreadable
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return L10n.string("Die Datei ist keine gültige Healthpit-Sicherung.")
        case let .unsupportedVersion(version):
            return L10n.string("Sicherungsformat")
                + " \(version) "
                + L10n.string("wird von dieser App-Version nicht unterstützt.")
        }
    }
}

/// Wraps a backup so SwiftUI's fileExporter can write it to Files.
struct HealthpitBackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var backup: HealthpitBackup

    init(backup: HealthpitBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw HealthpitBackupError.unreadable
        }
        backup = try HealthpitBackup.decoder().decode(HealthpitBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try HealthpitBackup.encoder().encode(backup))
    }
}

enum HealthpitBackupService {
    /// Collect the full local workout history for export.
    static func makeBackup(deviceID: String, username: String) async -> HealthpitBackup {
        HealthpitBackup(
            deviceID: deviceID,
            username: username,
            workouts: await LocalWorkoutStore.shared.load()
        )
    }

    /// Read a backup file. The caller keeps the security-scoped access open.
    static func readBackup(at url: URL) throws -> HealthpitBackup {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw HealthpitBackupError.unreadable
        }
        let backup: HealthpitBackup
        do {
            backup = try HealthpitBackup.decoder().decode(HealthpitBackup.self, from: data)
        } catch {
            throw HealthpitBackupError.unreadable
        }
        guard backup.version <= HealthpitBackup.currentVersion else {
            throw HealthpitBackupError.unsupportedVersion(backup.version)
        }
        return backup
    }

    /// Merge a backup into the local store.
    ///
    /// Restoring never removes anything. A backup is a safety net, so a file
    /// that happens to be older than the device must not delete newer
    /// workouts. Entries with a known id are replaced, the rest are added.
    @discardableResult
    static func restore(_ backup: HealthpitBackup) async -> Int {
        guard !backup.workouts.isEmpty else { return 0 }
        await LocalWorkoutStore.shared.saveMany(backup.workouts)
        return backup.workouts.count
    }
}
