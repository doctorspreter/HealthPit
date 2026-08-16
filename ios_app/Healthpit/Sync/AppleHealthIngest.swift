//
//  AppleHealthIngest.swift
//  Healthpit
//
//  Apple Health hinein in die Datenbank – der einzige Weg, auf dem
//  Apple-Health-Werte in HealthPit ankommen.
//
//  Gelesen wird ueber die Tabelle in `AppleHealthMapping`: Sie sagt, welcher
//  HealthKit-Typ welche Metrik ist, in welcher Einheit gelesen wird und wie
//  der Wert zusammengefasst gehoert. Was hier herausfaellt, geht durch die
//  ImportPipeline – dieselbe, die auch Garmin, Huawei, GymPit und die Bridge
//  benutzen. Damit gilt fuer jede Quelle dieselbe Erkennung, und ein Wert
//  entsteht genau einmal.
//

import Foundation
import HealthKit

struct AppleHealthIngestReport: Sendable, Equatable {
    var dailyValues = 0
    var nights = 0
    var sleepSegments = 0
    var workouts = 0
    var cycleDays = 0
    /// Ab wann Apple Health ueberhaupt etwas hat.
    var earliest: Date?

    var didFindAnything: Bool {
        dailyValues > 0 || nights > 0 || workouts > 0 || cycleDays > 0
    }
}

/// Fortschritt fuer die Oberflaeche: Was gerade laeuft und wie weit.
struct IngestProgress: Sendable, Equatable {
    var step: String = ""
    /// 0…1, `nil` solange die Gesamtmenge unbekannt ist.
    var fraction: Double?
}

