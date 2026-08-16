//
//  AppleHealthIngest+Cycle.swift
//  Healthpit
//
//  Die Blutungstage aus Apple Health.
//
//  Der Zyklus war der letzte Bestand, den die Datenbank gar nicht kannte: Die
//  Ansicht und die Bruecke lasen ihn jedes Mal frisch aus HealthKit. Damit galt
//  fuer ihn nichts von dem, was fuer alles andere gilt — keine Quellenregeln,
//  keine Herkunft, keine Wiedererkennung.
//
//  Abgelegt wird der Tag so, wie HealthKit ihn fuehrt: eine Probe je Tag mit
//  der Staerke als Code. Alles Weitere — Zykluslaenge, Zyklustag, Mittelwerte —
//  ist eine Rechnung darueber und wird nicht gespeichert.
//

import Foundation
import HealthKit

extension AppleHealthIngest {

    /// Blutungstage und Zyklus-Ereignisse als Beobachtungen.
    func cycleObservations(from start: Date, to end: Date) async throws -> [IncomingObservation] {
        var out: [IncomingObservation] = []
        if let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) {
            out += try await categorySamples(of: type, from: start, to: end).map(Self.observation)
        }
        // Ovulationstest, Zervixschleim, Zwischenblutung, sexuelle Aktivitaet.
        // Alle unter einer Metrik, die Art als Code — sonst braeuchte jede
        // Kleinigkeit ihren eigenen Katalogeintrag.
        for kind in CycleEventKind.allCases {
            guard let type = HKCategoryType.categoryType(forIdentifier: kind.categoryIdentifier) else { continue }
            out += try await categorySamples(of: type, from: start, to: end)
                .map { Self.eventObservation($0, kind: kind) }
        }
        return out
    }

    /// Ein Zyklus-Ereignis als Beobachtung.
    static func eventObservation(_ sample: HKCategorySample,
                                 kind: CycleEventKind) -> IncomingObservation {
        let bundleID = sample.sourceRevision.source.bundleIdentifier
        let provider = ProviderRegistry.provider(forBundleID: bundleID,
                                                 sourceName: sample.sourceRevision.source.name,
                                                 ownBundleID: Bundle.main.bundleIdentifier)
        return IncomingObservation(sourceMetric: "HKCategoryTypeIdentifier" + kind.rawValue,
                                   metricID: "CYC_EVENT",
                                   valueCode: Self.eventCode(kind),
                                   startTime: sample.startDate,
                                   endTime: sample.endDate,
                                   aggregation: .raw,
                                   periodType: .instant,
                                   originProvider: provider ?? .appleHealth,
                                   originExternalID: sample.uuid.uuidString,
                                   sourceAppID: bundleID,
                                   metadata: [
                                    "source": "apple_health",
                                    "event_kind": kind.rawValue,
                                    "raw_value": String(sample.value)
                                   ])
    }

    /// Die Art des Ereignisses als Code des Katalogs.
    static func eventCode(_ kind: CycleEventKind) -> String {
        switch kind {
        case .intermenstrualBleeding: return "INTERMENSTRUAL_BLEEDING"
        case .ovulationTest:          return "OVULATION_TEST"
        case .cervicalMucus:          return "CERVICAL_MUCUS"
        case .sexualActivity:         return "SEXUAL_ACTIVITY"
        }
    }

    /// Eine HealthKit-Probe als Beobachtung.
    ///
    /// Die Kennung der Probe reist als Fremdkennung mit. Sie ist noetig, um
    /// denselben Tag in Apple Health wieder zu treffen: Ein Eintrag laesst sich
    /// dort nur ersetzen, wenn man weiss, welche Probe gemeint war.
    static func observation(_ sample: HKCategorySample) -> IncomingObservation {
        let bundleID = sample.sourceRevision.source.bundleIdentifier
        let provider = ProviderRegistry.provider(forBundleID: bundleID,
                                                 sourceName: sample.sourceRevision.source.name,
                                                 ownBundleID: Bundle.main.bundleIdentifier)
        let isCycleStart = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) ?? false
        let day = Calendar.healthApp.startOfDay(for: sample.startDate)

        return IncomingObservation(sourceMetric: "HKCategoryTypeIdentifierMenstrualFlow",
                                   metricID: "CYC_MENSTRUAL_FLOW",
                                   valueCode: String(sample.value),
                                   startTime: day,
                                   endTime: sample.endDate,
                                   aggregation: .raw,
                                   periodType: .day,
                                   originProvider: provider ?? .appleHealth,
                                   originExternalID: sample.uuid.uuidString,
                                   sourceAppID: bundleID,
                                   metadata: [
                                    "source": "apple_health",
                                    "cycle_start": isCycleStart ? "1" : "0"
                                   ])
    }
}
