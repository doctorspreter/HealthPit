//
//  BodyMetricStatus.swift
//  Healthpit
//
//  Grobe Ampel-Einordnung für Gesundheitswerte. Die Bereiche dienen nur der
//  schnellen Orientierung und ersetzen keine medizinische Bewertung.
//
//  Die Grenzen stehen in der kanonischen Einheit der Datenbank – also der
//  Einheit, in der die Werte hier ankommen. Prozente sind Prozente: 95 heisst
//  95 %, nicht 0,95.
//

import HealthKit
import SwiftUI

enum BodyMetricStatus: CaseIterable {
    case good
    case caution
    case bad
    case neutral

    var color: Color {
        switch self {
        case .good: return .green
        case .caution: return .yellow
        case .bad: return .red
        case .neutral: return .blue
        }
    }

    var title: String {
        switch self {
        case .good: return L10n.string("Gut")
        case .caution: return L10n.string("Auffällig")
        case .bad: return L10n.string("Kritisch")
        case .neutral: return L10n.string("Neutral")
        }
    }

    static func evaluate(metric: HealthMetric, value: Double?) -> BodyMetricStatus {
        guard let value else { return .neutral }
        return guide(for: metric)?.status(for: value) ?? .neutral
    }

    static func guide(for metric: HealthMetric) -> MetricStatusGuide? {
        switch metric.quantityTypeIdentifier {
        case .heartRate:
            return .target(lowCritical: 45, lowCaution: 50, highCaution: 100, highCritical: 120)
        case .restingHeartRate:
            return .target(lowCritical: 40, lowCaution: 45, highCaution: 75, highCritical: 90)
        case .walkingHeartRateAverage:
            return .target(lowCritical: 45, lowCaution: 50, highCaution: 110, highCritical: 125)
        case .heartRateRecoveryOneMinute:
            return .higherIsBetter(caution: 12, good: 20)
        case .heartRateVariabilitySDNN:
            return .higherIsBetter(caution: 30, good: 50)
        case .vo2Max:
            return .higherIsBetter(caution: 32, good: 42)
        case .bloodPressureSystolic:
            return .target(lowCritical: 90, lowCaution: 100, highCaution: 120, highCritical: 140)
        case .bloodPressureDiastolic:
            return .target(lowCritical: 60, lowCaution: 65, highCaution: 80, highCritical: 90)
        case .peripheralPerfusionIndex:
            return .higherIsBetter(caution: 0.5, good: 1)
        case .atrialFibrillationBurden:
            return .lowerIsBetter(good: 2, caution: 10)

        case .bodyMassIndex:
            return .target(lowCritical: 17, lowCaution: 18.5, highCaution: 24.9, highCritical: 29.9)
        case .bodyFatPercentage:
            return .target(lowCritical: 6, lowCaution: 10, highCaution: 25, highCritical: 32)
        case .waistCircumference:
            return .lowerIsBetter(good: 94, caution: 102)

        case .stepCount:
            return .higherIsBetter(caution: 4_000, good: 8_000)
        case .activeEnergyBurned:
            return .higherIsBetter(caution: 250, good: 500)
        case .appleExerciseTime:
            return .higherIsBetter(caution: 10, good: 30)
        case .appleStandTime, .appleMoveTime:
            return .higherIsBetter(caution: 30, good: 60)
        case .flightsClimbed:
            return .higherIsBetter(caution: 5, good: 10)
        case .distanceWalkingRunning:
            return .higherIsBetter(caution: 2, good: 5)
        case .distanceCycling:
            return .higherIsBetter(caution: 5, good: 15)
        case .walkingSpeed:
            return .target(lowCritical: 2.5, lowCaution: 3.5, highCaution: 7.0, highCritical: 9.0)
        case .walkingStepLength:
            return .higherIsBetter(caution: 50, good: 65)
        case .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage:
            return .lowerIsBetter(good: 20, caution: 35)
        case .appleWalkingSteadiness:
            return .higherIsBetter(caution: 50, good: 75)
        case .sixMinuteWalkTestDistance:
            return .higherIsBetter(caution: 350, good: 500)
        case .runningGroundContactTime:
            return .lowerIsBetter(good: 260, caution: 320)
        case .runningVerticalOscillation:
            return .lowerIsBetter(good: 9, caution: 12)

        case .dietaryWater:
            return .higherIsBetter(caution: 1_500, good: 2_000)
        case .dietaryEnergyConsumed:
            return .target(lowCritical: 1_200, lowCaution: 1_600, highCaution: 2_600, highCritical: 3_200)
        case .dietaryProtein:
            return .higherIsBetter(caution: 50, good: 80)
        case .dietaryFiber:
            return .higherIsBetter(caution: 20, good: 30)
        case .dietarySugar:
            return .lowerIsBetter(good: 50, caution: 90)
        case .dietarySodium:
            return .lowerIsBetter(good: 2_300, caution: 3_500)
        case .dietaryCaffeine:
            return .lowerIsBetter(good: 200, caution: 400)
        case .dietaryCholesterol:
            return .lowerIsBetter(good: 300, caution: 500)
        case .dietaryCarbohydrates:
            return .target(lowCritical: 80, lowCaution: 130, highCaution: 300, highCritical: 400)
        case .dietaryFatTotal:
            return .target(lowCritical: 35, lowCaution: 45, highCaution: 90, highCritical: 120)
        case .dietaryFatSaturated:
            return .lowerIsBetter(good: 20, caution: 35)
        case .dietaryPotassium:
            return .higherIsBetter(caution: 2_000, good: 3_500)
        case .dietaryCalcium:
            return .higherIsBetter(caution: 700, good: 1_000)
        case .dietaryIron:
            return .higherIsBetter(caution: 8, good: 12)
        case .dietaryMagnesium:
            return .higherIsBetter(caution: 250, good: 350)
        case .dietaryZinc:
            return .higherIsBetter(caution: 7, good: 10)
        case .dietaryVitaminC:
            return .higherIsBetter(caution: 60, good: 90)
        case .dietaryVitaminD:
            return .higherIsBetter(caution: 10, good: 20)
        case .dietaryVitaminB12:
            return .higherIsBetter(caution: 2, good: 3)

        case .oxygenSaturation:
            return .higherIsBetter(caution: 92, good: 95)
        case .respiratoryRate:
            return .target(lowCritical: 10, lowCaution: 12, highCaution: 20, highCritical: 24)
        case .bodyTemperature, .basalBodyTemperature:
            return .target(lowCritical: 35.8, lowCaution: 36.1, highCaution: 37.2, highCritical: 38.0)
        case .bloodGlucose:
            return .target(lowCritical: 70, lowCaution: 80, highCaution: 140, highCritical: 180)
        case .inhalerUsage, .numberOfTimesFallen:
            return .lowerIsBetter(good: 0, caution: 1)
        case .environmentalAudioExposure, .headphoneAudioExposure:
            return .lowerIsBetter(good: 70, caution: 85)
        case .uvExposure:
            return .lowerIsBetter(good: 2, caution: 6)

        default:
            return nil
        }
    }
}

