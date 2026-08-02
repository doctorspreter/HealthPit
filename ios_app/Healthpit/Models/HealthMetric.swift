//
//  HealthMetric.swift
//  Healthpit
//
//  Das zentrale Datenmodell-"Backbone" der App (PLAN.md Abschnitt 4.1):
//  Jede ablesbare Mengen-Metrik wird hier EINMAL deklarativ beschrieben –
//  mit HealthKit-Identifier, Anzeigename, Icon, Farbe, Einheit und
//  Aggregationsart. Dashboard, Detailansicht und Charts arbeiten generisch
//  gegen dieses Modell, statt jeden Typ einzeln auszuprogrammieren.
//
//  Hinweis: Hier sind nur HKQuantityType-basierte Metriken modelliert.
//  Schlaf (HKCategoryType), Workouts (HKWorkoutType) und Blutdruck
//  (HKCorrelationType) erhalten in späteren Schritten eigene Modelle.
//

import Foundation
import HealthKit

/// Wie ein Datentyp über einen Zeitraum zusammengefasst wird.
///
/// Entscheidend für korrekte Diagramme: kumulierbare Werte (Schritte, kcal)
/// werden summiert, Momentaufnahmen (Puls, Gewicht) gemittelt.
enum AggregationStyle: Sendable {
    /// Werte über das Intervall aufaddieren (z. B. Schritte/Tag).
    case cumulativeSum
    /// Werte über das Intervall mitteln (z. B. Ruhepuls/Tag).
    case discreteAverage

    /// Passende Optionen für `HKStatisticsCollectionQuery`.
    var statisticsOptions: HKStatisticsOptions {
        switch self {
        case .cumulativeSum:   return .cumulativeSum
        case .discreteAverage: return .discreteAverage
        }
    }
}

/// Deklarative Beschreibung einer einzelnen, lesbaren Mengen-Metrik.
struct HealthMetric: Identifiable, Hashable, Sendable {

    /// Stabile ID = HealthKit-Identifier (z. B. "HKQuantityTypeIdentifierStepCount").
    nonisolated var id: String { quantityTypeIdentifier.rawValue }

    /// Kategorie für Gruppierung im Dashboard.
    let category: HealthCategory

    /// Deutscher Lokalisierungsschlüssel und aktuell übersetzter Anzeigename.
    private let titleKey: String
    var title: String { L10n.string(titleKey) }

    /// SF-Symbol für Listen/Detail.
    let systemImage: String

    /// Der zugrunde liegende HealthKit-Mengentyp.
    let quantityTypeIdentifier: HKQuantityTypeIdentifier

    /// Einheit, in der gespeicherte Werte gelesen werden.
    let unit: HKUnit

    /// Kurzes Einheitenkürzel für die Anzeige (z. B. "kcal", "bpm", "kg").
    private let unitSymbolKey: String
    var unitSymbol: String { L10n.string(unitSymbolKey) }

    /// Summieren oder Mitteln über den Zeitraum.
    let aggregation: AggregationStyle

    nonisolated init(category: HealthCategory,
                     title: String,
                     systemImage: String,
                     quantityTypeIdentifier: HKQuantityTypeIdentifier,
                     unit: HKUnit,
                     unitSymbol: String,
                     aggregation: AggregationStyle) {
        self.category = category
        self.titleKey = title
        self.systemImage = systemImage
        self.quantityTypeIdentifier = quantityTypeIdentifier
        self.unit = unit
        self.unitSymbolKey = unitSymbol
        self.aggregation = aggregation
    }

    /// Bequemer Zugriff auf den HealthKit-Typ für Queries.
    nonisolated var quantityType: HKQuantityType {
        HKQuantityType(quantityTypeIdentifier)
    }

    // Gleichheit/Hashing nur über die ID – HKUnit ist sonst umständlich zu hashen.
    nonisolated static func == (lhs: HealthMetric, rhs: HealthMetric) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Registry: alle Metriken aus PLAN.md Abschnitt 2

extension HealthMetric {

    /// Alle modellierten Mengen-Metriken (über alle Kategorien hinweg).
    nonisolated static let all: [HealthMetric] =
        activity + heart + body + nutrition + vitals

    /// Metriken einer Kategorie (für Kategorie-Detailansicht).
    nonisolated static func metrics(for category: HealthCategory) -> [HealthMetric] {
        all.filter { $0.category == category }
    }

    /// Metrik per HealthKit-Identifier nachschlagen.
    nonisolated static func metric(id: String) -> HealthMetric? {
        all.first { $0.id == id }
    }

