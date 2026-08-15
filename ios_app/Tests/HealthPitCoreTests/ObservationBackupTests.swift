//
//  ObservationBackupTests.swift
//  HealthPitCoreTests
//
//  Eine Sicherung, die den halben Bestand vergisst, ist keine.
//

import Foundation
import XCTest
@testable import HealthPitCore

final class ObservationBackupTests: XCTestCase {

    private func fill(_ store: HealthPitStore) async throws -> (ObservationID, WorkoutID) {
        let workout = StoredWorkout(sportType: "RUNNING",
                                    title: "Morgenlauf",
                                    startTime: T.at(-7200),
                                    endTime: T.at(-3600),
                                    originProvider: .appleHealth,
                                    ingestProvider: .appleHealth,
                                    sourceRecordID: "APP-1")
        try await store.insert(workout)

        let sleep = HealthObservation(metricID: "SLP_DURATION",
                                      valueNumeric: 25_200,
                                      unit: .second,
                                      startTime: T.at(-40_000),
                                      endTime: T.at(-14_000),
                                      aggregation: .sum,
                                      periodType: .night,
                                      originProvider: .appleHealth,
                                      ingestProvider: .appleHealth)
        try await store.insert(sleep)
        try await store.upsert(ExternalReference(entityID: sleep.observationID.rawValue,
                                                 provider: .appleHealth,
                                                 externalRecordID: "APP-SLEEP-1"))
        try await store.setSourcePolicy(metricID: "ACT_STEPS", provider: .appleHealth, enabled: false)
        return (sleep.observationID, workout.workoutID)
    }

    func testBackupCarriesEverythingNotJustWorkouts() async throws {
        let store = try makeStore()
        let (sleepID, workoutID) = try await fill(store)

        let backup = try await ObservationBackupService.makeBackup(store: store)

        XCTAssertEqual(backup.observations.count, 1)
        XCTAssertEqual(backup.observations.first?.observationID, sleepID)
        XCTAssertEqual(backup.workouts.first?.workoutID, workoutID)
        XCTAssertEqual(backup.references.count, 1)
        XCTAssertEqual(backup.sourcePolicies.count, 1, "Abgeschaltete Quellen gehören dazu")
        XCTAssertFalse(backup.isEmpty)
    }

    func testEachOriginGetsItsOwnSection() async throws {
        let store = try makeStore()
        _ = try await fill(store)

        // Dazu etwas, das in HealthPit selbst entstanden ist, und ein Wert,
        // der von Garmin stammt, aber über Apple Health hereinkam.
        try await store.insert(HealthObservation(metricID: "BDY_WEIGHT",
                                                 valueNumeric: 82.4,
                                                 unit: .kilogram,
                                                 startTime: T.at(0),
                                                 endTime: T.at(0),
                                                 originProvider: .healthPit,
                                                 ingestProvider: .healthPit))
        try await store.insert(HealthObservation(metricID: "HRT_RATE",
                                                 valueNumeric: 72,
                                                 unit: .beatsPerMinute,
                                                 startTime: T.at(60),
                                                 endTime: T.at(60),
                                                 originProvider: .garmin,
                                                 ingestProvider: .appleHealth))

        let backup = try await ObservationBackupService.makeBackup(store: store)

        XCTAssertEqual(backup.sections.map(\.provider), [.healthPit, .appleHealth, .garmin],
                       "HealthPit zuerst, danach die Erweiterungen")
        XCTAssertTrue(backup.sections.first?.isHealthPitOwn ?? false)
        XCTAssertEqual(backup.healthPitOwn?.observations.count, 1)
        XCTAssertEqual(backup.extensions.map(\.provider), [.appleHealth, .garmin])

        // Der Garmin-Wert steht bei Garmin, nicht bei Apple Health – der
        // Lieferweg ändert die Herkunft nicht.
        let garmin = try unwrap(backup.sections.first { $0.provider == .garmin })
        XCTAssertEqual(garmin.observations.first?.metricID, "HRT_RATE")
        XCTAssertEqual(garmin.observations.first?.ingestProvider, .appleHealth)
    }

