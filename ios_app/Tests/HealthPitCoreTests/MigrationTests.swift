//
//  MigrationTests.swift
//  HealthPitCoreTests
//
//  Punkt 11 der geforderten Faelle: Der Altbestand muss vollstaendig
//  ankommen – auch das, was sich nicht sauber zuordnen laesst.
//

import Foundation
import XCTest
@testable import HealthPitCore

final class MigrationTests: XCTestCase {

    private func makeLegacyWorkoutsFile(_ workouts: [[String: Any]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "legacy-workouts-\(UUID().uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: workouts, options: [.sortedKeys])
        try data.write(to: url)
        return url
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Legt den alten Key-Value-Cache in derselben Datei an, so wie ihn
    /// `HealthPitDatabase` heute schreibt.
    private func seedLegacyCache(_ store: HealthPitStore, entries: [String: Any]) async throws {
        try await store.executeRaw("""
        CREATE TABLE IF NOT EXISTS cache_entries (
            key TEXT PRIMARY KEY NOT NULL,
            payload BLOB NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
        for (key, value) in entries {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            let json = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "'", with: "''")
            try await store.executeRaw("""
            INSERT OR REPLACE INTO cache_entries (key, payload, updated_at)
            VALUES ('\(key)', '\(json)', \(Date().timeIntervalSince1970));
            """)
        }
    }

    func test11_legacyDataMigratesWithoutLoss() async throws {
        let store = try makeStore()
        let manualID = UUID()
        let appleWorkoutID = UUID()
        let start = T.at(-7200)
        let end = T.at(-3600)

        let workoutsURL = try makeLegacyWorkoutsFile([
            [
                "id": manualID.uuidString,
                "source": "manual",
                "sport": "Krafttraining",
                "title": "Push Day",
                "start": iso(start),
                "end": iso(end),
                "energyKcal": 420.0,
                "averageHeartRate": 118.0,
                "maxHeartRate": 155.0,
                "notes": "Bank neue Bestleistung",
                "exercises": [[
                    "id": "ex-1",
                    "name": "Bankdruecken",
                    "category": "chest",
                    "sets": [["id": "s-1", "index": 1, "type": "work", "reps": 8.0, "weight_kg": 80.0]]
                ]],
                "route": []
            ],
            [
                "id": appleWorkoutID.uuidString,
                "source": "apple_health",
                "sport": "Laufen",
                "title": "Morgenlauf",
                "start": iso(T.at(-86_400)),
                "end": iso(T.at(-83_000)),
                "distanceKm": 8.2,
                "energyKcal": 610.0,
                "notes": "",
                "route": []
            ]
        ])

        try await seedLegacyCache(store, entries: [
            "dashboard.metric.values": [
                ["metricID": "HKQuantityTypeIdentifierStepCount",
                 "value": 8431.0,
                 "updatedAt": iso(T.at(0))],
                ["metricID": "HKQuantityTypeIdentifierBodyMass",
                 "value": 82.4,
                 "updatedAt": iso(T.at(0)),
                 "measuredAt": iso(T.at(-600))],
                ["metricID": "HKQuantityTypeIdentifierOxygenSaturation",
                 "value": 0.97,
                 "updatedAt": iso(T.at(0)),
                 "measuredAt": iso(T.at(-900))],
                // Ein Schluessel, den die Mapping-Tabelle nicht kennt.
                ["metricID": "HKQuantityTypeIdentifierSomethingFromTheFuture",
                 "value": 42.0,
                 "updatedAt": iso(T.at(0))]
            ],
            "sleep_sessions.week.2026-08-12": [[
                "id": UUID().uuidString,
                "start": iso(T.at(-40_000)),
                "end": iso(T.at(-14_000)),
                "inBed": 26_000.0,
                "segments": [
                    ["id": UUID().uuidString, "stage": "deep",
                     "start": iso(T.at(-40_000)), "end": iso(T.at(-37_000))],
                    ["id": UUID().uuidString, "stage": "core",
                     "start": iso(T.at(-37_000)), "end": iso(T.at(-20_000))],
                    ["id": UUID().uuidString, "stage": "rem",
                     "start": iso(T.at(-20_000)), "end": iso(T.at(-15_000))],
                    ["id": UUID().uuidString, "stage": "awake",
                     "start": iso(T.at(-15_000)), "end": iso(T.at(-14_000))]
                ]
            ]],
            "workout.records.snapshot": [["id": "record-1", "value": "irrelevant"]]
        ])

        let migration = LegacyMigration(store: store, localWorkoutsURL: workoutsURL)
        let report = try await migration.run()

        // Beide Workouts sind da – und behalten ihre bisherige UUID.
        let actual1 = try await store.workoutCount()
        XCTAssertEqual(actual1, 2)
        let manualWorkout = try unwrap(await store.workout(WorkoutID(uuid: manualID)))
        XCTAssertEqual(manualWorkout.sportType, "KRAFTTRAINING")
        XCTAssertEqual(manualWorkout.originProvider, .healthPit)
        XCTAssertNotNil(manualWorkout.rawPayload, "Originaldatensatz muss erhalten bleiben")

        let appleWorkout = try unwrap(await store.workout(WorkoutID(uuid: appleWorkoutID)))
        XCTAssertEqual(appleWorkout.originProvider, .appleHealth)
        let appleReference = try await store.reference(entityType: .workout,
                                                       entityID: appleWorkout.workoutID.rawValue,
                                                       provider: .appleHealth)
        XCTAssertEqual(appleReference?.externalRecordID, appleWorkoutID.uuidString)

        // Werte des Krafttrainings inklusive der Saetze, die Apple Health
        // gar nicht abbilden koennte.
        let manualValues = try await store.observations(workoutID: manualWorkout.workoutID)
        let manualMetrics = Set(manualValues.map(\.metricID))
        XCTAssertTrue(manualMetrics.contains("WRK_ENERGY"))
        XCTAssertTrue(manualMetrics.contains("HRT_RATE"))
        XCTAssertTrue(manualMetrics.contains("HRT_MAX_RATE"))
        XCTAssertTrue(manualMetrics.contains("WRK_STRENGTH_SET"))

        // Distanz wurde von km auf Meter normalisiert, der Originalwert bleibt.
        let distance = try unwrap(await store.observations(metricID: "WRK_DISTANCE").first)
        XCTAssertEqual(distance.valueNumeric ?? 0, 8200, accuracy: 0.5)
        XCTAssertEqual(distance.sourceValue, 8.2)
        XCTAssertEqual(distance.sourceUnit, .kilometer)

        // Dashboardwerte: Schritte, Gewicht, SpO2 – letzteres mit der
        // Skalenkorrektur von 0,97 auf 97 %.
        let steps = try unwrap(await store.observations(metricID: "ACT_STEPS").first)
        XCTAssertEqual(steps.valueNumeric, 8431)
        XCTAssertEqual(steps.aggregation, .sum)
        XCTAssertEqual(steps.periodType, .day)
        let spo2 = try unwrap(await store.observations(metricID: "RSP_SPO2").first)
        XCTAssertEqual(spo2.valueNumeric ?? 0, 97, accuracy: 0.001)
        XCTAssertEqual(spo2.unit, .percent)

        // Der unbekannte Schluessel ist nicht verloren, sondern markiert.
        let unresolved = try await store.observations(reviewState: .unresolvedMetric)
        XCTAssertEqual(unresolved.count, 1)
        XCTAssertEqual(unresolved.first?.valueNumeric, 42)
        XCTAssertEqual(unresolved.first?.sourceMetric,
                       "HKQuantityTypeIdentifierSomethingFromTheFuture")
        XCTAssertEqual(report.unresolvedObservations, 1)

        // Schlaf: Phasen und Nachtsummen.
        let actual2 = try await store.observations(metricID: "SLP_STAGE").count
        XCTAssertEqual(actual2, 4)
        let deep = try unwrap(await store.observations(metricID: "SLP_DEEP_DURATION").first)
        XCTAssertEqual(deep.valueNumeric, 3000)
        let efficiency = try unwrap(await store.observations(metricID: "SLP_EFFICIENCY").first)
        XCTAssertEqual(efficiency.unit, .percent)

        // Abgeleitetes bleibt liegen, statt halbgar mitzuwandern.
        XCTAssertTrue(report.untouchedCacheKeys.contains("workout.records.snapshot"))
    }

    func test11b_migrationIsIdempotent() async throws {
        let store = try makeStore()
        let workoutID = UUID()
        let workoutsURL = try makeLegacyWorkoutsFile([[
            "id": workoutID.uuidString,
            "source": "gympit",
            "sport": "Krafttraining",
            "title": "Pull Day",
            "start": iso(T.at(-7200)),
            "end": iso(T.at(-3600)),
            "energyKcal": 380.0,
            "notes": "",
            "route": []
        ]])
        try await seedLegacyCache(store, entries: [
            "dashboard.metric.values": [["metricID": "HKQuantityTypeIdentifierStepCount",
                                         "value": 8431.0,
                                         "updatedAt": iso(T.at(0))]]
        ])

        let migration = LegacyMigration(store: store, localWorkoutsURL: workoutsURL)
        let first = try await migration.run()
        let second = try await migration.run()
        let forced = try await migration.run(force: true)

        XCTAssertEqual(first.workouts, 1)
        XCTAssertTrue(second.alreadyMigrated)
        // Auch ein erzwungener zweiter Lauf legt nichts doppelt an.
        XCTAssertEqual(forced.workouts, 0)
        XCTAssertEqual(forced.metricObservations, 0)
        let actual3 = try await store.workoutCount()
        XCTAssertEqual(actual3, 1)
        let actual4 = try await store.observations(metricID: "ACT_STEPS").count
        XCTAssertEqual(actual4, 1)
    }

    func test11c_migratedAppleWorkoutIsNotImportedTwice() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let hkUUID = UUID()
        let workoutsURL = try makeLegacyWorkoutsFile([[
            "id": hkUUID.uuidString,
            "source": "apple_health",
            "sport": "Laufen",
            "title": "Morgenlauf",
            "start": iso(T.at(-7200)),
            "end": iso(T.at(-3600)),
            "distanceKm": 8.2,
            "notes": "",
            "route": []
        ]])
        _ = try await LegacyMigration(store: store, localWorkoutsURL: workoutsURL).run()

        // Derselbe Lauf kommt beim naechsten Apple-Sync wieder herein.
        let pipeline = ImportPipeline(store: store)
        let result = try await pipeline.import(IncomingWorkout(sportType: "RUNNING",
                                                               title: "Morgenlauf",
                                                               startTime: T.at(-7200),
                                                               endTime: T.at(-3600),
                                                               externalRecordID: hkUUID.uuidString),
                                               from: .appleHealth)

        XCTAssertNotEqual(result.action, .create)
        let actual5 = try await store.workoutCount()
        XCTAssertEqual(actual5, 1)
    }
}

// MARK: - Der Cache liegt als BLOB in der Datenbank

final class LegacyBlobCacheTests: XCTestCase {

    /// `HealthPitDatabase.save` bindet seine JSON-Nutzlast als BLOB. Genau so
    /// muss die Uebernahme sie auch wieder lesen – sonst waeren im Alltag
    /// saemtliche Messwerte und Schlafnaechte unsichtbar, obwohl sie da sind.
    func testMigrationReadsPayloadsStoredAsBlob() async throws {
        let store = try makeStore()
        try await store.executeRaw("""
        CREATE TABLE IF NOT EXISTS cache_entries (
            key TEXT PRIMARY KEY NOT NULL,
            payload BLOB NOT NULL,
            updated_at REAL NOT NULL
        );
        """)

        let formatter = ISO8601DateFormatter()
        let entries: [[String: Any]] = [
            ["metricID": "HKQuantityTypeIdentifierStepCount",
             "value": 8431.0,
             "updatedAt": formatter.string(from: T.at(0))]
        ]
        let json = try JSONSerialization.data(withJSONObject: entries)
        // Als echtes BLOB einfuegen, nicht als Text.
        let hex = json.map { String(format: "%02x", $0) }.joined()
        try await store.executeRaw("""
        INSERT INTO cache_entries (key, payload, updated_at)
        VALUES ('dashboard.metric.values', X'\(hex)', \(Date().timeIntervalSince1970));
        """)

        let inventory = try await LegacyMigration(store: store, localWorkoutsURL: nil).inspect()
        XCTAssertEqual(inventory.dashboardValues, 1, "Der Dialog muss den Wert finden")

        let report = try await LegacyMigration(store: store, localWorkoutsURL: nil).run()
        XCTAssertEqual(report.metricObservations, 1)

        let steps = try await store.observations(metricID: "ACT_STEPS")
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?.valueNumeric, 8431)
    }
}