    /// Metrik per HealthKit-Identifier nachschlagen (typsicher).
    nonisolated static func metric(_ identifier: HKQuantityTypeIdentifier) -> HealthMetric? {
        metric(id: identifier.rawValue)
    }

    /// Häufig gebrauchte Einzel-Metrik (z. B. für Dashboard/Schnelltests).
    nonisolated static var stepCount: HealthMetric? { metric(.stepCount) }

    /// Bis zu 4 Kennzahlen, die auf der Dashboard-Kachel einer Kategorie
    /// erscheinen (1x1 nutzt die erste, 2x2 die ersten zwei, 4x2 alle mit Daten).
    nonisolated static func headline(for category: HealthCategory) -> [HealthMetric] {
        let ids: [HKQuantityTypeIdentifier]
        switch category {
        case .activity:  ids = [.stepCount, .distanceWalkingRunning, .flightsClimbed, .activeEnergyBurned]
        case .heart:     ids = [.restingHeartRate, .heartRate, .heartRateVariabilitySDNN, .vo2Max]
        case .body:      ids = [.bodyMass, .bodyMassIndex, .bodyFatPercentage, .leanBodyMass]
        case .nutrition: ids = [.dietaryEnergyConsumed, .dietaryWater, .dietaryCarbohydrates, .dietaryProtein]
        case .vitals:    ids = [.oxygenSaturation, .respiratoryRate, .bodyTemperature, .bloodGlucose]
        case .workouts, .sleep: ids = []
        }
        return ids.compactMap { metric($0) }
    }

    // Bequeme Einheiten-Kürzel
    private nonisolated static let bpm = HKUnit.count().unitDivided(by: .minute())
    private nonisolated static let kmh = HKUnit(from: "km/hr")
    private nonisolated static let mps = HKUnit.meter().unitDivided(by: .second())

    // MARK: Aktivität & Mobilität (PLAN 2.1)

