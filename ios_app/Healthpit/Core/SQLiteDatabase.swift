//
//  SQLiteDatabase.swift
//  HealthPitCore
//
//  Duenne Huelle um die SQLite-C-API. Bewusst kein ORM: das Schema ist
//  ueberschaubar, und handgeschriebenes SQL zeigt beim Lesen sofort, welche
//  Indexe und Constraints wirklich greifen.
//

import Foundation
import SQLite3

enum SQLValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    /// Rohbytes. Der bisherige Cache legt seine JSON-Nutzlast als BLOB ab –
    /// ohne diesen Fall waere sie fuer uns unsichtbar.
    case blob(Data)

    static func bool(_ value: Bool?) -> SQLValue {
        guard let value else { return .null }
        return .integer(value ? 1 : 0)
    }

    static func date(_ value: Date?) -> SQLValue {
        guard let value else { return .null }
        return .real(value.timeIntervalSince1970)
    }

    static func text(_ value: String?) -> SQLValue {
        guard let value else { return .null }
        return .text(value)
    }

    static func int(_ value: Int?) -> SQLValue {
        guard let value else { return .null }
        return .integer(Int64(value))
    }

    static func double(_ value: Double?) -> SQLValue {
        guard let value else { return .null }
        return .real(value)
    }
}

struct SQLiteError: Error, CustomStringConvertible {
    let code: Int32
    let message: String
    let statement: String?

    var description: String {
        "SQLite \(code): \(message)" + (statement.map { " – \($0)" } ?? "")
    }
}

/// Eine Ergebniszeile. Zugriff ueber den Spaltennamen, damit ein spaeter
/// eingefuegtes Feld nicht stillschweigend alle Indizes verschiebt.
struct SQLRow {
    private let values: [String: SQLValue]

    init(values: [String: SQLValue]) {
        self.values = values
    }

    func value(_ column: String) -> SQLValue {
        values[column] ?? .null
    }

    func string(_ column: String) -> String? {
        switch value(column) {
        case let .text(value): return value
        case let .blob(data): return String(data: data, encoding: .utf8)
        default: return nil
        }
    }

    /// Rohbytes einer Spalte, egal ob sie als BLOB oder als Text abgelegt ist.
    func data(_ column: String) -> Data? {
        switch value(column) {
        case let .blob(data): return data
        case let .text(text): return text.data(using: .utf8)
        default: return nil
        }
    }

    func requiredString(_ column: String) throws -> String {
        guard let value = string(column) else {
            throw SQLiteError(code: -1, message: "Spalte \(column) ist leer", statement: nil)
        }
        return value
    }

    func double(_ column: String) -> Double? {
        switch value(column) {
        case let .real(value): return value
        case let .integer(value): return Double(value)
        default: return nil
        }
    }

    func int(_ column: String) -> Int? {
        switch value(column) {
        case let .integer(value): return Int(value)
        case let .real(value): return Int(value)
        default: return nil
        }
    }

    func int64(_ column: String) -> Int64? {
        if case let .integer(value) = value(column) { return value }
        return nil
    }

    func bool(_ column: String) -> Bool? {
        guard let value = int(column) else { return nil }
        return value != 0
    }

    func date(_ column: String) -> Date? {
        guard let value = double(column) else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}

/// Nicht Sendable: Der Zugriff wird durch den umgebenden Actor serialisiert.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// Datei oder `":memory:"` fuer Tests.
    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw SQLiteError(code: result, message: message, statement: path)
        }
        self.handle = handle
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA busy_timeout = 5000;")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard let handle else { throw SQLiteError(code: -1, message: "Datenbank geschlossen", statement: sql) }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unbekannter Fehler"
            sqlite3_free(errorPointer)
            throw SQLiteError(code: result, message: message, statement: sql)
        }
    }

    @discardableResult
    func run(_ sql: String, _ bindings: [SQLValue] = []) throws -> Int64 {
        guard let handle else { throw SQLiteError(code: -1, message: "Datenbank geschlossen", statement: sql) }
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(handle)), statement: sql)
        }
        return sqlite3_last_insert_rowid(handle)
    }

    func query(_ sql: String, _ bindings: [SQLValue] = []) throws -> [SQLRow] {
        guard let handle else { throw SQLiteError(code: -1, message: "Datenbank geschlossen", statement: sql) }
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }

        var rows: [SQLRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw SQLiteError(code: step, message: String(cString: sqlite3_errmsg(handle)), statement: sql)
            }
            var values: [String: SQLValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    values[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    values[name] = .real(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    values[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(statement, index) {
                        let count = Int(sqlite3_column_bytes(statement, index))
                        values[name] = .blob(Data(bytes: bytes, count: count))
                    } else {
                        values[name] = .blob(Data())
                    }
                default:
                    values[name] = .null
                }
            }
            rows.append(SQLRow(values: values))
        }
        return rows
    }

    /// Alles-oder-nichts. Ein halb importierter Batch waere schlimmer als ein
    /// fehlgeschlagener.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String, _ bindings: [SQLValue]) throws -> OpaquePointer? {
        guard let handle else { throw SQLiteError(code: -1, message: "Datenbank geschlossen", statement: sql) }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(handle)), statement: sql)
        }
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let bindResult: Int32
            switch binding {
            case .null:
                bindResult = sqlite3_bind_null(statement, index)
            case let .integer(value):
                bindResult = sqlite3_bind_int64(statement, index, value)
            case let .real(value):
                bindResult = sqlite3_bind_double(statement, index, value)
            case let .text(value):
                bindResult = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            case let .blob(data):
                bindResult = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(data.count), sqliteTransient)
                }
            }
            guard bindResult == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw SQLiteError(code: bindResult, message: "Binden fehlgeschlagen", statement: sql)
            }
        }
        return statement
    }
}

/// SQLite soll den String kopieren – der Swift-Puffer lebt nur bis zum Ende
/// des Aufrufs.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// JSON-Kodierung fuer die `metadata`- und `raw_payload`-Spalten.
enum JSONColumn {
    static func encode(_ dictionary: [String: String]) -> String? {
        guard !dictionary.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ value: String?) -> [String: String] {
        guard let value, let data = value.data(using: .utf8) else { return [:] }
        let object = try? JSONSerialization.jsonObject(with: data)
        return (object as? [String: String]) ?? [:]
    }
}
