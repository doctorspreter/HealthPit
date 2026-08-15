//
//  CatalogTests.swift
//  HealthPitCoreTests
//
//  Entitaetenkatalog und Quellenfreigaben: „Schritte von Garmin und Huawei
//  annehmen, aus Apple Health nicht.“
//

import Foundation
import XCTest
@testable import HealthPitCore

final class CatalogTests: XCTestCase {

    private func steps(from provider: ProviderCode,
                       sourceMetric: String,
                       recordID: String,
                       appID: String? = nil,
                       value: Double = 1000,
                       offset: TimeInterval = 0) -> IncomingObservation {
        IncomingObservation(sourceMetric: sourceMetric,
                            value: value,
                            unit: .count,
                            startTime: T.at(offset),
                            endTime: T.at(offset + 86_400),
                            aggregation: .sum,
                            periodType: .day,
                            originProvider: provider,
                            externalRecordID: recordID,
                            sourceAppID: appID)
    }

    func testDisabledSourceIsNotImported() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        // Apple Health zaehlt das iPhone in der Hosentasche mit – abschalten.
        try await store.setSourcePolicy(metricID: "ACT_STEPS", provider: .appleHealth, enabled: false)

        let fromApple = try await pipeline.import(
            steps(from: .appleHealth, sourceMetric: "HKQuantityTypeIdentifierStepCount", recordID: "APP-1"),
            from: .appleHealth)
        let fromGarmin = try await pipeline.import(
            steps(from: .garmin, sourceMetric: "dailies.steps", recordID: "GAR-1", value: 8431),
            from: .garmin)
        let fromHuawei = try await pipeline.import(
            steps(from: .huawei, sourceMetric: "com.huawei.continuous.steps.delta",
                  recordID: "HUA-1", value: 8500, offset: 90_000),
            from: .huawei)

        XCTAssertEqual(fromApple.action, .skip)
        XCTAssertEqual(fromGarmin.action, .create)
        XCTAssertEqual(fromHuawei.action, .create)
        let stepCount = try await observationCount(store, "ACT_STEPS")
        XCTAssertEqual(stepCount, 2)