    nonisolated static let activity: [HealthMetric] = [
        HealthMetric(category: .activity, title: "Schritte", systemImage: "shoeprints.fill",
                     quantityTypeIdentifier: .stepCount, unit: .count(), unitSymbol: "Schritte",
                     aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Gehen + Laufen", systemImage: "figure.walk",
                     quantityTypeIdentifier: .distanceWalkingRunning,
                     unit: .meterUnit(with: .kilo), unitSymbol: "km", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Radfahren", systemImage: "bicycle",
                     quantityTypeIdentifier: .distanceCycling,
                     unit: .meterUnit(with: .kilo), unitSymbol: "km", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Schwimmen", systemImage: "figure.pool.swim",
                     quantityTypeIdentifier: .distanceSwimming,
                     unit: .meter(), unitSymbol: "m", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Schwimmzüge", systemImage: "figure.pool.swim",
                     quantityTypeIdentifier: .swimmingStrokeCount, unit: .count(), unitSymbol: "Züge",
                     aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Rollstuhl-Distanz", systemImage: "figure.roll",
                     quantityTypeIdentifier: .distanceWheelchair,
                     unit: .meterUnit(with: .kilo), unitSymbol: "km", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Rollstuhl-Stöße", systemImage: "figure.roll",
                     quantityTypeIdentifier: .pushCount, unit: .count(), unitSymbol: "Stöße",
                     aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Ski/Snowboard", systemImage: "figure.skiing.downhill",
                     quantityTypeIdentifier: .distanceDownhillSnowSports,
                     unit: .meterUnit(with: .kilo), unitSymbol: "km", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Treppen", systemImage: "figure.stairs",
                     quantityTypeIdentifier: .flightsClimbed, unit: .count(), unitSymbol: "Etagen",
                     aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Aktive Kalorien", systemImage: "flame.fill",
                     quantityTypeIdentifier: .activeEnergyBurned,
                     unit: .kilocalorie(), unitSymbol: "kcal", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Ruheumsatz", systemImage: "flame",
                     quantityTypeIdentifier: .basalEnergyBurned,
                     unit: .kilocalorie(), unitSymbol: "kcal", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Trainingsminuten", systemImage: "figure.run",
                     quantityTypeIdentifier: .appleExerciseTime,
                     unit: .minute(), unitSymbol: "min", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Stehminuten", systemImage: "figure.stand",
                     quantityTypeIdentifier: .appleStandTime,
                     unit: .minute(), unitSymbol: "min", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Move-Minuten", systemImage: "figure.walk.motion",
                     quantityTypeIdentifier: .appleMoveTime,
                     unit: .minute(), unitSymbol: "min", aggregation: .cumulativeSum),
        HealthMetric(category: .activity, title: "Gehtempo", systemImage: "speedometer",
                     quantityTypeIdentifier: .walkingSpeed, unit: kmh, unitSymbol: "km/h",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Schrittlänge", systemImage: "ruler",
                     quantityTypeIdentifier: .walkingStepLength,
                     unit: .meterUnit(with: .centi), unitSymbol: "cm", aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Geh-Asymmetrie", systemImage: "figure.walk",
                     quantityTypeIdentifier: .walkingAsymmetryPercentage,
                     unit: .percent(), unitSymbol: "%", aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Doppelstand-Zeit", systemImage: "figure.walk",
                     quantityTypeIdentifier: .walkingDoubleSupportPercentage,
                     unit: .percent(), unitSymbol: "%", aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Gehstabilität", systemImage: "figure.walk.circle",
                     quantityTypeIdentifier: .appleWalkingSteadiness,
                     unit: .percent(), unitSymbol: "%", aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "6-Min-Gehtest", systemImage: "figure.walk",
                     quantityTypeIdentifier: .sixMinuteWalkTestDistance,
                     unit: .meter(), unitSymbol: "m", aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Treppe hoch (Tempo)", systemImage: "figure.stairs",
                     quantityTypeIdentifier: .stairAscentSpeed, unit: mps, unitSymbol: "m/s",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Treppe runter (Tempo)", systemImage: "figure.stairs",
                     quantityTypeIdentifier: .stairDescentSpeed, unit: mps, unitSymbol: "m/s",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Lauftempo", systemImage: "figure.run",
                     quantityTypeIdentifier: .runningSpeed, unit: kmh, unitSymbol: "km/h",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Laufleistung", systemImage: "bolt.fill",
                     quantityTypeIdentifier: .runningPower, unit: .watt(), unitSymbol: "W",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Schrittlänge (Lauf)", systemImage: "ruler",
                     quantityTypeIdentifier: .runningStrideLength, unit: .meter(), unitSymbol: "m",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Vertikale Bewegung", systemImage: "arrow.up.and.down",
                     quantityTypeIdentifier: .runningVerticalOscillation,
                     unit: .meterUnit(with: .centi), unitSymbol: "cm", aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Bodenkontaktzeit", systemImage: "timer",
                     quantityTypeIdentifier: .runningGroundContactTime,
                     unit: .secondUnit(with: .milli), unitSymbol: "ms", aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Radtempo", systemImage: "bicycle",
                     quantityTypeIdentifier: .cyclingSpeed, unit: kmh, unitSymbol: "km/h",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Radleistung", systemImage: "bolt.fill",
                     quantityTypeIdentifier: .cyclingPower, unit: .watt(), unitSymbol: "W",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "Trittfrequenz", systemImage: "arrow.triangle.2.circlepath",
                     quantityTypeIdentifier: .cyclingCadence, unit: bpm, unitSymbol: "U/min",
                     aggregation: .discreteAverage),
        HealthMetric(category: .activity, title: "FTP (Rad)", systemImage: "bolt.fill",
                     quantityTypeIdentifier: .cyclingFunctionalThresholdPower,
                     unit: .watt(), unitSymbol: "W", aggregation: .discreteAverage),
    ]

    // MARK: Herz (PLAN 2.3) – Quantity-Typen (Blutdruck via Komponenten)

    nonisolated static let heart: [HealthMetric] = [
        HealthMetric(category: .heart, title: "Herzfrequenz", systemImage: "heart.fill",
                     quantityTypeIdentifier: .heartRate, unit: bpm, unitSymbol: "bpm",
                     aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "Ruhepuls", systemImage: "heart",
                     quantityTypeIdentifier: .restingHeartRate, unit: bpm, unitSymbol: "bpm",
                     aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "Geh-Puls Ø", systemImage: "heart.text.square",
                     quantityTypeIdentifier: .walkingHeartRateAverage, unit: bpm, unitSymbol: "bpm",
                     aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "Erholungspuls (1 Min)", systemImage: "heart.circle",
                     quantityTypeIdentifier: .heartRateRecoveryOneMinute, unit: bpm, unitSymbol: "bpm",
                     aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "HRV (SDNN)", systemImage: "waveform.path.ecg",
                     quantityTypeIdentifier: .heartRateVariabilitySDNN,
                     unit: .secondUnit(with: .milli), unitSymbol: "ms", aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "VO₂max", systemImage: "lungs",
                     quantityTypeIdentifier: .vo2Max,
                     unit: HKUnit(from: "ml/kg*min"), unitSymbol: "ml/kg·min",
                     aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "Blutdruck systolisch", systemImage: "waveform.path.ecg.rectangle",
                     quantityTypeIdentifier: .bloodPressureSystolic,
                     unit: .millimeterOfMercury(), unitSymbol: "mmHg", aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "Blutdruck diastolisch", systemImage: "waveform.path.ecg.rectangle",
                     quantityTypeIdentifier: .bloodPressureDiastolic,
                     unit: .millimeterOfMercury(), unitSymbol: "mmHg", aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "Perfusionsindex", systemImage: "drop.fill",
                     quantityTypeIdentifier: .peripheralPerfusionIndex,
                     unit: .percent(), unitSymbol: "%", aggregation: .discreteAverage),
        HealthMetric(category: .heart, title: "AFib-Verlauf", systemImage: "waveform.path.ecg",
                     quantityTypeIdentifier: .atrialFibrillationBurden,
                     unit: .percent(), unitSymbol: "%", aggregation: .discreteAverage),
    ]

