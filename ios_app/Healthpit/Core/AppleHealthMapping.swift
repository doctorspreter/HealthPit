//
//  AppleHealthMapping.swift
//  HealthPitCore
//
//  Das Alt-zu-Neu-Mapping fuer Apple Health – und damit zugleich fuer die
//  bisherigen HealthPit-Werte: Bis heute ist die Kennung eines Werts in
//  HealthPit der HealthKit-Identifier (`HKQuantityTypeIdentifierStepCount`).
//  Genau der steht hier links.
//
//  Bewusst ohne `import HealthKit`: Die Tabelle ist reiner Text und laesst
//  sich damit auf dem Mac testen. Der Adapter in der App baut daraus die
//  HKUnit-Objekte.
//

import Foundation

/// Eine Zeile des Apple-Health-Mappings.
struct AppleHealthMetricMapping: Hashable, Sendable {
    /// `HKQuantityTypeIdentifier…` bzw. `HKCategoryTypeIdentifier…`.
    let identifier: String
    let metricID: MetricID
    /// Einheitenstring, mit dem die App aus HealthKit liest (`HKUnit(from:)`).
    let healthKitUnit: String
    /// Derselbe Wert als HealthPit-Einheitencode.
    let sourceUnit: UnitCode
    /// Skalenkorrektur. HealthKit liefert Prozent als Anteil (0,97) –
    /// HealthPit speichert 97.
    let rule: ConversionRule
    /// Wie die App den Wert bisher zusammenfasst.
    let aggregation: Aggregation
    let periodType: PeriodType
    /// Darf HealthPit diesen Typ nach Apple Health zurueckschreiben?
    let canWrite: Bool

    init(_ identifier: String,
         _ metricID: MetricID,
         healthKitUnit: String,
         sourceUnit: UnitCode,
         rule: ConversionRule = .identity,
         aggregation: Aggregation = .raw,
         periodType: PeriodType = .instant,
         canWrite: Bool = false) {
        self.identifier = identifier
        self.metricID = metricID
        self.healthKitUnit = healthKitUnit
        self.sourceUnit = sourceUnit
        self.rule = rule
        self.aggregation = aggregation
        self.periodType = periodType
        self.canWrite = canWrite
    }
}

enum AppleHealthMapping {

    /// Kurzschreibweise fuer die Tabelle unten.
    private static func quantity(_ name: String) -> String {
        "HKQuantityTypeIdentifier" + name
    }

    private static let percentRule = ConversionRule(factor: 100)

