//
//  HealthKitManager+Cycle.swift
//  Healthpit
//
//  Zyklusdaten lesen und schreiben.
//
//  Getrennt von HealthKitManager, weil Zyklus als einzige Kategorie beides
//  kann: Apple Health ist Quelle *und* Ziel. Geschrieben werden ausschliesslich
//  Samples, die Healthpit selbst angelegt hat – fremde Eintraege werden
//  angezeigt, aber nie veraendert.
//

import Foundation
import HealthKit

extension HealthKitManager {

    /// Alles fuer die Zyklusansicht, ab `monthsBack` Monaten rueckwaerts.
    func fetchCycleOverview(monthsBack: Int = 12,
                            referenceDate now: Date = .now) async throws -> CycleOverview {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        try await requestAuthorization()

        let calendar = Calendar.healthApp
        let start = calendar.date(byAdding: .month, value: -monthsBack, to: now) ?? now
        let interval = DateInterval(start: start, end: max(now, start))

        var overview = CycleOverview()
        overview.days = try await fetchCycleDays(interval: interval)
        overview.cycles = Self.cycles(from: overview.days)
        overview.events = try await fetchCycleEvents(interval: interval)
        return overview
    }

    /// Blutungstage aus `menstrualFlow`.
    func fetchCycleDays(interval: DateInterval) async throws -> [CycleDayEntry] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) else { return [] }
        let samples = try await categorySamples(of: type,
                                                interval: interval,
                                                dataPointID: HealthDataPointDescriptor.cycleID)
        let ownBundleID = Bundle.main.bundleIdentifier

        // Pro Tag zaehlt genau ein Eintrag. Liegen mehrere vor – etwa weil eine
        // andere App denselben Tag fuehrt – gewinnt der eigene. Sonst waere
        // nach einer Korrektur in Healthpit unklar, welcher Wert erscheint.
        var byDay: [Date: CycleDayEntry] = [:]
        for sample in samples {
            let day = Calendar.healthApp.startOfDay(for: sample.startDate)
            let isStart = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) ?? false
            let entry = CycleDayEntry(id: sample.uuid,
                                      date: day,
                                      flow: MenstrualFlow(rawValue: sample.value) ?? .unspecified,
                                      isCycleStart: isStart,
                                      isOwnEntry: sample.sourceRevision.source.bundleIdentifier == ownBundleID)
            if let existing = byDay[day], existing.isOwnEntry, !entry.isOwnEntry { continue }
            byDay[day] = entry
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// Die uebrigen Ereignisse der Reproduktionsgesundheit.
    func fetchCycleEvents(interval: DateInterval) async throws -> [CycleEvent] {
        var out: [CycleEvent] = []
        for kind in CycleEventKind.allCases {
            guard let type = HKCategoryType.categoryType(forIdentifier: kind.categoryIdentifier) else { continue }
            let samples = try await categorySamples(of: type,
                                                    interval: interval,
                                                    dataPointID: HealthDataPointDescriptor.cycleID)
            out.append(contentsOf: samples.map {
                CycleEvent(id: $0.uuid, kind: kind, date: $0.startDate, rawValue: $0.value)
            })
        }
        return out.sorted { $0.date > $1.date }
    }

    // MARK: - Schreiben

    /// Legt einen Blutungstag an oder ersetzt den vorhandenen.
    ///
    /// `flow == .none` loescht einen eigenen Eintrag, statt eine Null-Blutung
    /// zu speichern – sonst sammeln sich in Apple Health Tage an, an denen
    /// ausdruecklich nichts war.
    func saveCycleDay(date: Date,
                      flow: MenstrualFlow,
                      isCycleStart: Bool) async throws {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        guard let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) else { return }
        try await requestAuthorization()

        let day = Calendar.healthApp.startOfDay(for: date)
        let end = Calendar.healthApp.date(byAdding: .day, value: 1, to: day)?
            .addingTimeInterval(-1) ?? day

        try await deleteOwnCycleSamples(of: type, on: day)
        guard flow != .none else { return }

        // HealthKit verlangt dieses Metadatum bei jedem menstrualFlow-Sample;
        // ohne es schlaegt das Speichern fehl.
        let sample = HKCategorySample(
            type: type,
            value: flow.rawValue,
            start: day,
            end: end,
            metadata: [HKMetadataKeyMenstrualCycleStart: isCycleStart]
        )
        try await healthStore.save(sample)
    }

    /// Legt ein Ereignis an (Zwischenblutung, Ovulationstest).
    func saveCycleEvent(kind: CycleEventKind, date: Date, rawValue: Int) async throws {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        guard HealthKitTypes.writableCycleIdentifiers.contains(kind.categoryIdentifier),
              let type = HKCategoryType.categoryType(forIdentifier: kind.categoryIdentifier) else {
            return
        }
        try await requestAuthorization()

        let day = Calendar.healthApp.startOfDay(for: date)
        let end = Calendar.healthApp.date(byAdding: .day, value: 1, to: day)?
            .addingTimeInterval(-1) ?? day
        let sample = HKCategorySample(type: type, value: rawValue, start: day, end: end)
        try await healthStore.save(sample)
    }

    /// Loescht den eigenen Blutungseintrag eines Tages.
    ///
    /// Nur eigene Samples: was eine andere App geschrieben hat, darf HealthKit
    /// gar nicht entfernen, und es waere auch nicht unsere Entscheidung.
    @discardableResult
    func deleteCycleDay(date: Date) async throws -> Bool {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        guard let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) else {
            return false
        }
        try await requestAuthorization()
        return try await deleteOwnCycleSamples(
            of: type,
            on: Calendar.healthApp.startOfDay(for: date)
        )
    }

    /// Loescht ein einzelnes Ereignis (Zwischenblutung, Ovulationstest).
    @discardableResult
    func deleteCycleEvent(kind: CycleEventKind, date: Date) async throws -> Bool {
        guard isHealthDataAvailable else { throw HealthError.healthDataUnavailable }
        guard let type = HKCategoryType.categoryType(forIdentifier: kind.categoryIdentifier) else {
            return false
        }
        try await requestAuthorization()
        return try await deleteOwnCycleSamples(
            of: type,
            on: Calendar.healthApp.startOfDay(for: date)
        )
    }

    /// Loescht alles, was Healthpit an einem Tag angelegt hat.
    @discardableResult
    func deleteCycleEntries(on date: Date) async throws -> Bool {
        var removed = try await deleteCycleDay(date: date)
        for kind in CycleEventKind.allCases {
            if try await deleteCycleEvent(kind: kind, date: date) {
                removed = true
            }
        }
        return removed
    }

    // MARK: - Hilfen

    @discardableResult
    private func deleteOwnCycleSamples(of type: HKCategoryType, on day: Date) async throws -> Bool {
        let end = Calendar.healthApp.date(byAdding: .day, value: 1, to: day) ?? day
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: day, end: end, options: []),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        let existing = try await samples(of: type, predicate: predicate)
        guard !existing.isEmpty else { return false }
        try await healthStore.delete(existing)
        return true
    }

    private func categorySamples(of type: HKCategoryType,
                                 interval: DateInterval,
                                 dataPointID: String) async throws -> [HKCategorySample] {
        let base = HKQuery.predicateForSamples(withStart: interval.start,
                                               end: interval.end,
                                               options: [])
        let scope = try await configuredScope(basePredicate: base,
                                              sampleType: type,
                                              dataPointID: dataPointID)
        guard case .predicate(let predicate) = scope else { return [] }
        return try await samples(of: type, predicate: predicate).compactMap { $0 as? HKCategorySample }
    }

    private func samples(of type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        let store = healthStore
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
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Zyklen ableiten

    /// Fasst Blutungstage zu Zyklen zusammen.
    ///
    /// Ein neuer Zyklus beginnt, wenn Apple Health den Tag als Zyklusstart
    /// kennzeichnet – oder, wenn kein Kennzeichen gesetzt ist, nach einer Pause
    /// von mehr als zwei Tagen ohne Blutung. Ohne die Pausenregel wuerde eine
    /// aus einer anderen App importierte Periode als ein einziger langer Zyklus
    /// erscheinen; die meisten Apps setzen das Metadatum naemlich nicht.
    static func cycles(from days: [CycleDayEntry]) -> [MenstrualCycle] {
        let bleeding = days.filter(\.flow.isBleeding).sorted { $0.date < $1.date }
        guard !bleeding.isEmpty else { return [] }

        let calendar = Calendar.healthApp
        var groups: [[CycleDayEntry]] = []
        var current: [CycleDayEntry] = []

        for entry in bleeding {
            if let previous = current.last {
                let gap = calendar.dateComponents([.day], from: previous.date, to: entry.date).day ?? 0
                if entry.isCycleStart || gap > 2 {
                    groups.append(current)
                    current = []
                }
            }
            current.append(entry)
        }
        if !current.isEmpty { groups.append(current) }

        return groups.enumerated().map { index, group in
            MenstrualCycle(id: group[0].id,
                           start: group[0].date,
                           periodEnd: group[group.count - 1].date,
                           nextStart: index + 1 < groups.count ? groups[index + 1][0].date : nil,
                           bleedingDays: group.count)
        }
    }
}
