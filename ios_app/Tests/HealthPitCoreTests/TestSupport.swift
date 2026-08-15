//
//  TestSupport.swift
//  HealthPitCoreTests
//
//  Gemeinsames Geruest: ein frischer Store je Test und ein Adapter, der
//  mitschreibt, was ein Anbieter zu sehen bekommen haette.
//

import Foundation
import XCTest
@testable import HealthPitCore

/// Feste Uhrzeiten, damit Vergleiche nachvollziehbar bleiben.
enum T {
    static let base = Date(timeIntervalSince1970: 1_786_000_000) // 2026-08-12, ca. 13:26 UTC

    static func at(_ offsetSeconds: TimeInterval) -> Date {
        base.addingTimeInterval(offsetSeconds)
    }
}

func makeStore(file: StaticString = #filePath, line: UInt = #line) throws -> HealthPitStore {
    // Eigene Datei je Test: `:memory:` reicht nicht, weil einige Tests den
    // alten `cache_entries`-Cache mit anlegen und lesen wollen.
    let url = FileManager.default.temporaryDirectory
        .appending(path: "healthpit-test-\(UUID().uuidString).sqlite3")
    return try HealthPitStore(path: url.path)
}

/// Legt die Mappings an, die die Tests brauchen.
func seedMappings(_ store: HealthPitStore) async throws {
    for mapping in AppleHealthMapping.providerMappings() {
        try await store.upsertMapping(mapping)
    }
    for mapping in GarminMapping.mappings {
        try await store.upsertMapping(mapping)
    }
    for mapping in HuaweiMapping.mappings {
        try await store.upsertMapping(mapping)
    }
}

/// Ein Anbieter, der jeden Schreibvorgang protokolliert – damit laesst sich
/// pruefen, ob ein Exportjob wirklich nur einmal angelegt hat.
///
/// Die Tests laufen seriell, deshalb reicht `@unchecked Sendable` ohne Sperre.
final class RecordingAdapter: ProviderAdapter, @unchecked Sendable {
    struct Write: Equatable {
        let action: SyncAction
        let targetMetric: String
        let value: Double?
        let unit: UnitCode?
        let syncIdentifier: String
        let externalRecordID: String?
    }

    let provider: ProviderCode
    let mappings: [ProviderMetricMapping]
    private(set) var writes: [Write] = []
    private(set) var deletes: [String] = []
    /// Was der Anbieter beim naechsten Lesen zurueckliefern wuerde.
    private(set) var storedRecords: [String: ExportPayload] = [:]
    private var counter = 0

    init(provider: ProviderCode, mappings: [ProviderMetricMapping] = []) {
        self.provider = provider
        self.mappings = mappings
    }

    func write(_ payload: ExportPayload, action: SyncAction) async throws -> ExportOutcome {
        let recordID: String
        if let existing = payload.externalRecordID {
            recordID = existing
        } else {
            counter += 1
            recordID = "\(provider.rawValue)-REC-\(counter)"
        }
        writes.append(Write(action: action,
                            targetMetric: payload.targetMetric,
                            value: payload.value,
                            unit: payload.unit,
                            syncIdentifier: payload.syncIdentifier,
                            externalRecordID: payload.externalRecordID))
        storedRecords[recordID] = payload
        return ExportOutcome(externalRecordID: recordID, syncVersion: payload.syncVersion)
    }

    func delete(externalRecordID: String, syncIdentifier: String?) async throws {
        deletes.append(externalRecordID)
        storedRecords[externalRecordID] = nil
    }

    /// Simuliert, was beim naechsten Import von diesem Anbieter zurueckkommt:
    /// derselbe Datensatz, inklusive unseres Sync-Identifiers.
    func echoBack(externalRecordID: String) -> IncomingObservation? {
        guard let payload = storedRecords[externalRecordID] else { return nil }
        let observation = payload.observation
        return IncomingObservation(sourceMetric: payload.targetMetric,
                                   value: payload.value,
                                   valueCode: payload.valueCode,
                                   unit: payload.unit,
                                   startTime: observation.startTime,
                                   endTime: observation.endTime,
                                   aggregation: observation.aggregation,
                                   periodType: observation.periodType,
                                   externalRecordID: externalRecordID,
                                   syncIdentifier: payload.syncIdentifier,
                                   syncVersion: payload.syncVersion,
                                   sourceAppID: "de.healthpit.app")
    }
}

/// `XCTUnwrap` nimmt seinen Wert als Autoclosure – darin ist `await` nicht
/// erlaubt. Diese Variante nimmt ihn normal entgegen.
func unwrap<T>(_ value: T?,
               _ message: String = "Wert war nil",
               file: StaticString = #filePath,
               line: UInt = #line) throws -> T {
    try XCTUnwrap(value, message, file: file, line: line)
}

extension XCTestCase {
    /// Anzahl lebender Observations einer Metrik.
    func observationCount(_ store: HealthPitStore, _ metric: MetricID) async throws -> Int {
        try await store.observations(metricID: metric).count
    }
}
