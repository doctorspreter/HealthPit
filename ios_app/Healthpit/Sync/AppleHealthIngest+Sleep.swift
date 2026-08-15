//
//  AppleHealthIngest+Sleep.swift
//  Healthpit
//
//  Naechte aus Apple Health.
//
//  Hier steht nur die Uebersetzung: HealthKit-Proben werden zu
//  `SleepSampleInput`. Wie daraus Naechte werden, entscheidet
//  `SleepNightBuilder` im Kern – dort ist es ohne Geraet nachrechenbar, und
//  genau dort lag der Fehler der Vorgaengerfassung.
//

import Foundation
import HealthKit

extension AppleHealthIngest {

    struct SleepHarvest: Sendable {
        var observations: [IncomingObservation] = []
        var nights = 0
        var segments = 0
    }

    func sleepObservations(from start: Date, to end: Date) async throws -> SleepHarvest {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return SleepHarvest()
        }
        // Mit Vorlauf lesen, sonst fehlt der Teil der Nacht vor Mitternacht.
        let samples = try await categorySamples(of: type,
                                                from: start.addingTimeInterval(-SleepNightBuilder.lookBack),
                                                to: end)
        let inputs = samples.compactMap(Self.input)
        let interval = DateInterval(start: start, end: max(end, start))

        var harvest = SleepHarvest()
        for night in SleepNightBuilder.nights(from: inputs, endingIn: interval) {
            harvest.nights += 1
            harvest.segments += night.segments.count
            harvest.observations.append(contentsOf: Self.observations(for: night))
        }
        return harvest
    }

    /// Eine HealthKit-Probe als quellenneutrale Schlafprobe.
    ///
    /// Alles, was HealthKit sonst noch unter Schlaf fuehrt, faellt hier
    /// heraus – lieber eine Probe weniger als eine falsch einsortierte.
    static func input(_ sample: HKCategorySample) -> SleepSampleInput? {
        let kind: SleepSampleInput.Kind
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed:                          kind = .inBed
        case .asleepDeep:                     kind = .deep
        case .asleepREM:                      kind = .rem
        case .asleepCore, .asleepUnspecified: kind = .core
        case .awake:                          kind = .awake
        default:                              return nil
        }

        let bundleID = sample.sourceRevision.source.bundleIdentifier
        let provider = ProviderRegistry.provider(forBundleID: bundleID,
                                                 sourceName: sample.sourceRevision.source.name,
                                                 ownBundleID: Bundle.main.bundleIdentifier)
        return SleepSampleInput(kind: kind,
                                start: sample.startDate,
                                end: sample.endDate,
                                provider: provider ?? .appleHealth,
                                sourceAppID: bundleID)
    }

    /// Was von einer Nacht in die Datenbank geht.
    static func observations(for night: SleepNight) -> [IncomingObservation] {
        func summary(_ metricID: MetricID,
                     _ seconds: TimeInterval,
                     _ sourceMetric: String,
                     unit: UnitCode = .second,
                     aggregation: Aggregation = .sum) -> IncomingObservation? {
            guard seconds > 0 else { return nil }
            return IncomingObservation(sourceMetric: sourceMetric,
                                       metricID: metricID,
                                       value: seconds,
                                       unit: unit,
                                       startTime: night.start,
                                       endTime: night.end,
                                       aggregation: aggregation,
                                       periodType: .night,
                                       originProvider: night.provider,
                                       sourceAppID: night.sourceAppID,
                                       sessionID: night.sessionID,
                                       metadata: ["source": "apple_health"])
        }

        var result = [
            summary("SLP_DURATION", night.asleep, "sleep_session.asleep"),
            summary("SLP_TIME_IN_BED", night.timeInBed, "sleep_session.in_bed"),
            summary("SLP_DEEP_DURATION", night.duration(of: .deep), "sleep_session.deep"),
            summary("SLP_CORE_DURATION", night.duration(of: .core), "sleep_session.core"),
            summary("SLP_REM_DURATION", night.duration(of: .rem), "sleep_session.rem"),
            summary("SLP_AWAKE_DURATION", night.awake, "sleep_session.awake")
        ].compactMap { $0 }

        if night.efficiency > 0 {
            result.append(contentsOf: [
                summary("SLP_EFFICIENCY", night.efficiency * 100, "sleep_session.efficiency",
                        unit: .percent, aggregation: .average)
            ].compactMap { $0 })
        }

        // Jede Phase einzeln – daraus zeichnet die Detailansicht das
        // Hypnogramm. Ohne sie waere nur die Summe da.
        for segment in night.segments {
            result.append(IncomingObservation(sourceMetric: "HKCategoryTypeIdentifierSleepAnalysis",
                                              metricID: "SLP_STAGE",
                                              valueCode: segment.kind.rawValue,
                                              startTime: segment.start,
                                              endTime: segment.end,
                                              aggregation: .raw,
                                              periodType: .interval,
                                              originProvider: night.provider,
                                              sourceAppID: night.sourceAppID,
                                              sessionID: night.sessionID,
                                              metadata: ["source": "apple_health"]))
        }
        return result
    }

    func categorySamples(of type: HKCategoryType,
                         from start: Date,
                         to end: Date) async throws -> [HKCategorySample] {
        let store = HKHealthStore()
        // Bewusst ohne Quellenfilter: Gespeichert wird alles, mit seiner
        // Herkunft. Welche Quelle angezeigt wird, entscheidet die Anzeige –
        // ein Filter beim Lesen wirft Daten weg, die niemand je wiedersieht.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }
}
