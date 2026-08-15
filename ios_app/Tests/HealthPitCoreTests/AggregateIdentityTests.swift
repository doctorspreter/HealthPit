//
//  AggregateIdentityTests.swift
//  HealthPitCoreTests
//
//  Tageswerte und Nachtwerte sind Zusammenfassungen eines Zeitraums, keine
//  Einzelmessungen. Kommt derselbe Zeitraum mit einer anderen Zahl noch
//  einmal herein – weil der Anbieter nachgerechnet hat oder weil ein zweiter
//  Cache einen aelteren Stand enthielt –, ist das ein neuer Stand desselben
//  Werts. Nicht ein zweiter Wert.
//
//  Genau hier entstanden die doppelten Schlaf- und Tageswerte.
//

import Foundation
import XCTest
@testable import HealthPitCore

final class AggregateIdentityTests: XCTestCase {

    private func nightlySleep(_ seconds: Double, recordID: String? = nil) -> IncomingObservation {
        IncomingObservation(sourceMetric: "sleep_session.asleep",
                            metricID: "SLP_DURATION",
                            value: seconds,
                            unit: .second,
                            startTime: T.at(-40_000),
                            endTime: T.at(-14_000),
                            aggregation: .sum,
                            periodType: .night,
                            originProvider: .appleHealth,
                            externalRecordID: recordID)
    }

    private func dailySteps(_ value: Double) -> IncomingObservation {
        IncomingObservation(sourceMetric: "HKQuantityTypeIdentifierStepCount",
                            metricID: "ACT_STEPS",
                            value: value,
                            unit: .count,
                            startTime: T.at(-86_400),
                            endTime: T.at(0),
                            aggregation: .sum,
                            periodType: .day,
                            originProvider: .appleHealth)
    }

    func testSameNightWithACorrectedValueStaysOneObservation() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        // Erst der Stand aus dem Wochen-Cache, dann der vollstaendigere aus
        // dem Monats-Cache. Dieselbe Nacht, andere Zahl.
        let first = try await pipeline.import(nightlySleep(21_600), from: .appleHealth)
        let second = try await pipeline.import(nightlySleep(24_300), from: .appleHealth)

        XCTAssertEqual(first.action, .create)
        XCTAssertEqual(second.action, .update)
        XCTAssertEqual(second.observationID, first.observationID)

