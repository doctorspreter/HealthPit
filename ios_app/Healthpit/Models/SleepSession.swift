//
//  SleepSession.swift
//  Healthpit
//
//  Eine zusammenhängende Schlafphase (eine "Nacht"), aggregiert aus den
//  HKCategoryValueSleepAnalysis-Samples (PLAN 2.4). Enthält die einzelnen
//  Phasen-Segmente (für ein Hypnogramm) sowie berechnete Dauern je Phase.
//

import Foundation

/// Schlafphase (asleepUnspecified wird auf Core abgebildet).
enum SleepStage: String, CaseIterable, Identifiable, Codable, Sendable {
    case deep, core, rem, awake
    var id: String { rawValue }
    var title: String {
        switch self {
        case .deep:  return L10n.string("Tief")
        case .core:  return L10n.string("Core")
        case .rem:   return L10n.string("REM")
        case .awake: return L10n.string("Wach")
        }
    }
}

/// Ein einzelnes Phasen-Segment über die Zeit (für das Hypnogramm).
struct SleepSegment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let stage: SleepStage
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }

    init(id: UUID = UUID(), stage: SleepStage, start: Date, end: Date) {
        self.id = id
        self.stage = stage
        self.start = start
        self.end = end
    }
}

struct SleepSession: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let inBed: TimeInterval
    let segments: [SleepSegment]

    init(id: UUID = UUID(), start: Date, end: Date, inBed: TimeInterval, segments: [SleepSegment]) {
        self.id = id
        self.start = start
        self.end = end
        self.inBed = inBed
        self.segments = segments
    }

    func duration(of stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    var deep: TimeInterval  { duration(of: .deep) }
    var core: TimeInterval  { duration(of: .core) }
    var rem: TimeInterval   { duration(of: .rem) }
    var awake: TimeInterval { duration(of: .awake) }

    /// Gesamter Schlaf (alle Phasen außer Wach).
    var asleep: TimeInterval { deep + core + rem }

    /// Zeit im Bett (Fallback: Spanne der Nacht).
    var timeInBed: TimeInterval { max(inBed, end.timeIntervalSince(start)) }

    /// Schlafeffizienz = Schlaf / Zeit im Bett.
    var efficiency: Double { timeInBed > 0 ? asleep / timeInBed : 0 }
}

extension TimeInterval {
    /// Kompakte Stunden/Minuten-Darstellung, z. B. "7 Std 23 Min".
    var hoursMinutes: String {
        let totalMinutes = Int((self / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0
            ? L10n.format("%lld Std %lld Min", h, m)
            : L10n.format("%lld Min", m)
    }
}