    /// Alle Zuordnungen. Links steht exakt das, was heute in der App als
    /// Metrik-ID, als Cache-Schluessel und in den Einstellungen steht.
    static let all: [AppleHealthMetricMapping] = [
        // Aktivitaet – Summen ueber den Tag
        .init(quantity("StepCount"), "ACT_STEPS", healthKitUnit: "count", sourceUnit: .count,
              aggregation: .sum, periodType: .day),
        .init(quantity("DistanceWalkingRunning"), "ACT_DISTANCE_WALK_RUN", healthKitUnit: "km",
              sourceUnit: .kilometer, aggregation: .sum, periodType: .day, canWrite: true),
        .init(quantity("DistanceCycling"), "ACT_DISTANCE_CYCLING", healthKitUnit: "km",
              sourceUnit: .kilometer, aggregation: .sum, periodType: .day, canWrite: true),
        .init(quantity("DistanceSwimming"), "ACT_DISTANCE_SWIMMING", healthKitUnit: "m",
              sourceUnit: .meter, aggregation: .sum, periodType: .day),
        .init(quantity("SwimmingStrokeCount"), "ACT_SWIM_STROKES", healthKitUnit: "count",
              sourceUnit: .count, aggregation: .sum, periodType: .day),
        .init(quantity("DistanceWheelchair"), "ACT_DISTANCE_WHEELCHAIR", healthKitUnit: "km",
              sourceUnit: .kilometer, aggregation: .sum, periodType: .day),
        .init(quantity("PushCount"), "ACT_WHEELCHAIR_PUSHES", healthKitUnit: "count",
              sourceUnit: .count, aggregation: .sum, periodType: .day),
        .init(quantity("DistanceDownhillSnowSports"), "ACT_DISTANCE_SNOW_SPORTS", healthKitUnit: "km",
              sourceUnit: .kilometer, aggregation: .sum, periodType: .day),
        .init(quantity("FlightsClimbed"), "ACT_FLIGHTS_CLIMBED", healthKitUnit: "count",
              sourceUnit: .count, aggregation: .sum, periodType: .day),
        .init(quantity("ActiveEnergyBurned"), "NRG_ACTIVE", healthKitUnit: "kcal",
              sourceUnit: .kilocalorie, aggregation: .sum, periodType: .day, canWrite: true),
        .init(quantity("BasalEnergyBurned"), "NRG_BASAL", healthKitUnit: "kcal",
              sourceUnit: .kilocalorie, aggregation: .sum, periodType: .day),
        .init(quantity("AppleExerciseTime"), "ACT_EXERCISE_TIME", healthKitUnit: "min",
              sourceUnit: .minute, aggregation: .sum, periodType: .day),
        .init(quantity("AppleStandTime"), "ACT_STAND_TIME", healthKitUnit: "min",
              sourceUnit: .minute, aggregation: .sum, periodType: .day),
        .init(quantity("AppleMoveTime"), "ACT_MOVE_TIME", healthKitUnit: "min",
              sourceUnit: .minute, aggregation: .sum, periodType: .day),

        // Aktivitaet – Momentaufnahmen
        .init(quantity("WalkingSpeed"), "ACT_WALKING_SPEED", healthKitUnit: "km/hr",
              sourceUnit: .kilometersPerHour, aggregation: .average),
        .init(quantity("WalkingStepLength"), "ACT_WALKING_STEP_LENGTH", healthKitUnit: "cm",
              sourceUnit: .centimeter, aggregation: .average),
        .init(quantity("WalkingAsymmetryPercentage"), "ACT_WALKING_ASYMMETRY", healthKitUnit: "%",
              sourceUnit: .percent, rule: percentRule, aggregation: .average),
        .init(quantity("WalkingDoubleSupportPercentage"), "ACT_WALKING_DOUBLE_SUPPORT", healthKitUnit: "%",
              sourceUnit: .percent, rule: percentRule, aggregation: .average),
        .init(quantity("AppleWalkingSteadiness"), "ACT_WALKING_STEADINESS", healthKitUnit: "%",
              sourceUnit: .percent, rule: percentRule, aggregation: .average),
        .init(quantity("SixMinuteWalkTestDistance"), "ACT_SIX_MINUTE_WALK_DISTANCE", healthKitUnit: "m",
              sourceUnit: .meter, aggregation: .average),
        .init(quantity("StairAscentSpeed"), "ACT_STAIR_ASCENT_SPEED", healthKitUnit: "m/s",
              sourceUnit: .metersPerSecond, aggregation: .average),
        .init(quantity("StairDescentSpeed"), "ACT_STAIR_DESCENT_SPEED", healthKitUnit: "m/s",
              sourceUnit: .metersPerSecond, aggregation: .average),
        .init(quantity("RunningSpeed"), "ACT_RUNNING_SPEED", healthKitUnit: "km/hr",
              sourceUnit: .kilometersPerHour, aggregation: .average),
        .init(quantity("RunningPower"), "ACT_RUNNING_POWER", healthKitUnit: "W",
              sourceUnit: .watt, aggregation: .average),
        .init(quantity("RunningStrideLength"), "ACT_RUNNING_STRIDE_LENGTH", healthKitUnit: "m",
              sourceUnit: .meter, aggregation: .average),
        .init(quantity("RunningVerticalOscillation"), "ACT_RUNNING_VERTICAL_OSCILLATION", healthKitUnit: "cm",
              sourceUnit: .centimeter, aggregation: .average),
        .init(quantity("RunningGroundContactTime"), "ACT_RUNNING_GROUND_CONTACT_TIME", healthKitUnit: "ms",
              sourceUnit: .millisecond, aggregation: .average),
        .init(quantity("CyclingSpeed"), "ACT_CYCLING_SPEED", healthKitUnit: "km/hr",
              sourceUnit: .kilometersPerHour, aggregation: .average),
        .init(quantity("CyclingPower"), "ACT_CYCLING_POWER", healthKitUnit: "W",
              sourceUnit: .watt, aggregation: .average),
        .init(quantity("CyclingCadence"), "ACT_CYCLING_CADENCE", healthKitUnit: "count/min",
              sourceUnit: .revolutionsPerMinute, aggregation: .average),
        .init(quantity("CyclingFunctionalThresholdPower"), "ACT_CYCLING_FTP", healthKitUnit: "W",
              sourceUnit: .watt, aggregation: .average),

        // Herz
        .init(quantity("HeartRate"), "HRT_RATE", healthKitUnit: "count/min",
              sourceUnit: .beatsPerMinute, aggregation: .average),
        .init(quantity("RestingHeartRate"), "HRT_RESTING_RATE", healthKitUnit: "count/min",
              sourceUnit: .beatsPerMinute, aggregation: .average),
        .init(quantity("WalkingHeartRateAverage"), "HRT_WALKING_AVERAGE", healthKitUnit: "count/min",
              sourceUnit: .beatsPerMinute, aggregation: .average),
        .init(quantity("HeartRateRecoveryOneMinute"), "HRT_RECOVERY_ONE_MINUTE", healthKitUnit: "count/min",
              sourceUnit: .beatsPerMinute, aggregation: .average),
        .init(quantity("HeartRateVariabilitySDNN"), "HRT_HRV_SDNN", healthKitUnit: "ms",
              sourceUnit: .millisecond, aggregation: .average),
        .init(quantity("VO2Max"), "HRT_VO2_MAX", healthKitUnit: "ml/kg*min",
              sourceUnit: .milliliterPerKilogramMinute, aggregation: .average),
        .init(quantity("BloodPressureSystolic"), "HRT_BLOOD_PRESSURE_SYSTOLIC", healthKitUnit: "mmHg",
              sourceUnit: .millimeterOfMercury, aggregation: .average),
        .init(quantity("BloodPressureDiastolic"), "HRT_BLOOD_PRESSURE_DIASTOLIC", healthKitUnit: "mmHg",
              sourceUnit: .millimeterOfMercury, aggregation: .average),
        .init(quantity("PeripheralPerfusionIndex"), "HRT_PERFUSION_INDEX", healthKitUnit: "%",
              sourceUnit: .percent, rule: percentRule, aggregation: .average),
        .init(quantity("AtrialFibrillationBurden"), "HRT_AFIB_BURDEN", healthKitUnit: "%",
              sourceUnit: .percent, rule: percentRule, aggregation: .average),

        // Koerper
        .init(quantity("BodyMass"), "BDY_WEIGHT", healthKitUnit: "kg",
              sourceUnit: .kilogram, aggregation: .average),
        .init(quantity("BodyMassIndex"), "BDY_BMI", healthKitUnit: "count",
              sourceUnit: .none, aggregation: .average),
        .init(quantity("BodyFatPercentage"), "BDY_FAT", healthKitUnit: "%",
              sourceUnit: .percent, rule: percentRule, aggregation: .average),
        .init(quantity("LeanBodyMass"), "BDY_LEAN_MASS", healthKitUnit: "kg",
              sourceUnit: .kilogram, aggregation: .average),
        .init(quantity("Height"), "BDY_HEIGHT", healthKitUnit: "cm",
              sourceUnit: .centimeter, aggregation: .average),
        .init(quantity("WaistCircumference"), "BDY_WAIST_CIRCUMFERENCE", healthKitUnit: "cm",
              sourceUnit: .centimeter, aggregation: .average),

        // Ernaehrung – Tagessummen
        .init(quantity("DietaryEnergyConsumed"), "NUT_ENERGY", healthKitUnit: "kcal",
              sourceUnit: .kilocalorie, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryWater"), "NUT_WATER", healthKitUnit: "ml",
              sourceUnit: .milliliter, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryCarbohydrates"), "NUT_CARBOHYDRATES", healthKitUnit: "g",
              sourceUnit: .gram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryProtein"), "NUT_PROTEIN", healthKitUnit: "g",
              sourceUnit: .gram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryFatTotal"), "NUT_FAT_TOTAL", healthKitUnit: "g",
              sourceUnit: .gram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryFatSaturated"), "NUT_FAT_SATURATED", healthKitUnit: "g",
              sourceUnit: .gram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryFatMonounsaturated"), "NUT_FAT_MONOUNSATURATED", healthKitUnit: "g",
              sourceUnit: .gram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryFatPolyunsaturated"), "NUT_FAT_POLYUNSATURATED", healthKitUnit: "g",
              sourceUnit: .gram, aggregation: .sum, periodType: .day),
        .init(quantity("DietarySugar"), "NUT_SUGAR", healthKitUnit: "g",
              sourceUnit: .gram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryFiber"), "NUT_FIBER", healthKitUnit: "g",
              sourceUnit: .gram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryCholesterol"), "NUT_CHOLESTEROL", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietarySodium"), "NUT_SODIUM", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryPotassium"), "NUT_POTASSIUM", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryCalcium"), "NUT_CALCIUM", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryIron"), "NUT_IRON", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryMagnesium"), "NUT_MAGNESIUM", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryZinc"), "NUT_ZINC", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryCaffeine"), "NUT_CAFFEINE", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryVitaminC"), "NUT_VITAMIN_C", healthKitUnit: "mg",
              sourceUnit: .milligram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryVitaminD"), "NUT_VITAMIN_D", healthKitUnit: "mcg",
              sourceUnit: .microgram, aggregation: .sum, periodType: .day),
        .init(quantity("DietaryVitaminB12"), "NUT_VITAMIN_B12", healthKitUnit: "mcg",
              sourceUnit: .microgram, aggregation: .sum, periodType: .day),

        // Atmung, Temperatur, Vitalwerte, Umgebung
        .init(quantity("RespiratoryRate"), "RSP_RATE", healthKitUnit: "count/min",
              sourceUnit: .breathsPerMinute, aggregation: .average),
        .init(quantity("OxygenSaturation"), "RSP_SPO2", healthKitUnit: "%",
              sourceUnit: .percent, rule: percentRule, aggregation: .average),
        .init(quantity("ForcedExpiratoryVolume1"), "RSP_FEV1", healthKitUnit: "L",
              sourceUnit: .liter, aggregation: .average),
        .init(quantity("ForcedVitalCapacity"), "RSP_FVC", healthKitUnit: "L",
              sourceUnit: .liter, aggregation: .average),
        .init(quantity("PeakExpiratoryFlowRate"), "RSP_PEAK_FLOW", healthKitUnit: "L/min",
              sourceUnit: .litersPerMinute, aggregation: .average),
        .init(quantity("InhalerUsage"), "RSP_INHALER_USAGE", healthKitUnit: "count",
              sourceUnit: .count, aggregation: .sum, periodType: .day),
        .init(quantity("BodyTemperature"), "TMP_BODY", healthKitUnit: "degC",
              sourceUnit: .celsius, aggregation: .average),
        .init(quantity("BasalBodyTemperature"), "TMP_BASAL_BODY", healthKitUnit: "degC",
              sourceUnit: .celsius, aggregation: .average),
        .init(quantity("AppleSleepingWristTemperature"), "TMP_SLEEPING_WRIST", healthKitUnit: "degC",
              sourceUnit: .celsius, aggregation: .average),
        .init(quantity("BloodGlucose"), "VTL_BLOOD_GLUCOSE", healthKitUnit: "mg/dL",
              sourceUnit: .milligramPerDeciliter, aggregation: .average),
        .init(quantity("InsulinDelivery"), "VTL_INSULIN_DELIVERY", healthKitUnit: "IU",
              sourceUnit: .internationalUnit, aggregation: .sum, periodType: .day),
        .init(quantity("NumberOfTimesFallen"), "VTL_FALLS", healthKitUnit: "count",
              sourceUnit: .count, aggregation: .sum, periodType: .day),
        .init(quantity("EnvironmentalAudioExposure"), "ENV_AUDIO_EXPOSURE", healthKitUnit: "dBASPL",
              sourceUnit: .decibel, aggregation: .average),
        .init(quantity("HeadphoneAudioExposure"), "ENV_HEADPHONE_AUDIO_EXPOSURE", healthKitUnit: "dBASPL",
              sourceUnit: .decibel, aggregation: .average),
        .init(quantity("UVExposure"), "ENV_UV_INDEX", healthKitUnit: "count",
              sourceUnit: .index, aggregation: .average),

        // Schlaf: eine Kategorie, kein Mengentyp. Die einzelnen Phasen kommen
        // ueber `valueMapping` (siehe unten).
        .init("HKCategoryTypeIdentifierSleepAnalysis", "SLP_STAGE", healthKitUnit: "",
              sourceUnit: .none, aggregation: .raw, periodType: .interval),
        .init("HKCategoryTypeIdentifierMenstrualFlow", "CYC_MENSTRUAL_FLOW", healthKitUnit: "",
              sourceUnit: .none, aggregation: .raw, periodType: .day, canWrite: true)
    ]

    static let byIdentifier: [String: AppleHealthMetricMapping] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.identifier, $0) })

    static let byMetricID: [MetricID: AppleHealthMetricMapping] =
        Dictionary(all.map { ($0.metricID, $0) }, uniquingKeysWith: { first, _ in first })

    /// Der bisherige HealthPit-Metrikschluessel ist der HealthKit-Identifier.
    /// Diese Funktion ist damit zugleich das Alt-zu-Neu-Mapping.
    static func metricID(forLegacyIdentifier identifier: String) -> MetricID? {
        byIdentifier[identifier]?.metricID
    }

    /// HealthKit-Werte fuer die Schlafphasen (`HKCategoryValueSleepAnalysis`).
    static let sleepStageValueMapping: [String: String] = [
        "0": "IN_BED",
        "1": "ASLEEP_UNSPECIFIED",
        "2": "AWAKE",
        "3": "CORE",
        "4": "DEEP",
        "5": "REM"
    ]

    /// HealthKit-Werte fuer den Zyklusfluss (`HKCategoryValueMenstrualFlow`).
    static let menstrualFlowValueMapping: [String: String] = [
        "1": "UNSPECIFIED",
        "2": "LIGHT",
        "3": "MEDIUM",
        "4": "HEAVY",
        "5": "NONE"
    ]

    /// Die Zeilen, die beim Start in `provider_metric_mapping` landen.
    static func providerMappings() -> [ProviderMetricMapping] {
        all.map { entry in
            let valueMapping: [String: String]
            switch entry.identifier {
            case "HKCategoryTypeIdentifierSleepAnalysis": valueMapping = sleepStageValueMapping
            case "HKCategoryTypeIdentifierMenstrualFlow": valueMapping = menstrualFlowValueMapping
            default: valueMapping = [:]
            }
            return ProviderMetricMapping(provider: .appleHealth,
                                         sourceMetric: entry.identifier,
                                         metricID: entry.metricID,
                                         sourceUnit: entry.sourceUnit,
                                         canonicalUnit: MetricRegistry().canonicalUnit(for: entry.metricID),
                                         conversionRule: entry.rule,
                                         valueMapping: valueMapping,
                                         canRead: true,
                                         canWrite: entry.canWrite,
                                         canUpdate: entry.canWrite,
                                         canDelete: entry.canWrite)
        }
    }
}