        let stored = try await store.observations(metricID: "SLP_DURATION")
        XCTAssertEqual(stored.count, 1, "Eine Nacht ist eine Observation")
        XCTAssertEqual(stored.first?.valueNumeric, 24_300, "Der neuere Stand gewinnt")
        XCTAssertEqual(stored.first?.version, 2)
    }

    func testUnchangedAggregateIsNotCountedAsChange() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        _ = try await pipeline.import(nightlySleep(21_600), from: .appleHealth)
        let again = try await pipeline.import(nightlySleep(21_600), from: .appleHealth)

        XCTAssertEqual(again.action, .unchanged)
        let count = try await store.observations(metricID: "SLP_DURATION").count
        XCTAssertEqual(count, 1)
    }

    func testDailyTotalIsUpdatedWhileTheDayIsStillRunning() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        _ = try await pipeline.import(dailySteps(4_120), from: .appleHealth)
        _ = try await pipeline.import(dailySteps(6_580), from: .appleHealth)
        let evening = try await pipeline.import(dailySteps(8_431), from: .appleHealth)

        XCTAssertEqual(evening.action, .update)
        let stored = try await store.observations(metricID: "ACT_STEPS")
        XCTAssertEqual(stored.count, 1, "Ein Tag ist eine Observation, kein Verlauf aus Zwischenstaenden")
        XCTAssertEqual(stored.first?.valueNumeric, 8_431)
    }

    func testDifferentDaysStaySeparate() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        _ = try await pipeline.import(dailySteps(8_431), from: .appleHealth)
        var yesterday = dailySteps(7_200)
        yesterday.startTime = T.at(-172_800)
        yesterday.endTime = T.at(-86_400)
        _ = try await pipeline.import(yesterday, from: .appleHealth)

        let count = try await store.observations(metricID: "ACT_STEPS").count
        XCTAssertEqual(count, 2)
    }

    func testDifferentProvidersKeepTheirOwnDailyTotal() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        _ = try await pipeline.import(dailySteps(8_431), from: .appleHealth)
        var garmin = dailySteps(8_900)
        garmin.sourceMetric = "dailies.steps"
        garmin.originProvider = .garmin
        _ = try await pipeline.import(garmin, from: .garmin)

        // Zwei Anbieter zaehlen unterschiedlich. Das sind zwei Aussagen ueber
        // denselben Tag, keine Korrektur derselben Aussage.
        let count = try await store.observations(metricID: "ACT_STEPS").count
        XCTAssertEqual(count, 2)
    }

    func testRawMeasurementsAreStillNeverMergedByPeriod() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        // Zwei echte Pulsmessungen im selben Zeitfenster mit verschiedenen
        // Werten bleiben zwei Messungen – die Regel gilt nur fuer
        // Zusammenfassungen.
        let first = IncomingObservation(sourceMetric: "heartRate", value: 72, unit: .beatsPerMinute,
                                        startTime: T.at(0), endTime: T.at(0),
                                        externalRecordID: "GAR-1")
        let second = IncomingObservation(sourceMetric: "heartRate", value: 96, unit: .beatsPerMinute,
                                         startTime: T.at(0), endTime: T.at(0),
                                         externalRecordID: "GAR-2")
        _ = try await pipeline.import(first, from: .garmin)
        _ = try await pipeline.import(second, from: .garmin)

        let count = try await store.observations(metricID: "HRT_RATE").count
        XCTAssertEqual(count, 2)
    }

    func testWorkoutValuesOfDifferentWorkoutsStaySeparate() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let firstWorkout = WorkoutID.generate()
        let secondWorkout = WorkoutID.generate()
        func distance(_ workoutID: WorkoutID, _ value: Double) -> IncomingObservation {
            IncomingObservation(sourceMetric: "workout_summary.distance_km",
                                metricID: "WRK_DISTANCE",
                                value: value,
                                unit: .kilometer,
                                startTime: T.at(0),
                                endTime: T.at(3600),
                                aggregation: .sum,
                                periodType: .workout,
                                originProvider: .appleHealth,
                                workoutID: workoutID)
        }

        _ = try await pipeline.import(distance(firstWorkout, 8.2), from: .appleHealth)
        _ = try await pipeline.import(distance(secondWorkout, 5.1), from: .appleHealth)

        let count = try await store.observations(metricID: "WRK_DISTANCE").count
        XCTAssertEqual(count, 2, "Zwei Workouts sind zwei Werte, auch zur selben Zeit")
    }

    /// Der Fall aus dem Alltag: Dieselbe Nacht steht in mehreren
    /// Zeitraum-Caches, mit unterschiedlich vollstaendigen Zahlen.
    func testMigrationOfOverlappingSleepCachesCreatesOneNight() async throws {
        let store = try makeStore()
        try await store.executeRaw("""
        CREATE TABLE IF NOT EXISTS cache_entries (
            key TEXT PRIMARY KEY NOT NULL,
            payload BLOB NOT NULL,
            updated_at REAL NOT NULL
        );
        """)

        let formatter = ISO8601DateFormatter()
        func night(deepSeconds: Double) -> [[String: Any]] {
            [[
                "id": UUID().uuidString,
                "start": formatter.string(from: T.at(-40_000)),
                "end": formatter.string(from: T.at(-14_000)),
                "inBed": 26_000.0,
                "segments": [
                    ["id": UUID().uuidString, "stage": "deep",
                     "start": formatter.string(from: T.at(-40_000)),
                     "end": formatter.string(from: T.at(-40_000 + deepSeconds))],
                    ["id": UUID().uuidString, "stage": "core",
                     "start": formatter.string(from: T.at(-40_000 + deepSeconds)),
                     "end": formatter.string(from: T.at(-14_000))]
                ]
            ]]
        }

        for (key, deep) in [("sleep_sessions.week.2026-08-12", 3_000.0),
                            ("sleep_sessions.month.2026-08-01", 3_600.0)] {
            let data = try JSONSerialization.data(withJSONObject: night(deepSeconds: deep))
            let json = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "'", with: "''")
            try await store.executeRaw("""
            INSERT OR REPLACE INTO cache_entries (key, payload, updated_at)
            VALUES ('\(key)', '\(json)', \(Date().timeIntervalSince1970));
            """)
        }

        _ = try await LegacyMigration(store: store, localWorkoutsURL: nil).run()

        let asleep = try await store.observations(metricID: "SLP_DURATION")
        let inBed = try await store.observations(metricID: "SLP_TIME_IN_BED")
        let deep = try await store.observations(metricID: "SLP_DEEP_DURATION")
        XCTAssertEqual(asleep.count, 1, "Eine Nacht, nicht zwei")
        XCTAssertEqual(inBed.count, 1)
        XCTAssertEqual(deep.count, 1)

        // Und auch die Phasen liegen nur einmal da – nicht zwei Reihen
        // uebereinander, eine je Cache-Stand.
        let stages = try await store.observations(metricID: "SLP_STAGE")
        XCTAssertEqual(stages.count, 2, "Zwei Phasen der einen Nacht")
        XCTAssertEqual(Set(stages.compactMap(\.valueCode)), ["DEEP", "CORE"])
    }
}

