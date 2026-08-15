//
//  ModelTests.swift
//  HealthPitCoreTests
//
//  Grundlagen: Registry, Identifier, Einheiten, Constraints. Das sind die
//  Zusagen, auf denen die Sync-Tests aufbauen.
//

import Foundation
import XCTest
@testable import HealthPitCore

final class ModelTests: XCTestCase {

    func testRegistryIsConsistent() {
        let registry = MetricRegistry()
        XCTAssertEqual(registry.validate(), [], "Die eingebaute Registry muss sauber sein")
        XCTAssertTrue(registry.contains("HRT_RATE"))
        XCTAssertEqual(registry.canonicalUnit(for: "BDY_WEIGHT"), .kilogram)
        XCTAssertEqual(registry.canonicalUnit(for: "ACT_DISTANCE"), .meter)
        XCTAssertEqual(registry.canonicalUnit(for: "RSP_SPO2"), .percent)
    }

    func testMetricIDRules() {
        XCTAssertTrue(MetricID.isValid("HRT_RATE"))
        XCTAssertTrue(MetricID.isValid("ACT_STEPS"))
        XCTAssertFalse(MetricID.isValid("hrt_rate"), "Kleinbuchstaben sind nicht erlaubt")
        XCTAssertFalse(MetricID.isValid("HRT-RATE"), "Nur der Unterstrich trennt")
        XCTAssertFalse(MetricID.isValid("HRT RATE"))
        XCTAssertFalse(MetricID.isValid("HRT__RATE"))
        XCTAssertFalse(MetricID.isValid("HRT_RATE_"))
        XCTAssertFalse(MetricID.isValid(""))
    }