    // MARK: Körper (PLAN 2.5)

    nonisolated static let body: [HealthMetric] = [
        HealthMetric(category: .body, title: "Gewicht", systemImage: "scalemass.fill",
                     quantityTypeIdentifier: .bodyMass,
                     unit: .gramUnit(with: .kilo), unitSymbol: "kg", aggregation: .discreteAverage),
        HealthMetric(category: .body, title: "BMI", systemImage: "figure",
                     quantityTypeIdentifier: .bodyMassIndex, unit: .count(), unitSymbol: "",
                     aggregation: .discreteAverage),
        HealthMetric(category: .body, title: "Körperfett", systemImage: "drop.triangle",
                     quantityTypeIdentifier: .bodyFatPercentage,
                     unit: .percent(), unitSymbol: "%", aggregation: .discreteAverage),
        HealthMetric(category: .body, title: "Magermasse", systemImage: "figure.arms.open",
                     quantityTypeIdentifier: .leanBodyMass,
                     unit: .gramUnit(with: .kilo), unitSymbol: "kg", aggregation: .discreteAverage),
        HealthMetric(category: .body, title: "Größe", systemImage: "ruler",
                     quantityTypeIdentifier: .height,
                     unit: .meterUnit(with: .centi), unitSymbol: "cm", aggregation: .discreteAverage),
        HealthMetric(category: .body, title: "Taillenumfang", systemImage: "ruler",
                     quantityTypeIdentifier: .waistCircumference,
                     unit: .meterUnit(with: .centi), unitSymbol: "cm", aggregation: .discreteAverage),
    ]

    // MARK: Ernährung (PLAN 2.6) – Makros, Wasser, Mikronährstoffe

    nonisolated static let nutrition: [HealthMetric] = [
        HealthMetric(category: .nutrition, title: "Energie", systemImage: "fork.knife",
                     quantityTypeIdentifier: .dietaryEnergyConsumed,
                     unit: .kilocalorie(), unitSymbol: "kcal", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Wasser", systemImage: "drop.fill",
                     quantityTypeIdentifier: .dietaryWater,
                     unit: .literUnit(with: .milli), unitSymbol: "ml", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Kohlenhydrate", systemImage: "carrot",
                     quantityTypeIdentifier: .dietaryCarbohydrates,
                     unit: .gram(), unitSymbol: "g", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Eiweiß", systemImage: "fish",
                     quantityTypeIdentifier: .dietaryProtein,
                     unit: .gram(), unitSymbol: "g", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Fett gesamt", systemImage: "drop",
                     quantityTypeIdentifier: .dietaryFatTotal,
                     unit: .gram(), unitSymbol: "g", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Gesättigte Fette", systemImage: "drop",
                     quantityTypeIdentifier: .dietaryFatSaturated,
                     unit: .gram(), unitSymbol: "g", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Einfach unges. Fette", systemImage: "drop",
                     quantityTypeIdentifier: .dietaryFatMonounsaturated,
                     unit: .gram(), unitSymbol: "g", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Mehrfach unges. Fette", systemImage: "drop",
                     quantityTypeIdentifier: .dietaryFatPolyunsaturated,
                     unit: .gram(), unitSymbol: "g", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Zucker", systemImage: "cube",
                     quantityTypeIdentifier: .dietarySugar,
                     unit: .gram(), unitSymbol: "g", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Ballaststoffe", systemImage: "leaf",
                     quantityTypeIdentifier: .dietaryFiber,
                     unit: .gram(), unitSymbol: "g", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Cholesterin", systemImage: "drop",
                     quantityTypeIdentifier: .dietaryCholesterol,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Natrium", systemImage: "cube",
                     quantityTypeIdentifier: .dietarySodium,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Kalium", systemImage: "cube",
                     quantityTypeIdentifier: .dietaryPotassium,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Kalzium", systemImage: "cube",
                     quantityTypeIdentifier: .dietaryCalcium,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Eisen", systemImage: "cube",
                     quantityTypeIdentifier: .dietaryIron,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Magnesium", systemImage: "cube",
                     quantityTypeIdentifier: .dietaryMagnesium,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Zink", systemImage: "cube",
                     quantityTypeIdentifier: .dietaryZinc,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Koffein", systemImage: "cup.and.saucer.fill",
                     quantityTypeIdentifier: .dietaryCaffeine,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Vitamin C", systemImage: "pills",
                     quantityTypeIdentifier: .dietaryVitaminC,
                     unit: .gramUnit(with: .milli), unitSymbol: "mg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Vitamin D", systemImage: "pills",
                     quantityTypeIdentifier: .dietaryVitaminD,
                     unit: .gramUnit(with: .micro), unitSymbol: "µg", aggregation: .cumulativeSum),
        HealthMetric(category: .nutrition, title: "Vitamin B12", systemImage: "pills",
                     quantityTypeIdentifier: .dietaryVitaminB12,
                     unit: .gramUnit(with: .micro), unitSymbol: "µg", aggregation: .cumulativeSum),
    ]

