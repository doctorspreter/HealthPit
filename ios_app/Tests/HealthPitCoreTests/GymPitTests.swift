//
//  GymPitTests.swift
//  HealthPitCoreTests
//
//  GymPit liefert heute ueber die Bridge und zusaetzlich als Kopie in Apple
//  Health. Beides muss auf dasselbe Training zeigen – heute wie spaeter, wenn
//  GymPit direkt im neuen Format sendet.
//

import Foundation
import XCTest
@testable import HealthPitCore

final class GymPitTests: XCTestCase {

    private func seed(_ store: HealthPitStore) async throws {
        try await seedMappings(store)
        for mapping in GymPitMapping.mappings {
            try await store.upsertMapping(mapping)
        }
    }

    func testGymPitWorkoutArrivesOnceEvenWhenUploadedRepeatedly() async throws {
        let store = try makeStore()
        try await seed(store)
        let pipeline = ImportPipeline(store: store)

        let workout = GymPitIngestContract.makeIncomingWorkout(
            workoutID: "GYM-4711",
            sportType: "strength_training",
            title: "Push Day",
            start: T.at(-7200),
            end: T.at(-3600),
            observations: [
                IncomingObservation(sourceMetric: "workout.energy_kcal",
                                    value: 420,
                                    startTime: T.at(-7200),
                                    endTime: T.at(-3600),
                                    aggregation: .sum,
                                    periodType: .workout,
                                    originProvider: .gymPit,
                                    externalRecordID: "GYM-4711-energy")
            ])

        let first = try await pipeline.import(workout, from: .gymPit)
        let second = try await pipeline.import(workout, from: .gymPit)

        XCTAssertEqual(first.action, .create)
        XCTAssertEqual(second.action, .unchanged)
        let workoutCount = try await store.workoutCount()
        XCTAssertEqual(workoutCount, 1)
        let energy = try await store.observations(metricID: "WRK_ENERGY")
        XCTAssertEqual(energy.count, 1)
        XCTAssertEqual(energy.first?.originProvider, .gymPit)
    }

    func testAppleHealthCopyOfAGymPitWorkoutIsRecognised() async throws {
        let store = try makeStore()
        try await seed(store)
        let pipeline = ImportPipeline(store: store)

        // Direkt von GymPit.
        let direct = try await pipeline.import(
            GymPitIngestContract.makeIncomingWorkout(workoutID: "GYM-4711",
                                                     sportType: "strength_training",
                                                     title: "Push Day",
                                                     start: T.at(-7200),
                                                     end: T.at(-3600)),
            from: .gymPit)
        XCTAssertEqual(direct.action, .create)

        // Dieselbe Einheit, die GymPit zusaetzlich nach Apple Health
        // geschrieben hat: eigene HealthKit-UUID, aber die GymPit-ID reist
        // als HKMetadataKeyExternalUUID mit.
        let viaApple = try await pipeline.import(
            IncomingWorkout(sportType: "TRADITIONAL_STRENGTH_TRAINING",
                            title: "Krafttraining",
                            startTime: T.at(-7200),
                            endTime: T.at(-3600),
                            originProvider: .gymPit,
                            originExternalID: "GYM-4711",
                            externalRecordID: UUID().uuidString,
                            sourceAppID: "de.tauwe.gympit"),
            from: .appleHealth)

        XCTAssertEqual(viaApple.action, .deduplicate)
        XCTAssertEqual(viaApple.matchedBy, .originRecordID)
        XCTAssertEqual(viaApple.workoutID, direct.workoutID)

        let workoutCount = try await store.workoutCount()
        XCTAssertEqual(workoutCount, 1, "Ein Training, zwei Wege")

        let references = try await store.references(entityType: .workout,
                                                    entityID: direct.workoutID!.rawValue)
        XCTAssertEqual(Set(references.map(\.provider)), [.gymPit, .appleHealth])
    }

    func testGymPitCorrectionUpdatesTheWorkout() async throws {
        let store = try makeStore()
        try await seed(store)
        let pipeline = ImportPipeline(store: store)

        var workout = GymPitIngestContract.makeIncomingWorkout(workoutID: "GYM-99",
                                                               sportType: "strength_training",
                                                               title: "Pull Day",
                                                               start: T.at(-7200),
                                                               end: T.at(-3600))
        let created = try await pipeline.import(workout, from: .gymPit)

        // Der Nutzer haengt in GymPit nachtraeglich zehn Minuten an.
        workout.endTime = T.at(-3000)
        let updated = try await pipeline.import(workout, from: .gymPit)

        XCTAssertEqual(updated.action, .update)
        XCTAssertEqual(updated.workoutID, created.workoutID)
        let workoutCount = try await store.workoutCount()
        XCTAssertEqual(workoutCount, 1)
    }

    func testSourceDetectionForAppleHealthCopies() {
        XCTAssertTrue(GymPitMapping.isGymPitSource(bundleIdentifier: "de.tauwe.gympit",
                                                   sourceName: nil))
        XCTAssertTrue(GymPitMapping.isGymPitSource(bundleIdentifier: nil,
                                                   sourceName: "GymPit"))
        XCTAssertFalse(GymPitMapping.isGymPitSource(bundleIdentifier: "com.apple.Health",
                                                    sourceName: "Fitness"))
    }

    func testGymPitMappingsPointAtKnownMetrics() {
        let registry = MetricRegistry()
        for mapping in GymPitMapping.mappings {
            XCTAssertTrue(registry.contains(mapping.metricID), "\(mapping.metricID) fehlt")
        }
    }
}
