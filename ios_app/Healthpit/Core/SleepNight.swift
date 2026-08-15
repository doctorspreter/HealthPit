//
//  SleepNight.swift
//  HealthPitCore
//
//  Aus einzelnen Schlafproben werden Naechte.
//
//  Das steht hier im Kern und nicht bei HealthKit, weil genau an dieser Stelle
//  der Schlaf der Vorgaengerfassung falsch wurde – und weil sich hier
//  nachrechnen laesst, ob eine Nacht stimmt, ohne Geraet und ohne Apple
//  Health. Die Regeln:
//
//  1. Eine Nacht ist eine Folge von Proben ohne Luecke groesser als drei
//     Stunden. Wachphasen unterbrechen sie nicht – wer nachts aufsteht,
//     schlaeft danach weiter.
//  2. Getrennt wird nach Quelle. Uhr und Telefon zeichnen dieselbe Nacht auf;
//     das sind zwei Aufzeichnungen, keine gemeinsame. Wirft man sie zusammen,
//     stammt die Bettzeit von der einen und die Phasen von der anderen, und
//     die Rechnung ergibt eine Nacht, die es nie gab.
//  3. Zugeordnet wird nach dem Ende: Eine Nacht gehoert zu dem Tag, an dem man
//     aufwacht.
//

import Foundation

/// Eine Schlafprobe, wie sie eine Quelle geliefert hat – ohne HealthKit.
struct SleepSampleInput: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable {
        case inBed = "IN_BED"
        case deep = "DEEP"
        case core = "CORE"
        case rem = "REM"
        case awake = "AWAKE"

        /// Zaehlt diese Probe als Schlaf?
        var isAsleep: Bool {
            switch self {
            case .deep, .core, .rem: return true
            case .inBed, .awake: return false
            }
        }
    }

    let kind: Kind
    let start: Date
    let end: Date
    let provider: ProviderCode
    let sourceAppID: String

    init(kind: Kind, start: Date, end: Date, provider: ProviderCode, sourceAppID: String) {
        self.kind = kind
        self.start = start
        self.end = end
        self.provider = provider
        self.sourceAppID = sourceAppID
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Eine Nacht, wie eine einzelne Quelle sie aufgezeichnet hat.
struct SleepNight: Sendable, Equatable {
    let provider: ProviderCode
    let sourceAppID: String
    let start: Date
    let end: Date
    let samples: [SleepSampleInput]

    var segments: [SleepSampleInput] { samples.filter { $0.kind != .inBed } }

    func duration(of kind: SleepSampleInput.Kind) -> TimeInterval {
        samples.filter { $0.kind == kind }.reduce(0) { $0 + $1.duration }
    }

    /// Schlaf = alle Phasen ausser Wach und Zeit im Bett.
    var asleep: TimeInterval {
        samples.filter { $0.kind.isAsleep }.reduce(0) { $0 + $1.duration }
    }

    var awake: TimeInterval { duration(of: .awake) }

    /// Zeit im Bett. Meldet die Quelle sie nicht, gilt die Spanne der Nacht.
    var timeInBed: TimeInterval {
        max(duration(of: .inBed), end.timeIntervalSince(start))
    }

    var efficiency: Double {
        timeInBed > 0 ? asleep / timeInBed : 0
    }

    /// Eine eindeutige Kennung der Aufzeichnung: Quelle plus Beginn. Damit
    /// findet dieselbe Nacht beim naechsten Lesen zu sich selbst zurueck.
    var sessionID: String {
        "\(sourceAppID)|\(Int(start.timeIntervalSince1970))"
    }
}

enum SleepNightBuilder {

    /// Ab dieser Luecke faengt eine neue Nacht an.
    static let gap: TimeInterval = 3 * 3600

    /// Wie weit vor dem gefragten Zeitraum zusaetzlich gelesen werden muss.
    ///
    /// Eine Nacht faengt vor Mitternacht an. Fragt man nur den Kalendertag ab,
    /// faellt jede Phase heraus, die vollstaendig davor liegt – aus sieben
    /// Stunden werden die zwei nach Mitternacht.
    static let lookBack: TimeInterval = 18 * 3600

    /// Formt Proben zu Naechten, je Quelle getrennt.
    static func nights(from samples: [SleepSampleInput]) -> [SleepNight] {
        guard !samples.isEmpty else { return [] }

        var bySource: [String: [SleepSampleInput]] = [:]
        for sample in samples {
            bySource[sample.sourceAppID, default: []].append(sample)
        }

        var nights: [SleepNight] = []
        for (sourceAppID, sourceSamples) in bySource {
            let sorted = sourceSamples.sorted { $0.start < $1.start }
            var group: [SleepSampleInput] = []
            var lastEnd: Date?

            func flush() {
                guard let first = group.first else { return }
                nights.append(SleepNight(provider: first.provider,
                                         sourceAppID: sourceAppID,
                                         start: group.map(\.start).min() ?? first.start,
                                         end: group.map(\.end).max() ?? first.end,
                                         samples: group))
                group.removeAll()
            }

            for sample in sorted {
                if let lastEnd, sample.start.timeIntervalSince(lastEnd) > gap {
                    flush()
                }
                group.append(sample)
                lastEnd = max(lastEnd ?? sample.end, sample.end)
            }
            flush()
        }
        return nights.sorted { $0.end > $1.end }
    }

    /// Die Naechte, die im gefragten Zeitraum enden.
    ///
    /// Gelesen wird mit Vorlauf; was davor aufgehoert hat, war nicht gefragt.
    static func nights(from samples: [SleepSampleInput],
                              endingIn interval: DateInterval) -> [SleepNight] {
        nights(from: samples).filter { $0.end >= interval.start && $0.end <= interval.end }
    }
}