    // MARK: Vitalwerte, Atmung, Hörgesundheit (PLAN 2.7)

    nonisolated static let vitals: [HealthMetric] = [
        HealthMetric(category: .vitals, title: "Atemfrequenz", systemImage: "lungs.fill",
                     quantityTypeIdentifier: .respiratoryRate, unit: bpm, unitSymbol: "Atemzüge/min",
                     aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Sauerstoff (SpO₂)", systemImage: "drop.degreesign",
                     quantityTypeIdentifier: .oxygenSaturation,
                     unit: .percent(), unitSymbol: "%", aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Körpertemperatur", systemImage: "thermometer",
                     quantityTypeIdentifier: .bodyTemperature,
                     unit: .degreeCelsius(), unitSymbol: "°C", aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Basaltemperatur", systemImage: "thermometer.low",
                     quantityTypeIdentifier: .basalBodyTemperature,
                     unit: .degreeCelsius(), unitSymbol: "°C", aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Handgelenk-Temp (Schlaf)", systemImage: "thermometer",
                     quantityTypeIdentifier: .appleSleepingWristTemperature,
                     unit: .degreeCelsius(), unitSymbol: "°C", aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Blutzucker", systemImage: "drop.fill",
                     quantityTypeIdentifier: .bloodGlucose,
                     unit: HKUnit(from: "mg/dL"), unitSymbol: "mg/dL", aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "FEV1", systemImage: "lungs",
                     quantityTypeIdentifier: .forcedExpiratoryVolume1,
                     unit: .liter(), unitSymbol: "L", aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Vitalkapazität (FVC)", systemImage: "lungs",
                     quantityTypeIdentifier: .forcedVitalCapacity,
                     unit: .liter(), unitSymbol: "L", aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Peak Flow", systemImage: "wind",
                     quantityTypeIdentifier: .peakExpiratoryFlowRate,
                     unit: HKUnit(from: "L/min"), unitSymbol: "L/min", aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Inhalator-Nutzung", systemImage: "inhaler",
                     quantityTypeIdentifier: .inhalerUsage, unit: .count(), unitSymbol: "×",
                     aggregation: .cumulativeSum),
        HealthMetric(category: .vitals, title: "Stürze", systemImage: "figure.fall",
                     quantityTypeIdentifier: .numberOfTimesFallen, unit: .count(), unitSymbol: "×",
                     aggregation: .cumulativeSum),
        HealthMetric(category: .vitals, title: "Umgebungslautstärke", systemImage: "speaker.wave.3",
                     quantityTypeIdentifier: .environmentalAudioExposure,
                     unit: .decibelAWeightedSoundPressureLevel(), unitSymbol: "dB",
                     aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Kopfhörer-Lautstärke", systemImage: "headphones",
                     quantityTypeIdentifier: .headphoneAudioExposure,
                     unit: .decibelAWeightedSoundPressureLevel(), unitSymbol: "dB",
                     aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "UV-Belastung", systemImage: "sun.max",
                     quantityTypeIdentifier: .uvExposure, unit: .count(), unitSymbol: "Index",
                     aggregation: .discreteAverage),
        HealthMetric(category: .vitals, title: "Insulin", systemImage: "syringe",
                     quantityTypeIdentifier: .insulinDelivery,
                     unit: .internationalUnit(), unitSymbol: "IE", aggregation: .cumulativeSum),
    ]
}