// MARK: - Reparatur bereits entstandener Duplikate

final class DuplicateRepairTests: XCTestCase {

    private func nightly(_ seconds: Double, updatedAt: Date) -> HealthObservation {
        HealthObservation(metricID: "SLP_DURATION",
                          valueNumeric: seconds,
                          unit: .second,
                          startTime: T.at(-40_000),
                          endTime: T.at(-14_000),
                          aggregation: .sum,
                          periodType: .night,
                          originProvider: .appleHealth,
                          ingestProvider: .appleHealth,
                          updatedAt: updatedAt)
    }

    func testRepairKeepsTheNewestStandAndRetiresTheRest() async throws {
        let store = try makeStore()
        // So sah die Datenbank nach dem ersten Lauf aus: dieselbe Nacht,
        // drei Zwischenstaende.
        let old = nightly(21_600, updatedAt: T.at(-3600))
        let middle = nightly(23_400, updatedAt: T.at(-1800))
        let newest = nightly(24_300, updatedAt: T.at(0))
        for observation in [old, middle, newest] {
            try await store.insert(observation)
        }
        try await store.upsert(ExternalReference(entityID: old.observationID.rawValue,
                                                 provider: .appleHealth,
                                                 externalRecordID: "APP-OLD"))

        let report = try await DuplicateRepair(store: store).run()

        XCTAssertEqual(report.groups, 1)
        XCTAssertEqual(report.mergedObservations, 2)
        XCTAssertEqual(report.movedReferences, 1)

        let live = try await store.observations(metricID: "SLP_DURATION")
        XCTAssertEqual(live.count, 1)
        XCTAssertEqual(live.first?.observationID, newest.observationID)
        XCTAssertEqual(live.first?.valueNumeric, 24_300)

        // Nichts ist verschwunden – die anderen Zeilen sind nur weich geloescht.
        let all = try await store.observationCount(includeDeleted: true)
        XCTAssertEqual(all, 3)
        let retired = try await unwrap(store.observation(old.observationID))
        XCTAssertNotNil(retired.deletedAt)
        XCTAssertEqual(retired.metadata["merged_into"], newest.observationID.rawValue)

        // Die externe Referenz zeigt jetzt auf den verbleibenden Wert.
        let reference = try await unwrap(store.reference(provider: .appleHealth,
                                                         externalRecordID: "APP-OLD"))
        XCTAssertEqual(reference.entityID, newest.observationID.rawValue)
    }

    func testRepairLeavesCleanDataAlone() async throws {
        let store = try makeStore()
        try await store.insert(nightly(24_300, updatedAt: T.at(0)))
        var otherNight = nightly(25_000, updatedAt: T.at(0))
        otherNight.startTime = T.at(-126_400)
        otherNight.endTime = T.at(-100_400)
        try await store.insert(otherNight)

        let report = try await DuplicateRepair(store: store).run()

        XCTAssertEqual(report.groups, 0)
        XCTAssertFalse(report.didChangeAnything)
        let count = try await store.observations(metricID: "SLP_DURATION").count
        XCTAssertEqual(count, 2)
    }

    func testRepairRunsOnlyOnce() async throws {
        let store = try makeStore()
        try await store.insert(nightly(21_600, updatedAt: T.at(-3600)))
        try await store.insert(nightly(24_300, updatedAt: T.at(0)))

        let first = try await DuplicateRepair(store: store).runIfNeeded()
        let second = try await DuplicateRepair(store: store).runIfNeeded()

        XCTAssertEqual(first.mergedObservations, 1)
        XCTAssertEqual(second.mergedObservations, 0)
    }

    func testRepairDoesNotTouchSingleMeasurements() async throws {
        let store = try makeStore()
        // Zwei echte Pulsmessungen zur selben Sekunde, verschiedene Geraete.
        for device in ["fenix-7", "hrm-pro"] {
            try await store.insert(HealthObservation(metricID: "HRT_RATE",
                                                     valueNumeric: 72,
                                                     unit: .beatsPerMinute,
                                                     startTime: T.at(0),
                                                     endTime: T.at(0),
                                                     originProvider: .garmin,
                                                     ingestProvider: .garmin,
                                                     sourceDeviceID: device))
        }

        let report = try await DuplicateRepair(store: store).run()

        XCTAssertEqual(report.mergedObservations, 0)
        let count = try await store.observations(metricID: "HRT_RATE").count
        XCTAssertEqual(count, 2)
    }
}
