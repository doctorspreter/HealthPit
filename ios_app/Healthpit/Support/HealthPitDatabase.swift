//
//  HealthPitDatabase.swift
//  Healthpit
//
//  Lokaler SQLite-Cache fuer teure HealthKit-/Bridge-Abfragen.
//

import Foundation
import SQLite3

actor HealthPitDatabase {
    static let shared = HealthPitDatabase()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var database: OpaquePointer?

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appending(path: "Database", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "healthpit.sqlite3")
        let legacyURL = folder.appending(path: "health" + "app.sqlite3")
        if !FileManager.default.fileExists(atPath: url.path),
           FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.moveItem(at: legacyURL, to: url)
        }

        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            database = nil
            return
        }
        sqlite3_exec(database, """
        CREATE TABLE IF NOT EXISTS cache_entries (
            key TEXT PRIMARY KEY NOT NULL,
            payload BLOB NOT NULL,
            updated_at REAL NOT NULL
        );
        """, nil, nil, nil)
    }

    deinit {
        sqlite3_close(database)
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM cache_entries WHERE key = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, sqliteTransientDestructor())
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else {
            return nil
        }

        let count = Int(sqlite3_column_bytes(statement, 0))
        let data = Data(bytes: bytes, count: count)
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let database,
              let data = try? encoder.encode(value) else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO cache_entries (key, payload, updated_at) VALUES (?, ?, ?);", -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, sqliteTransientDestructor())
        _ = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(data.count), sqliteTransientDestructor())
        }
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func remove(key: String) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM cache_entries WHERE key = ?;", -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransientDestructor())
        sqlite3_step(statement)
    }

    func removeAll() {
        guard let database else { return }
        sqlite3_exec(database, "DELETE FROM cache_entries;", nil, nil, nil)
    }
}

nonisolated private func sqliteTransientDestructor() -> sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