    func testObservationIDIsUUIDv7AndSortsByTime() throws {
        let early = ObservationID.generate(at: Date(timeIntervalSince1970: 1_700_000_000))
        let late = ObservationID.generate(at: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertLessThan(early, late, "UUIDv7 muss zeitlich sortierbar sein")

        let stamp = try XCTUnwrap(late.embeddedTimestamp)
        XCTAssertEqual(stamp.timeIntervalSince1970, 1_800_000_000, accuracy: 1)

        // Version- und Variantenbits nach RFC 9562.
        let bytes = try XCTUnwrap(UUID(uuidString: late.rawValue)).uuid
        XCTAssertEqual(bytes.6 & 0xF0, 0x70)
        XCTAssertEqual(bytes.8 & 0xC0, 0x80)

        var seen = Set<String>()
        for _ in 0..<1000 { seen.insert(ObservationID.generate().rawValue) }
        XCTAssertEqual(seen.count, 1000, "IDs muessen eindeutig sein")
    }

    func testSyncIdentifierRoundTrip() {
        let id = ObservationID.generate()
        let marker = SyncIdentifier.make(for: id)
        XCTAssertEqual(marker, "HEALTHPIT:OBS-\(id.rawValue)")
        XCTAssertEqual(SyncIdentifier.observationID(from: marker), id)
        XCTAssertNil(SyncIdentifier.observationID(from: "GARMIN-123"))
        XCTAssertNil(SyncIdentifier.observationID(from: nil))
        XCTAssertTrue(SyncIdentifier.isHealthPitOwned(marker))
    }

    func testUnitConversion() throws {
        XCTAssertEqual(try UnitConverter.convert(181.66, from: .pound, to: .kilogram), 82.4, accuracy: 0.01)
        XCTAssertEqual(try UnitConverter.convert(8.2, from: .kilometer, to: .meter), 8200, accuracy: 0.001)
        XCTAssertEqual(try UnitConverter.convert(60, from: .minute, to: .second), 3600, accuracy: 0.001)
        XCTAssertEqual(try UnitConverter.convert(37, from: .celsius, to: .fahrenheit), 98.6, accuracy: 0.01)
        XCTAssertEqual(try UnitConverter.convert(36, from: .kilometersPerHour, to: .metersPerSecond),
                       10, accuracy: 0.001)

        // Ein Puls ist keine Trittfrequenz – auch wenn beides „pro Minute“ ist.
        XCTAssertThrowsError(try UnitConverter.convert(72, from: .beatsPerMinute, to: .revolutionsPerMinute))
        XCTAssertThrowsError(try UnitConverter.convert(1, from: .kilogram, to: .meter))
    }

    func testAppleHealthMappingCoversTheCurrentMetricSet() {
        // Jede Zeile zeigt auf eine registrierte Metrik.
        let registry = MetricRegistry()
        for entry in AppleHealthMapping.all {
            XCTAssertTrue(registry.contains(entry.metricID),
                          "\(entry.metricID) fehlt in der Registry")
        }
        // Und die bisherigen Schluessel der App finden ihr Ziel.
        XCTAssertEqual(AppleHealthMapping.metricID(forLegacyIdentifier: "HKQuantityTypeIdentifierStepCount"),
                       "ACT_STEPS")
        XCTAssertEqual(AppleHealthMapping.metricID(forLegacyIdentifier: "HKQuantityTypeIdentifierBodyMass"),
                       "BDY_WEIGHT")
        XCTAssertEqual(AppleHealthMapping.metricID(forLegacyIdentifier: "HKQuantityTypeIdentifierHeartRate"),
                       "HRT_RATE")
        XCTAssertNil(AppleHealthMapping.metricID(forLegacyIdentifier: "HKQuantityTypeIdentifierUnknown"))
    }

    func testVendorMappingsPointAtKnownMetrics() {
        let registry = MetricRegistry()
        for mapping in GarminMapping.mappings + HuaweiMapping.mappings {
            XCTAssertTrue(registry.contains(mapping.metricID), "\(mapping.metricID) fehlt")
            if let source = mapping.sourceUnit, let target = mapping.canonicalUnit {
                XCTAssertTrue(UnitConverter.canConvert(from: source, to: target),
                              "\(mapping.sourceMetric): \(source) laesst sich nicht in \(target) rechnen")
            }
        }
    }

    func testExternalReferenceUniqueness() async throws {
        let store = try makeStore()
        let observationID = ObservationID.generate()
        let other = ObservationID.generate()

        _ = try await store.upsert(ExternalReference(entityID: observationID.rawValue,
                                                     provider: .garmin,
                                                     externalRecordID: "GAR-1"))
        // Dieselbe externe ID beim selben Anbieter darf keine zweite Zeile
        // erzeugen – sonst waere Idempotenz nicht garantiert.
        _ = try await store.upsert(ExternalReference(entityID: observationID.rawValue,
                                                     provider: .garmin,
                                                     externalRecordID: "GAR-1"))
        let actual1 = try await store.referenceCount()
        XCTAssertEqual(actual1, 1)

        // Dieselbe ID bei einem anderen Anbieter ist etwas anderes.
        _ = try await store.upsert(ExternalReference(entityID: other.rawValue,
                                                     provider: .huawei,
                                                     externalRecordID: "GAR-1"))
        let actual2 = try await store.referenceCount()
        XCTAssertEqual(actual2, 2)
    }

    func testStoreRoundTripKeepsEveryField() async throws {
        let store = try makeStore()
        let observation = HealthObservation(metricID: "SLP_STAGE",
                                            valueType: .enumerated,
                                            valueCode: "DEEP",
                                            startTime: T.at(-3600),
                                            endTime: T.at(0),
                                            timezone: "Europe/Berlin",
                                            aggregation: .raw,
                                            periodType: .interval,
                                            originProvider: .garmin,
                                            ingestProvider: .appleHealth,
                                            originExternalID: "GAR-SLEEP-9",
                                            sourceMetric: "sleeps.deep",
                                            sourceAppID: "com.garmin.connect.mobile",
                                            sourceDeviceID: "fenix-7",
                                            sourceDeviceModel: "Fenix 7",
                                            sessionID: "night-1",
                                            metadata: ["note": "test"],
                                            rawPayload: "{\"deep\":true}")
        try await store.insert(observation)

        let loaded = try unwrap(await store.observation(observation.observationID))
        XCTAssertEqual(loaded.metricID, observation.metricID)
        XCTAssertEqual(loaded.valueCode, "DEEP")
        XCTAssertEqual(loaded.valueType, .enumerated)
        XCTAssertEqual(loaded.timezone, "Europe/Berlin")
        XCTAssertEqual(loaded.originProvider, .garmin)
        XCTAssertEqual(loaded.ingestProvider, .appleHealth)
        XCTAssertEqual(loaded.originExternalID, "GAR-SLEEP-9")
        XCTAssertEqual(loaded.sourceDeviceModel, "Fenix 7")
        XCTAssertEqual(loaded.sessionID, "night-1")
        XCTAssertEqual(loaded.metadata["note"], "test")
        XCTAssertEqual(loaded.rawPayload, "{\"deep\":true}")
        XCTAssertEqual(loaded.contentHash, observation.contentHash)
    }

    func testSchemaHasTheExpectedTables() async throws {
        let store = try makeStore()
        let expected = ["metric_definition", "provider", "provider_metric_mapping",
                        "health_observation", "workout", "external_reference",
                        "sync_event", "migration_state"]
        // Ein Schreibzugriff je Tabelle wuerde reichen; hier genuegt, dass die
        // Registry vollstaendig eingespielt wurde.
        let metricIDs = try await store.knownMetricIDs()
        XCTAssertEqual(metricIDs.count, MetricRegistry().all.count)
        XCTAssertTrue(metricIDs.contains("HRT_RATE"))
        for table in expected {
            try await store.executeRaw("SELECT COUNT(*) FROM \(table);")
        }
    }
}