    func testTheInventoryCountsWhatEachSourceSupplied() async throws {
        let store = try makeStore()
        _ = try await fill(store)
        try await store.insert(HealthObservation(metricID: "BDY_WEIGHT",
                                                 valueNumeric: 82.4,
                                                 unit: .kilogram,
                                                 startTime: T.at(0),
                                                 endTime: T.at(0),
                                                 originProvider: .healthPit,
                                                 ingestProvider: .healthPit))

        let inventory = try await ObservationBackupService.inventory(store: store)

        XCTAssertEqual(inventory.map(\.provider), [.healthPit, .appleHealth],
                       "HealthPit zuerst, danach die Erweiterungen")
        let own = try unwrap(inventory.first)
        XCTAssertTrue(own.isHealthPitOwn)
        XCTAssertEqual(own.observations, 1)
        XCTAssertEqual(own.workouts, 0)

        let apple = try unwrap(inventory.last)
        XCTAssertEqual(apple.observations, 1)
        XCTAssertEqual(apple.workouts, 1, "Das Training zählt mit")
        XCTAssertEqual(apple.total, 2)
        XCTAssertEqual(apple.providerName, "Apple Health")
    }

    func testExportingASingleSourceLeavesTheOthersOut() async throws {
        let store = try makeStore()
        _ = try await fill(store)
        try await store.insert(HealthObservation(metricID: "BDY_WEIGHT",
                                                 valueNumeric: 82.4,
                                                 unit: .kilogram,
                                                 startTime: T.at(0),
                                                 endTime: T.at(0),
                                                 originProvider: .healthPit,
                                                 ingestProvider: .healthPit))

        let own = try await ObservationBackupService.makeBackup(store: store)
            .filtered(to: [.healthPit])

        XCTAssertEqual(own.sections.map(\.provider), [.healthPit])
        XCTAssertEqual(own.observations.map(\.metricID), ["BDY_WEIGHT"])
        XCTAssertTrue(own.workouts.isEmpty)
        XCTAssertTrue(own.sourcePolicies.isEmpty,
                      "Die Freigabe gehört zu Apple Health und bleibt dort")

        // Und die Gegenprobe: Apple Health allein trägt seinen Schlaf, sein
        // Training und die Referenz dazu.
        let apple = try await ObservationBackupService.makeBackup(store: store)
            .filtered(to: [.appleHealth])
        XCTAssertEqual(apple.observations.map(\.metricID), ["SLP_DURATION"])
        XCTAssertEqual(apple.workouts.count, 1)
        XCTAssertEqual(apple.references.count, 1)
        XCTAssertEqual(apple.sourcePolicies.count, 1)
    }

    func testReferencesTravelWithTheirOrigin() async throws {
        let store = try makeStore()
        let (sleepID, _) = try await fill(store)

        let backup = try await ObservationBackupService.makeBackup(store: store)
        let apple = try unwrap(backup.sections.first { $0.provider == .appleHealth })

        XCTAssertEqual(apple.references.count, 1)
        XCTAssertEqual(apple.references.first?.entityID, sleepID.rawValue)
    }

    func testOnlyTheDataEnteredInHealthPitCanBeRestored() async throws {
        let source = try makeStore()
        _ = try await fill(source)
        try await source.insert(HealthObservation(metricID: "BDY_WEIGHT",
                                                  valueNumeric: 82.4,
                                                  unit: .kilogram,
                                                  startTime: T.at(0),
                                                  endTime: T.at(0),
                                                  originProvider: .healthPit,
                                                  ingestProvider: .healthPit))
        let backup = try await ObservationBackupService.makeBackup(store: source)

        let target = try makeStore()
        let report = try await ObservationBackupService.restore(backup,
                                                                into: target,
                                                                only: [.healthPit])

        XCTAssertEqual(report.observations, 1)
        XCTAssertEqual(report.byProvider["HPT"], 1)
        XCTAssertNil(report.byProvider["APP"])
        let weight = try await target.observations(metricID: "BDY_WEIGHT")
        XCTAssertEqual(weight.count, 1)
        let sleep = try await target.observations(metricID: "SLP_DURATION")
        XCTAssertTrue(sleep.isEmpty, "Apple-Health-Daten waren nicht angefordert")
    }

