//
//  SyncScenarioTests.swift
//  HealthPitCoreTests
//
//  Die zwoelf geforderten Situationen, eine Testmethode je Punkt.
//

import Foundation
import XCTest
@testable import HealthPitCore

final class SyncScenarioTests: XCTestCase {

    // MARK: 1. Derselbe Garmin-Datensatz mehrfach importiert

    func test01_repeatedGarminImportCreatesOneObservation() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let incoming = IncomingObservation(sourceMetric: "heartRate",
                                           value: 72,
                                           unit: .beatsPerMinute,
                                           startTime: T.at(0),
                                           endTime: T.at(0),
                                           externalRecordID: "GAR-928374",
                                           sourceDeviceID: "fenix-7")

        let first = try await pipeline.import(incoming, from: .garmin)
        let second = try await pipeline.import(incoming, from: .garmin)
        let third = try await pipeline.import(incoming, from: .garmin)

        XCTAssertEqual(first.action, .create)
        XCTAssertEqual(second.action, .unchanged)
        XCTAssertEqual(third.action, .unchanged)
        XCTAssertEqual(first.observationID, second.observationID)
        let actual1 = try await observationCount(store, "HRT_RATE")
        XCTAssertEqual(actual1, 1)
        let actual2 = try await store.referenceCount()
        XCTAssertEqual(actual2, 1)
    }

    // MARK: 2. Derselbe Apple-Datensatz mehrfach importiert

    func test02_repeatedAppleImportCreatesOneObservation() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let sampleUUID = UUID().uuidString
        let incoming = IncomingObservation(sourceMetric: "HKQuantityTypeIdentifierStepCount",
                                           value: 8431,
                                           unit: .count,
                                           startTime: T.at(-86_400),
                                           endTime: T.at(0),
                                           aggregation: .sum,
                                           periodType: .day,
                                           externalRecordID: sampleUUID,
                                           sourceAppID: "com.apple.Health",
                                           sourceDeviceID: "iPhone")

        let first = try await pipeline.import(incoming, from: .appleHealth)
        let second = try await pipeline.import(incoming, from: .appleHealth)

        XCTAssertEqual(first.action, .create)
        XCTAssertEqual(second.action, .unchanged)
        let actual3 = try await observationCount(store, "ACT_STEPS")
        XCTAssertEqual(actual3, 1)
    }

    // MARK: 3. Export nach Apple Health und Reimport – keine Schleife

    func test03_exportThenReimportDoesNotCreateSecondObservation() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let apple = RecordingAdapter(provider: .appleHealth)
        let importPipeline = ImportPipeline(store: store)
        let exportPipeline = ExportPipeline(store: store)

        // Ein in HealthPit entstandener Wert. Aktive Energie ist einer der
        // Typen, die die App wirklich nach Apple Health schreibt.
        let observation = HealthObservation(metricID: "NRG_ACTIVE",
                                            valueNumeric: 512,
                                            unit: .kilocalorie,
                                            startTime: T.at(-3600),
                                            endTime: T.at(0),
                                            aggregation: .sum,
                                            periodType: .day,
                                            originProvider: .healthPit,
                                            ingestProvider: .healthPit)
        try await store.insert(observation)

        let exported = try await exportPipeline.export(observation, to: apple)
        XCTAssertEqual(exported.action, .create)
        let recordID = try XCTUnwrap(exported.externalRecordID)

        // Apple liefert denselben Datensatz beim naechsten Sync zurueck.
        let echoed = try XCTUnwrap(apple.echoBack(externalRecordID: recordID))
        XCTAssertTrue(echoed.syncIdentifier?.hasPrefix(SyncIdentifier.prefix) ?? false)

        let reimported = try await importPipeline.import(echoed, from: .appleHealth, adapter: apple)
        XCTAssertEqual(reimported.action, .loopBlocked)
        XCTAssertEqual(reimported.observationID, observation.observationID)
        let actual4 = try await observationCount(store, "NRG_ACTIVE")
        XCTAssertEqual(actual4, 1)

        // Und der naechste Exportlauf schreibt nichts nach – die Schleife
        // endet hier, nicht erst nach dem dritten Durchgang.
        let again = try await exportPipeline.export(observation, to: apple)
        XCTAssertEqual(again.action, .skip)
        XCTAssertEqual(apple.writes.count, 1)
    }

    // MARK: 4. Garmin direkt und zusaetzlich ueber Apple Health

    func test04_sameValueViaTwoProvidersStaysOneObservation() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let direct = IncomingObservation(sourceMetric: "heartRate",
                                         value: 72,
                                         unit: .beatsPerMinute,
                                         startTime: T.at(0),
                                         endTime: T.at(0),
                                         originProvider: .garmin,
                                         originExternalID: "GAR-928374",
                                         externalRecordID: "GAR-928374",
                                         sourceDeviceID: "fenix-7")
        let fromGarmin = try await pipeline.import(direct, from: .garmin)
        XCTAssertEqual(fromGarmin.action, .create)

        // Derselbe Wert, den Garmin nach Apple Health geschrieben hat. Apple
        // reicht die Garmin-Record-ID durch.
        let viaApple = IncomingObservation(sourceMetric: "HKQuantityTypeIdentifierHeartRate",
                                           value: 72,
                                           unit: .beatsPerMinute,
                                           startTime: T.at(0),
                                           endTime: T.at(0),
                                           originProvider: .garmin,
                                           originExternalID: "GAR-928374",
                                           externalRecordID: "APPLE-SAMPLE-1",
                                           sourceAppID: "com.garmin.connect.mobile",
                                           sourceDeviceID: "fenix-7")
        let fromApple = try await pipeline.import(viaApple, from: .appleHealth)

        XCTAssertEqual(fromApple.action, .deduplicate)
        XCTAssertEqual(fromApple.matchedBy, .originRecordID)
        XCTAssertEqual(fromApple.observationID, fromGarmin.observationID)
        let actual5 = try await observationCount(store, "HRT_RATE")
        XCTAssertEqual(actual5, 1)

        // Eine Observation, zwei externe Repraesentationen.
        let references = try await store.references(entityType: .observation,
                                                    entityID: fromGarmin.observationID!.rawValue)
        XCTAssertEqual(Set(references.map(\.provider)), [.garmin, .appleHealth])
    }

    func test04b_sameValueWithoutOriginIDStillMatchesHeuristically() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let direct = IncomingObservation(sourceMetric: "heartRate",
                                         value: 72,
                                         unit: .beatsPerMinute,
                                         startTime: T.at(0),
                                         endTime: T.at(0),
                                         originProvider: .garmin,
                                         externalRecordID: "GAR-1",
                                         sourceDeviceID: "fenix-7")
        let first = try await pipeline.import(direct, from: .garmin)

        // Apple kennt die Garmin-ID nicht, weiss aber, dass die Quelle Garmin
        // ist. Ohne ID zaehlt das als Indiz – und wird als solches vermerkt.
        let viaApple = IncomingObservation(sourceMetric: "HKQuantityTypeIdentifierHeartRate",
                                           value: 72,
                                           unit: .beatsPerMinute,
                                           startTime: T.at(0),
                                           endTime: T.at(0),
                                           originProvider: .garmin,
                                           externalRecordID: "APPLE-1",
                                           sourceDeviceID: "fenix-7")
        let second = try await pipeline.import(viaApple, from: .appleHealth)

        XCTAssertEqual(second.action, .deduplicate)
        XCTAssertEqual(second.matchedBy, .heuristic)
        XCTAssertEqual(second.observationID, first.observationID)

        let reference = try await store.reference(entityType: .observation,
                                                  entityID: first.observationID!.rawValue,
                                                  provider: .appleHealth)
        XCTAssertEqual(reference?.metadata["confidence"], "heuristic")
    }

    // MARK: 5. Zwei echte Messungen mit demselben Wert

    func test05_twoDistinctMeasurementsWithSameValueStaySeparate() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let morning = IncomingObservation(sourceMetric: "heartRate",
                                          value: 72,
                                          unit: .beatsPerMinute,
                                          startTime: T.at(0),
                                          endTime: T.at(0),
                                          externalRecordID: "GAR-A",
                                          sourceDeviceID: "fenix-7")
        let evening = IncomingObservation(sourceMetric: "heartRate",
                                          value: 72,
                                          unit: .beatsPerMinute,
                                          startTime: T.at(3600),
                                          endTime: T.at(3600),
                                          externalRecordID: "GAR-B",
                                          sourceDeviceID: "fenix-7")

        let first = try await pipeline.import(morning, from: .garmin)
        let second = try await pipeline.import(evening, from: .garmin)

        XCTAssertEqual(first.action, .create)
        XCTAssertEqual(second.action, .create)
        XCTAssertNotEqual(first.observationID, second.observationID)
        let actual6 = try await observationCount(store, "HRT_RATE")
        XCTAssertEqual(actual6, 2)
    }

    func test05b_sameSecondButDifferentDevicesStaySeparate() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let watch = IncomingObservation(sourceMetric: "heartRate", value: 72, unit: .beatsPerMinute,
                                        startTime: T.at(0), endTime: T.at(0),
                                        externalRecordID: "GAR-WATCH", sourceDeviceID: "fenix-7")
        let strap = IncomingObservation(sourceMetric: "heartRate", value: 72, unit: .beatsPerMinute,
                                        startTime: T.at(0), endTime: T.at(0),
                                        externalRecordID: "GAR-STRAP", sourceDeviceID: "hrm-pro")

        _ = try await pipeline.import(watch, from: .garmin)
        _ = try await pipeline.import(strap, from: .garmin)

        let actual7 = try await observationCount(store, "HRT_RATE")
        XCTAssertEqual(actual7, 2)
    }

    // MARK: 6. Anbieter aktualisiert einen bekannten Wert

    func test06_updatedProviderRecordUpdatesExistingObservation() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        var incoming = IncomingObservation(sourceMetric: "sleeps.deepSleepDurationInSeconds",
                                           value: 3600,
                                           unit: .second,
                                           startTime: T.at(-28_800),
                                           endTime: T.at(-3600),
                                           aggregation: .sum,
                                           periodType: .night,
                                           externalRecordID: "GAR-SLEEP-1")
        let created = try await pipeline.import(incoming, from: .garmin)
        XCTAssertEqual(created.action, .create)

        // Garmin wertet die Nacht nachtraeglich neu aus.
        incoming.value = 4200
        let updated = try await pipeline.import(incoming, from: .garmin)

        XCTAssertEqual(updated.action, .update)
        XCTAssertEqual(updated.observationID, created.observationID)
        let actual8 = try await observationCount(store, "SLP_DEEP_DURATION")
        XCTAssertEqual(actual8, 1)

        let stored = try unwrap(await store.observation(created.observationID!))
        XCTAssertEqual(stored.valueNumeric, 4200)
        XCTAssertEqual(stored.version, 2)
    }

    // MARK: 7. Anbieter loescht einen Wert

    func test07_deleteFromNonOriginProviderKeepsObservation() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        // Ein Garmin-Wert, den HealthPit ueber Apple Health bekommen hat.
        let viaApple = IncomingObservation(sourceMetric: "HKQuantityTypeIdentifierHeartRate",
                                           value: 65,
                                           unit: .beatsPerMinute,
                                           startTime: T.at(0),
                                           endTime: T.at(0),
                                           originProvider: .garmin,
                                           externalRecordID: "APPLE-DEL-1")
        let created = try await pipeline.import(viaApple, from: .appleHealth)

        var deletion = viaApple
        deletion.isDeleted = true
        let deleted = try await pipeline.import(deletion, from: .appleHealth)

        XCTAssertEqual(deleted.action, .delete)
        let stored = try unwrap(await store.observation(created.observationID!))
        // Die Kopie in Apple Health ist weg, der Garmin-Wert dahinter nicht.
        XCTAssertNil(stored.deletedAt)
        let reference = try await store.reference(entityType: .observation,
                                                  entityID: created.observationID!.rawValue,
                                                  provider: .appleHealth)
        XCTAssertEqual(reference?.status, .deletedRemote)
    }

    func test07b_deleteFromOriginProviderSoftDeletesObservation() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let incoming = IncomingObservation(sourceMetric: "heartRate",
                                           value: 65,
                                           unit: .beatsPerMinute,
                                           startTime: T.at(0),
                                           endTime: T.at(0),
                                           externalRecordID: "GAR-DEL-1")
        let created = try await pipeline.import(incoming, from: .garmin)

        var deletion = incoming
        deletion.isDeleted = true
        _ = try await pipeline.import(deletion, from: .garmin)

        let stored = try unwrap(await store.observation(created.observationID!))
        XCTAssertNotNil(stored.deletedAt, "Der Erzeuger darf loeschen")
        // Weich geloescht: die Zeile ist noch da, taucht aber nicht mehr auf.
        let actual9 = try await observationCount(store, "HRT_RATE")
        XCTAssertEqual(actual9, 0)
        let actual10 = try await store.observationCount(includeDeleted: true)
        XCTAssertEqual(actual10, 1)
    }

    // MARK: 8. Derselbe Exportjob laeuft mehrfach

    func test08_repeatedExportJobWritesOnce() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let apple = RecordingAdapter(provider: .appleHealth)
        let exportPipeline = ExportPipeline(store: store)

        let observation = HealthObservation(metricID: "NRG_ACTIVE",
                                            valueNumeric: 512,
                                            unit: .kilocalorie,
                                            startTime: T.at(-3600),
                                            endTime: T.at(0),
                                            aggregation: .sum,
                                            periodType: .day,
                                            originProvider: .healthPit,
                                            ingestProvider: .healthPit)
        try await store.insert(observation)

        for _ in 0..<5 {
            _ = try await exportPipeline.export(observation, to: apple)
        }

        XCTAssertEqual(apple.writes.count, 1)
        XCTAssertEqual(apple.writes.first?.action, .create)
        let references = try await store.references(entityType: .observation,
                                                    entityID: observation.observationID.rawValue)
        XCTAssertEqual(references.count, 1)
    }

    // MARK: 9. Neue Version einer Observation wird exportiert

    func test09_changedObservationIsUpdatedNotCreated() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let apple = RecordingAdapter(provider: .appleHealth)
        let exportPipeline = ExportPipeline(store: store)

        var observation = HealthObservation(metricID: "NRG_ACTIVE",
                                            valueNumeric: 512,
                                            unit: .kilocalorie,
                                            startTime: T.at(-3600),
                                            endTime: T.at(0),
                                            aggregation: .sum,
                                            periodType: .day,
                                            originProvider: .healthPit,
                                            ingestProvider: .healthPit)
        try await store.insert(observation)
        _ = try await exportPipeline.export(observation, to: apple)

        observation.valueNumeric = 538
        observation.version += 1
        observation.updatedAt = Date()
        try await store.update(observation)

        let second = try await exportPipeline.export(observation, to: apple)

        XCTAssertEqual(second.action, .update)
        XCTAssertEqual(apple.writes.count, 2)
        XCTAssertEqual(apple.writes.last?.action, .update)
        XCTAssertNotNil(apple.writes.last?.externalRecordID, "Update braucht die bestehende Anbieter-ID")
        XCTAssertEqual(apple.writes.first?.externalRecordID, nil)
        let referenceCount = try await store.references(entityType: .observation,
                                                        entityID: observation.observationID.rawValue).count
        XCTAssertEqual(referenceCount, 1)
    }

    // MARK: 10. Proprietaere Scores verschiedener Anbieter

    func test10_proprietaryScoresAreNeverMerged() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        try await store.upsertMapping(ProviderMetricMapping(provider: .oura,
                                                            sourceMetric: "daily_readiness.score",
                                                            metricID: "OUR_READINESS_SCORE",
                                                            sourceUnit: .score,
                                                            canonicalUnit: .score))
        let pipeline = ImportPipeline(store: store)

        let garmin = IncomingObservation(sourceMetric: "bodyBattery",
                                         value: 70,
                                         unit: .score,
                                         startTime: T.at(0),
                                         endTime: T.at(0),
                                         aggregation: .score,
                                         externalRecordID: "GAR-BB-1")
        let oura = IncomingObservation(sourceMetric: "daily_readiness.score",
                                       value: 70,
                                       unit: .score,
                                       startTime: T.at(0),
                                       endTime: T.at(0),
                                       aggregation: .score,
                                       externalRecordID: "OUR-RS-1")

        let first = try await pipeline.import(garmin, from: .garmin)
        let second = try await pipeline.import(oura, from: .oura)

        XCTAssertEqual(first.action, .create)
        XCTAssertEqual(second.action, .create)
        let actual11 = try await observationCount(store, "GAR_BODY_BATTERY")
        XCTAssertEqual(actual11, 1)
        let actual12 = try await observationCount(store, "OUR_READINESS_SCORE")
        XCTAssertEqual(actual12, 1)

        let registry = MetricRegistry()
        XCTAssertFalse(registry.areComparable("GAR_BODY_BATTERY", "OUR_READINESS_SCORE"))
        XCTAssertTrue(registry.definition("GAR_BODY_BATTERY")?.isProprietary ?? false)
        XCTAssertEqual(registry.definition("OUR_READINESS_SCORE")?.proprietaryProvider, .oura)
    }

    // MARK: 12. Unbekannter zukuenftiger Anbieter

    func test12_newProviderNeedsOnlyRegistryMappingAndAdapter() async throws {
        let store = try makeStore()
        try await seedMappings(store)

        // Ein Anbieter, den das Kernmodell nicht kennt.
        let whoop: ProviderCode = "WHO"
        try await store.registerProvider(ProviderDefinition(code: whoop,
                                                            name: "Whoop",
                                                            kind: .vendor,
                                                            canRead: true,
                                                            canWrite: true,
                                                            supportsSyncIdentifier: false,
                                                            hasStableRecordIDs: true,
                                                            isImplemented: true))
        try await store.registerMetric(MetricDefinition("WHO_STRAIN_SCORE",
                                                        category: .proprietary,
                                                        name: "Whoop strain score",
                                                        canonicalUnit: .score,
                                                        isProprietary: true,
                                                        proprietaryProvider: whoop))
        try await store.upsertMapping(ProviderMetricMapping(provider: whoop,
                                                            sourceMetric: "cycle.strain",
                                                            metricID: "WHO_STRAIN_SCORE",
                                                            sourceUnit: .score,
                                                            canonicalUnit: .score))
        try await store.upsertMapping(ProviderMetricMapping(provider: whoop,
                                                            sourceMetric: "cycle.average_heart_rate",
                                                            metricID: "HRT_RATE",
                                                            sourceUnit: .beatsPerMinute,
                                                            canonicalUnit: .beatsPerMinute,
                                                            canWrite: true))

        let pipeline = ImportPipeline(store: store)
        let strain = try await pipeline.import(IncomingObservation(sourceMetric: "cycle.strain",
                                                                   value: 14.6,
                                                                   unit: .score,
                                                                   startTime: T.at(0),
                                                                   endTime: T.at(0),
                                                                   aggregation: .score,
                                                                   externalRecordID: "WHO-1"),
                                               from: whoop)
        let heart = try await pipeline.import(IncomingObservation(sourceMetric: "cycle.average_heart_rate",
                                                                  value: 58,
                                                                  unit: .beatsPerMinute,
                                                                  startTime: T.at(0),
                                                                  endTime: T.at(0),
                                                                  aggregation: .average,
                                                                  externalRecordID: "WHO-2"),
                                              from: whoop)

        XCTAssertEqual(strain.action, .create)
        XCTAssertEqual(heart.action, .create)
        // Der Puls landet auf derselben fachlichen Metrik wie bei allen anderen.
        let actual13 = try await observationCount(store, "HRT_RATE")
        XCTAssertEqual(actual13, 1)

        // Und der Export funktioniert ueber denselben Weg.
        let adapter = RecordingAdapter(provider: whoop)
        let observation = try unwrap(await store.observation(heart.observationID!))
        var local = observation
        local.ingestProvider = .healthPit
        local.valueNumeric = 59
        local.version += 1
        try await store.update(local)
        let result = try await ExportPipeline(store: store).export(local, to: adapter)
        XCTAssertEqual(result.action, .update)
    }

    // MARK: Einheiten und Herkunft

    func testUnitNormalisationKeepsSourceValue() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        try await store.upsertMapping(ProviderMetricMapping(provider: .fitbit,
                                                            sourceMetric: "body/log/weight",
                                                            metricID: "BDY_WEIGHT",
                                                            sourceUnit: .pound,
                                                            canonicalUnit: .kilogram))
        let pipeline = ImportPipeline(store: store)

        let result = try await pipeline.import(IncomingObservation(sourceMetric: "body/log/weight",
                                                                   value: 181.66,
                                                                   unit: .pound,
                                                                   startTime: T.at(0),
                                                                   endTime: T.at(0),
                                                                   externalRecordID: "FIT-1"),
                                               from: .fitbit)

        let stored = try unwrap(await store.observation(result.observationID!))
        XCTAssertEqual(stored.unit, .kilogram)
        XCTAssertEqual(stored.valueNumeric ?? 0, 82.4, accuracy: 0.01)
        XCTAssertEqual(stored.sourceValue, 181.66)
        XCTAssertEqual(stored.sourceUnit, .pound)
    }

    func testOriginAndIngestAreKeptApart() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)

        let result = try await pipeline.import(IncomingObservation(sourceMetric: "HKQuantityTypeIdentifierHeartRate",
                                                                   value: 72,
                                                                   unit: .beatsPerMinute,
                                                                   startTime: T.at(0),
                                                                   endTime: T.at(0),
                                                                   originProvider: .garmin,
                                                                   externalRecordID: "APPLE-2",
                                                                   sourceAppID: "com.garmin.connect.mobile"),
                                               from: .appleHealth)

        let stored = try unwrap(await store.observation(result.observationID!))
        XCTAssertEqual(stored.originProvider, .garmin)
        XCTAssertEqual(stored.ingestProvider, .appleHealth)
        XCTAssertEqual(stored.sourceMetric, "HKQuantityTypeIdentifierHeartRate")
    }

    func testSyncEventsRecordWhatHappened() async throws {
        let store = try makeStore()
        try await seedMappings(store)
        let pipeline = ImportPipeline(store: store)
        let incoming = IncomingObservation(sourceMetric: "heartRate", value: 72, unit: .beatsPerMinute,
                                           startTime: T.at(0), endTime: T.at(0),
                                           externalRecordID: "GAR-LOG-1")
        let created = try await pipeline.import(incoming, from: .garmin)
        _ = try await pipeline.import(incoming, from: .garmin)

        let events = try await store.syncEvents(entityID: created.observationID!.rawValue)
        XCTAssertEqual(events.map(\.action), [.create, .unchanged])
        XCTAssertTrue(events.allSatisfy { $0.direction == .importing && $0.status == .ok })
    }
}