struct MetricStatusGuide {
    let bands: [MetricStatusBand]
    let greenStart: Double?
    let greenEnd: Double?

    func status(for value: Double) -> BodyMetricStatus {
        bands.first { $0.contains(value) }?.status ?? .neutral
    }

    var transitionValues: [Double] {
        let values = bands.flatMap { band in
            [band.lower, band.upper].compactMap { $0 }
        }
        return Array(Set(values)).sorted()
    }

    static func target(lowCritical: Double,
                       lowCaution: Double,
                       highCaution: Double,
                       highCritical: Double) -> MetricStatusGuide {
        MetricStatusGuide(
            bands: [
                MetricStatusBand(upper: lowCritical, status: .bad),
                MetricStatusBand(lower: lowCritical, upper: lowCaution, status: .caution),
                MetricStatusBand(lower: lowCaution, upper: highCaution, status: .good),
                MetricStatusBand(lower: highCaution, upper: highCritical, status: .caution),
                MetricStatusBand(lower: highCritical, status: .bad),
            ],
            greenStart: lowCaution,
            greenEnd: highCaution
        )
    }

    static func higherIsBetter(caution: Double, good: Double) -> MetricStatusGuide {
        MetricStatusGuide(
            bands: [
                MetricStatusBand(upper: caution, status: .bad),
                MetricStatusBand(lower: caution, upper: good, status: .caution),
                MetricStatusBand(lower: good, status: .good),
            ],
            greenStart: good,
            greenEnd: nil
        )
    }

    static func lowerIsBetter(good: Double, caution: Double) -> MetricStatusGuide {
        MetricStatusGuide(
            bands: [
                MetricStatusBand(upper: good, status: .good),
                MetricStatusBand(lower: good, upper: caution, status: .caution),
                MetricStatusBand(lower: caution, status: .bad),
            ],
            greenStart: nil,
            greenEnd: good
        )
    }
}

struct MetricStatusBand: Identifiable {
    let id = UUID()
    var lower: Double?
    var upper: Double?
    let status: BodyMetricStatus

    func contains(_ value: Double) -> Bool {
        if let lower, value < lower { return false }
        if let upper, value > upper { return false }
        return true
    }
}