        // Die Ablehnung steht im Protokoll, nicht nur im Nichts.
        let events = try await store.syncEvents(provider: .appleHealth)
        XCTAssertEqual(events.first?.action, .skip)
        XCTAssertEqual(events.first?.metadata["reason"], "source_disabled")
    }

    func testPolicyOnlyAffectsTheChosenMetric() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)
        try await store.setSourcePolicy(metricID: "ACT_STEPS", provider: .appleHealth, enabled: false)

        let heart = try await pipeline.import(
            IncomingObservation(sourceMetric: "HKQuantityTypeIdentifierHeartRate",
                                value: 72,
                                unit: .beatsPerMinute,
                                startTime: T.at(0),
                                endTime: T.at(0),
                                externalRecordID: "APP-HR-1"),
            from: .appleHealth)

        XCTAssertEqual(heart.action, .create, "Nur Schritte waren abgeschaltet")
    }

    func testAppSpecificPolicyBeatsProviderWide() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        // Alles aus Apple Health aus …
        try await store.setSourcePolicy(metricID: "ACT_STEPS", provider: .appleHealth, enabled: false)
        // … aber was Garmin Connect dort ablegt, darf rein.
        try await store.setSourcePolicy(metricID: "ACT_STEPS",
                                        provider: .appleHealth,
                                        sourceAppID: "com.garmin.connect.mobile",
                                        enabled: true)

        let iPhone = try await pipeline.import(
            steps(from: .appleHealth, sourceMetric: "HKQuantityTypeIdentifierStepCount",
                  recordID: "APP-1", appID: "com.apple.Health"),
            from: .appleHealth)
        let connect = try await pipeline.import(
            steps(from: .appleHealth, sourceMetric: "HKQuantityTypeIdentifierStepCount",
                  recordID: "APP-2", appID: "com.garmin.connect.mobile",
                  value: 8431, offset: 90_000),
            from: .appleHealth)

        XCTAssertEqual(iPhone.action, .skip)
        XCTAssertEqual(connect.action, .create)
    }

    func testEnablingAgainRemovesTheRule() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        try await store.setSourcePolicy(metricID: "ACT_STEPS", provider: .appleHealth, enabled: false)
        let blocked = try await pipeline.import(
            steps(from: .appleHealth, sourceMetric: "HKQuantityTypeIdentifierStepCount", recordID: "APP-1"),
            from: .appleHealth)
        XCTAssertEqual(blocked.action, .skip)

        try await store.clearSourcePolicy(metricID: "ACT_STEPS", provider: .appleHealth)
        let allowed = try await pipeline.import(
            steps(from: .appleHealth, sourceMetric: "HKQuantityTypeIdentifierStepCount", recordID: "APP-1"),
            from: .appleHealth)
        XCTAssertEqual(allowed.action, .create)

        let policies = try await store.sourcePolicies()
        XCTAssertTrue(policies.isEmpty, "Erlauben heisst: keine Regel")
    }

    func testCatalogShowsWhichSourceDeliversWhat() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        _ = try await pipeline.import(
            steps(from: .garmin, sourceMetric: "dailies.steps", recordID: "GAR-1", value: 8431),
            from: .garmin)
        _ = try await pipeline.import(
            steps(from: .garmin, sourceMetric: "dailies.steps", recordID: "GAR-2",
                  value: 9000, offset: 90_000),
            from: .garmin)
        // Derselbe Wert, aber ueber Apple Health hereingekommen.
        _ = try await pipeline.import(
            IncomingObservation(sourceMetric: "HKQuantityTypeIdentifierHeartRate",
                                value: 72,
                                unit: .beatsPerMinute,
                                startTime: T.at(0),
                                endTime: T.at(0),
                                originProvider: .huawei,
                                externalRecordID: "APP-HR-1",
                                sourceAppID: "com.huawei.health"),
            from: .appleHealth)

        let catalog = try await store.catalog()
        XCTAssertEqual(catalog.count, 2)

        let stepsEntry = try unwrap(catalog.first { $0.metricID == "ACT_STEPS" })
        XCTAssertEqual(stepsEntry.originProvider, .garmin)
        XCTAssertEqual(stepsEntry.ingestProvider, .garmin)
        XCTAssertEqual(stepsEntry.observationCount, 2)
        XCTAssertEqual(stepsEntry.unit, .count)

        // Herkunft und Lieferweg bleiben im Katalog unterscheidbar.
        let heartEntry = try unwrap(catalog.first { $0.metricID == "HRT_RATE" })
        XCTAssertEqual(heartEntry.originProvider, .huawei)
        XCTAssertEqual(heartEntry.ingestProvider, .appleHealth)
        XCTAssertEqual(heartEntry.sourceAppID, "com.huawei.health")
    }

    func testInventoryFindsLegacyDataWithoutChangingAnything() async throws {
        let store = try makeStore()
        let workoutsURL = FileManager.default.temporaryDirectory
            .appending(path: "legacy-inspect-\(UUID().uuidString).json")
        let formatter = ISO8601DateFormatter()
        let payload: [[String: Any]] = [[
            "id": UUID().uuidString,
            "source": "manual",
            "sport": "Laufen",
            "title": "Abendlauf",
            "start": formatter.string(from: T.at(-7200)),
            "end": formatter.string(from: T.at(-3600)),
            "notes": "",
            "route": []
        ]]
        try JSONSerialization.data(withJSONObject: payload).write(to: workoutsURL)

        let migration = LegacyMigration(store: store, localWorkoutsURL: workoutsURL)
        let inventory = try await migration.inspect()

        XCTAssertEqual(inventory.localWorkouts, 1)
        XCTAssertTrue(inventory.hasAnything)
        XCTAssertFalse(inventory.alreadyMigrated)
        // Nachsehen darf nichts anlegen.
        let workoutCount = try await store.workoutCount()
        XCTAssertEqual(workoutCount, 0)
        let observationCount = try await store.observationCount()
        XCTAssertEqual(observationCount, 0)

        _ = try await migration.run()
        let afterRun = try await migration.inspect()
        XCTAssertTrue(afterRun.alreadyMigrated, "Nach der Uebernahme fragt der Dialog nicht erneut")
    }
}