actor AppleHealthIngest {

    /// Merker in der Datenbank. Steht er, war der vollstaendige Erstlauf da.
    static let fullImportFlag = "apple_health_full_import"
    static let fullImportValue = "v1"
    /// Bis wohin zuletzt gelesen wurde – Grundlage des Nachlaufs.
    static let lastSyncFlag = "apple_health_last_sync"

    private let healthStore = HKHealthStore()

    // MARK: - Erstlauf

    /// Holt den gesamten Bestand: jeden Tageswert ab der ersten Aufzeichnung,
    /// jede Nacht, jedes Training.
    ///
    /// Tageswerte statt jeder Einzelmessung: Ein Jahr Pulsmessungen sind
    /// Hunderttausende Zeilen, und fuer Verlaeufe zaehlt der Tag. Einzelne
    /// Messungen kommen ueber den laufenden Abgleich fuer den jeweils
    /// betrachteten Zeitraum dazu.
    func runFullImport(store: HealthPitStore,
                       progress: @Sendable @MainActor (IngestProgress) -> Void = { _ in }) async throws -> AppleHealthIngestReport {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.healthDataUnavailable }

        var report = AppleHealthIngestReport()
        let pipeline = ImportPipeline(store: store)
        let now = Date()

        await progress(IngestProgress(step: L10n.string("Zeitraum wird ermittelt …"), fraction: nil))
        let quantities = AppleHealthMapping.all.filter { $0.identifier.hasPrefix("HKQuantityTypeIdentifier") }
        let earliest = try await earliestSampleDate(for: quantities) ?? Calendar.healthApp.date(byAdding: .year, value: -5, to: now) ?? now
        report.earliest = earliest

        // 1) Tageswerte je Metrik.
        for (index, entry) in quantities.enumerated() {
            await progress(IngestProgress(
                step: L10n.format("Lese %@ …", entry.metricID.rawValue),
                fraction: Double(index) / Double(max(quantities.count + 2, 1))
            ))
            let incoming = try await dailyValues(for: entry, from: earliest, to: now)
            guard !incoming.isEmpty else { continue }
            _ = try await pipeline.import(incoming, from: .appleHealth)
            report.dailyValues += incoming.count
        }

        // 2) Naechte.
        await progress(IngestProgress(step: L10n.string("Lese Schlaf …"),
                                      fraction: Double(quantities.count) / Double(quantities.count + 2)))
        let sleep = try await sleepObservations(from: earliest, to: now)
        if !sleep.observations.isEmpty {
            _ = try await pipeline.import(sleep.observations, from: .appleHealth)
        }
        report.nights = sleep.nights
        report.sleepSegments = sleep.segments

        // 3) Zyklus.
        let cycle = try await cycleObservations(from: earliest, to: now)
        if !cycle.isEmpty {
            _ = try await pipeline.import(cycle, from: .appleHealth)
        }
        report.cycleDays = cycle.count

        // 4) Trainings.
        await progress(IngestProgress(step: L10n.string("Lese Trainings …"),
                                      fraction: Double(quantities.count + 1) / Double(quantities.count + 2)))
        report.workouts = try await importWorkouts(from: earliest, to: now, pipeline: pipeline)

        try await store.setMigrationFlag(Self.fullImportFlag, value: Self.fullImportValue)
        try await store.setMigrationFlag(Self.lastSyncFlag, value: String(now.timeIntervalSince1970))
        await progress(IngestProgress(step: L10n.string("Fertig"), fraction: 1))
        return report
    }

    // MARK: - Nachlauf

    /// Holt nach, was seit dem letzten Lauf dazugekommen ist.
    ///
    /// Der letzte Tag wird bewusst noch einmal gelesen: Er war beim letzten
    /// Lauf noch nicht zu Ende, sein Wert ist also veraltet. Die Pipeline
    /// erkennt denselben Zeitraum wieder und aktualisiert ihn, statt eine
    /// zweite Zeile anzulegen.
    func runIncremental(store: HealthPitStore) async throws -> AppleHealthIngestReport {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.healthDataUnavailable }

        let now = Date()
        let last = await Self.lastSync(store: store) ?? Calendar.healthApp.date(byAdding: .day, value: -7, to: now) ?? now
        let from = Calendar.healthApp.startOfDay(for: last)

        var report = AppleHealthIngestReport()
        let pipeline = ImportPipeline(store: store)

        for entry in AppleHealthMapping.all where entry.identifier.hasPrefix("HKQuantityTypeIdentifier") {
            let incoming = try await dailyValues(for: entry, from: from, to: now)
            guard !incoming.isEmpty else { continue }
            _ = try await pipeline.import(incoming, from: .appleHealth)
            report.dailyValues += incoming.count
        }

        let sleep = try await sleepObservations(from: from, to: now)
        if !sleep.observations.isEmpty {
            _ = try await pipeline.import(sleep.observations, from: .appleHealth)
        }
        report.nights = sleep.nights
        report.sleepSegments = sleep.segments

        let cycle = try await cycleObservations(from: from, to: now)
        if !cycle.isEmpty {
            _ = try await pipeline.import(cycle, from: .appleHealth)
        }
        report.cycleDays = cycle.count
        report.workouts = try await importWorkouts(from: from, to: now, pipeline: pipeline)

        try await store.setMigrationFlag(Self.lastSyncFlag, value: String(now.timeIntervalSince1970))
        return report
    }

    static func lastSync(store: HealthPitStore) async -> Date? {
        guard let raw = try? await store.migrationFlag(lastSyncFlag),
              let seconds = TimeInterval(raw ?? "") else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func needsFullImport(store: HealthPitStore) async -> Bool {
        let flag = try? await store.migrationFlag(fullImportFlag)
        return (flag ?? nil) != fullImportValue
    }

    // MARK: - Tageswerte

    /// Ein Wert je Tag und Metrik, in der Einheit, die das Mapping nennt.
    private func dailyValues(for entry: AppleHealthMetricMapping,
                             from start: Date,
                             to end: Date) async throws -> [IncomingObservation] {
        guard end > start,
              let type = quantityType(for: entry) else { return [] }

        let calendar = Calendar.healthApp
        let anchor = calendar.startOfDay(for: start)
        let unit = HKUnit(from: entry.healthKitUnit)
        let options: HKStatisticsOptions = entry.aggregation == .sum ? .cumulativeSum : .discreteAverage
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let store = healthStore

        let statistics: [(date: Date, value: Double)] = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type,
                                                    quantitySamplePredicate: predicate,
                                                    options: options,
                                                    anchorDate: anchor,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var result: [(Date, Double)] = []
                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    let quantity = options == .cumulativeSum ? stats.sumQuantity() : stats.averageQuantity()
                    if let quantity, quantity.is(compatibleWith: unit) {
                        result.append((stats.startDate, quantity.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }

        return statistics.map { point in
            IncomingObservation(sourceMetric: entry.identifier,
                                metricID: entry.metricID,
                                value: point.value,
                                unit: entry.sourceUnit,
                                startTime: point.date,
                                endTime: calendar.date(byAdding: .day, value: 1, to: point.date) ?? point.date,
                                aggregation: entry.aggregation == .sum ? .sum : .average,
                                periodType: .day,
                                originProvider: .appleHealth,
                                sourceAppID: nil,
                                metadata: ["source": "apple_health"])
        }
    }

    private func quantityType(for entry: AppleHealthMetricMapping) -> HKQuantityType? {
        let identifier = HKQuantityTypeIdentifier(rawValue: entry.identifier)
        return HKQuantityType.quantityType(forIdentifier: identifier)
    }

    /// Ab wann Apple Health ueberhaupt Daten hat.
    ///
    /// Je Typ die aelteste Probe – der kleinste dieser Zeitpunkte ist der
    /// Anfang. Ohne das wuerde man entweder zu wenig holen oder Jahre leerer
    /// Tage durchrechnen.
    private func earliestSampleDate(for entries: [AppleHealthMetricMapping]) async throws -> Date? {
        var earliest: Date?
        for entry in entries {
            guard let type = quantityType(for: entry) else { continue }
            if let date = try? await oldestSampleDate(of: type) {
                earliest = min(earliest ?? date, date)
            }
        }
        return earliest
    }

    private func oldestSampleDate(of type: HKSampleType) async throws -> Date? {
        let store = healthStore
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: samples?.first?.startDate)
            }
            store.execute(query)
        }
    }
}