    func testAnOlderBackupFormatStillReads() throws {
        // Format 1: flache Listen ohne Abschnitte.
        let json = """
        {
          "version": 1,
          "exportedAt": "2026-08-12T16:18:26Z",
          "observations": [],
          "workouts": [],
          "references": [],
          "sourcePolicies": [],
          "customMetrics": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(HealthPitObservationBackup.self,
                                        from: Data(json.utf8))

        XCTAssertEqual(backup.version, 1)
        XCTAssertTrue(backup.isEmpty)
        XCTAssertTrue(backup.sections.isEmpty)
    }

    func testBackupSurvivesJSON() async throws {
        let store = try makeStore()
        _ = try await fill(store)
        let backup = try await ObservationBackupService.makeBackup(store: store)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let decoded = try decoder.decode(HealthPitObservationBackup.self, from: data)

        XCTAssertEqual(decoded.observations.first?.valueNumeric, 25_200)
        XCTAssertEqual(decoded.observations.first?.metricID, "SLP_DURATION")
        XCTAssertEqual(decoded.references.first?.externalRecordID, "APP-SLEEP-1")
        XCTAssertEqual(decoded.sections.map(\.provider), [.appleHealth])
        XCTAssertEqual(decoded.sections.first?.providerName, "Apple Health")
    }

    func testRestoreIntoAnEmptyDatabase() async throws {
        let source = try makeStore()
        _ = try await fill(source)
        let backup = try await ObservationBackupService.makeBackup(store: source)

        let target = try makeStore()
        let report = try await ObservationBackupService.restore(backup, into: target)

        XCTAssertEqual(report.observations, 1)
        XCTAssertEqual(report.workouts, 1)
        XCTAssertEqual(report.references, 1)
        let sleep = try await target.observations(metricID: "SLP_DURATION")
        XCTAssertEqual(sleep.count, 1)
        let stepsAllowed = try await target.isSourceEnabled(metricID: "ACT_STEPS", provider: .appleHealth)
        XCTAssertFalse(stepsAllowed, "Die Freigaben kommen mit zurück")
    }

    func testRestoringTwiceChangesNothing() async throws {
        let source = try makeStore()
        _ = try await fill(source)
        let backup = try await ObservationBackupService.makeBackup(store: source)

        let target = try makeStore()
        _ = try await ObservationBackupService.restore(backup, into: target)
        _ = try await ObservationBackupService.restore(backup, into: target)

        let count = try await target.observationCount(includeDeleted: true)
        XCTAssertEqual(count, 1)
        let references = try await target.referenceCount()
        XCTAssertEqual(references, 1)
    }

    func testAnOlderBackupDoesNotOverwriteNewerData() async throws {
        let source = try makeStore()
        let (sleepID, _) = try await fill(source)
        let backup = try await ObservationBackupService.makeBackup(store: source)

        // Inzwischen wurde der Wert korrigiert.
        let target = try makeStore()
        _ = try await ObservationBackupService.restore(backup, into: target)
        var newer = try unwrap(await target.observation(sleepID))
        newer.valueNumeric = 28_800
        newer.updatedAt = Date().addingTimeInterval(3600)
        newer.version += 1
        try await target.update(newer)

        _ = try await ObservationBackupService.restore(backup, into: target)

        let stored = try unwrap(await target.observation(sleepID))
        XCTAssertEqual(stored.valueNumeric, 28_800, "Die Sicherung ist älter und darf nicht zurückdrehen")
    }

    func testCustomMetricsComeAlong() async throws {
        let source = try makeStore()
        try await source.registerMetric(MetricDefinition("WHO_STRAIN_SCORE",
                                                         category: .proprietary,
                                                         name: "Whoop strain",
                                                         canonicalUnit: .score,
                                                         isProprietary: true,
                                                         proprietaryProvider: "WHO"))
        let backup = try await ObservationBackupService.makeBackup(store: source)
        XCTAssertEqual(backup.customMetrics.map(\.metricID), ["WHO_STRAIN_SCORE"])

        let target = try makeStore()
        let report = try await ObservationBackupService.restore(backup, into: target)
        XCTAssertEqual(report.metrics, 1)
        let known = try await target.knownMetricIDs()
        XCTAssertTrue(known.contains("WHO_STRAIN_SCORE"))
    }
}
