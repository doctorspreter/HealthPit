//
//  MetricCatalog.swift
//  HealthPitCore
//
//  Der eingebaute Katalog: jede Metrik, die HealthPit heute kennt, plus die
//  ersten proprietaeren Anbieterwerte als Beleg, dass sie eben nicht
//  zusammengefuehrt werden.
//
//  Regeln fuer neue Eintraege:
//  * Praefix = Kategorie (bzw. Provider-Code bei proprietaeren Werten)
//  * Nur Englisch, Grossbuchstaben, `_` als Trenner
//  * Kanonische Einheit ist die Basiseinheit der Dimension (M, KG, S, KCAL …),
//    nicht die Anzeigeeinheit. Was die Oberflaeche zeigt, entscheidet die App.
//  * Eine einmal ausgelieferte ID bekommt nie eine neue Bedeutung.
//

import Foundation

enum MetricCatalog {

    static let builtIn: [MetricDefinition] =
        activity + energy + heart + body + nutrition + respiratory
        + temperature + vitals + environment + sleep + cycle + workout + proprietary

    // MARK: - Aktivitaet & Mobilitaet

    static let activity: [MetricDefinition] = [
        MetricDefinition("ACT_STEPS", category: .activity, name: "Steps",
                         description: "Number of steps taken.",
                         canonicalUnit: .count),
        MetricDefinition("ACT_DISTANCE", category: .activity, name: "Distance",
                         description: "Distance covered, sport unspecified.",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_DISTANCE_WALK_RUN", category: .activity, name: "Walking + running distance",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_DISTANCE_CYCLING", category: .activity, name: "Cycling distance",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_DISTANCE_SWIMMING", category: .activity, name: "Swimming distance",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_DISTANCE_WHEELCHAIR", category: .activity, name: "Wheelchair distance",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_DISTANCE_SNOW_SPORTS", category: .activity, name: "Downhill snow sports distance",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_SWIM_STROKES", category: .activity, name: "Swimming strokes",
                         canonicalUnit: .count),
        MetricDefinition("ACT_WHEELCHAIR_PUSHES", category: .activity, name: "Wheelchair pushes",
                         canonicalUnit: .count),
        MetricDefinition("ACT_FLIGHTS_CLIMBED", category: .activity, name: "Flights climbed",
                         canonicalUnit: .count),
        MetricDefinition("ACT_EXERCISE_TIME", category: .activity, name: "Exercise time",
                         canonicalUnit: .second),
        MetricDefinition("ACT_STAND_TIME", category: .activity, name: "Stand time",
                         canonicalUnit: .second),
        MetricDefinition("ACT_MOVE_TIME", category: .activity, name: "Move time",
                         canonicalUnit: .second),
        MetricDefinition("ACT_WALKING_SPEED", category: .activity, name: "Walking speed",
                         canonicalUnit: .metersPerSecond),
        MetricDefinition("ACT_WALKING_STEP_LENGTH", category: .activity, name: "Walking step length",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_WALKING_ASYMMETRY", category: .activity, name: "Walking asymmetry",
                         canonicalUnit: .percent),
        MetricDefinition("ACT_WALKING_DOUBLE_SUPPORT", category: .activity, name: "Double support time",
                         canonicalUnit: .percent),
        MetricDefinition("ACT_WALKING_STEADINESS", category: .activity, name: "Walking steadiness",
                         canonicalUnit: .percent),
        MetricDefinition("ACT_SIX_MINUTE_WALK_DISTANCE", category: .activity, name: "Six-minute walk distance",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_STAIR_ASCENT_SPEED", category: .activity, name: "Stair ascent speed",
                         canonicalUnit: .metersPerSecond),
        MetricDefinition("ACT_STAIR_DESCENT_SPEED", category: .activity, name: "Stair descent speed",
                         canonicalUnit: .metersPerSecond),
        MetricDefinition("ACT_RUNNING_SPEED", category: .activity, name: "Running speed",
                         canonicalUnit: .metersPerSecond),
        MetricDefinition("ACT_RUNNING_POWER", category: .activity, name: "Running power",
                         canonicalUnit: .watt),
        MetricDefinition("ACT_RUNNING_STRIDE_LENGTH", category: .activity, name: "Running stride length",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_RUNNING_VERTICAL_OSCILLATION", category: .activity, name: "Vertical oscillation",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_RUNNING_GROUND_CONTACT_TIME", category: .activity, name: "Ground contact time",
                         canonicalUnit: .second),
        MetricDefinition("ACT_RUNNING_CADENCE", category: .activity, name: "Running cadence",
                         description: "Steps per minute during a run.",
                         canonicalUnit: .revolutionsPerMinute),
        MetricDefinition("ACT_CYCLING_SPEED", category: .activity, name: "Cycling speed",
                         canonicalUnit: .metersPerSecond),
        MetricDefinition("ACT_CYCLING_POWER", category: .activity, name: "Cycling power",
                         canonicalUnit: .watt),
        MetricDefinition("ACT_CYCLING_CADENCE", category: .activity, name: "Cycling cadence",
                         canonicalUnit: .revolutionsPerMinute),
        MetricDefinition("ACT_CYCLING_FTP", category: .activity, name: "Functional threshold power",
                         canonicalUnit: .watt),
        MetricDefinition("ACT_ALTITUDE", category: .activity, name: "Altitude",
                         description: "Elevation above sea level at a point in time.",
                         canonicalUnit: .meter),
        MetricDefinition("ACT_ELEVATION_GAIN", category: .activity, name: "Elevation gain",
                         canonicalUnit: .meter)
    ]

    // MARK: - Energie

    static let energy: [MetricDefinition] = [
        MetricDefinition("NRG_ACTIVE", category: .energy, name: "Active energy burned",
                         canonicalUnit: .kilocalorie),
        MetricDefinition("NRG_BASAL", category: .energy, name: "Basal energy burned",
                         canonicalUnit: .kilocalorie),
        MetricDefinition("NRG_TOTAL", category: .energy, name: "Total energy burned",
                         description: "Active plus basal energy, when a provider reports only the total.",
                         canonicalUnit: .kilocalorie)
    ]

    // MARK: - Herz

    static let heart: [MetricDefinition] = [
        MetricDefinition("HRT_RATE", category: .heart, name: "Heart rate",
                         canonicalUnit: .beatsPerMinute),
        MetricDefinition("HRT_RESTING_RATE", category: .heart, name: "Resting heart rate",
                         canonicalUnit: .beatsPerMinute),
        MetricDefinition("HRT_WALKING_AVERAGE", category: .heart, name: "Walking heart rate average",
                         canonicalUnit: .beatsPerMinute),
        MetricDefinition("HRT_MAX_RATE", category: .heart, name: "Maximum heart rate",
                         canonicalUnit: .beatsPerMinute),
        MetricDefinition("HRT_RECOVERY_ONE_MINUTE", category: .heart, name: "One-minute heart rate recovery",
                         canonicalUnit: .beatsPerMinute),
        // SDNN und RMSSD sind zwei Rechenwege. Apple liefert SDNN, Garmin und
        // Oura ueblicherweise RMSSD – deshalb zwei IDs statt einem HRT_HRV,
        // in dem sich unvergleichbare Zahlen mischen wuerden.
        MetricDefinition("HRT_HRV_SDNN", category: .heart, name: "Heart rate variability (SDNN)",
                         canonicalUnit: .millisecond),
        MetricDefinition("HRT_HRV_RMSSD", category: .heart, name: "Heart rate variability (RMSSD)",
                         canonicalUnit: .millisecond),
        MetricDefinition("HRT_VO2_MAX", category: .heart, name: "VO2 max",
                         canonicalUnit: .milliliterPerKilogramMinute),
        MetricDefinition("HRT_BLOOD_PRESSURE_SYSTOLIC", category: .heart, name: "Blood pressure, systolic",
                         canonicalUnit: .millimeterOfMercury),
        MetricDefinition("HRT_BLOOD_PRESSURE_DIASTOLIC", category: .heart, name: "Blood pressure, diastolic",
                         canonicalUnit: .millimeterOfMercury),
        MetricDefinition("HRT_PERFUSION_INDEX", category: .heart, name: "Peripheral perfusion index",
                         canonicalUnit: .percent),
        MetricDefinition("HRT_AFIB_BURDEN", category: .heart, name: "Atrial fibrillation burden",
                         canonicalUnit: .percent)
    ]

    // MARK: - Koerper

    static let body: [MetricDefinition] = [
        MetricDefinition("BDY_WEIGHT", category: .body, name: "Body weight",
                         canonicalUnit: .kilogram),
        MetricDefinition("BDY_BMI", category: .body, name: "Body mass index",
                         canonicalUnit: UnitCode.none),
        MetricDefinition("BDY_FAT", category: .body, name: "Body fat percentage",
                         canonicalUnit: .percent),
        MetricDefinition("BDY_LEAN_MASS", category: .body, name: "Lean body mass",
                         canonicalUnit: .kilogram),
        MetricDefinition("BDY_MUSCLE_MASS", category: .body, name: "Muscle mass",
                         description: "Reported by scales of several vendors; Apple Health has no equivalent.",
                         canonicalUnit: .kilogram),
        MetricDefinition("BDY_BONE_MASS", category: .body, name: "Bone mass",
                         canonicalUnit: .kilogram),
        MetricDefinition("BDY_WATER_PERCENTAGE", category: .body, name: "Body water percentage",
                         canonicalUnit: .percent),
        MetricDefinition("BDY_HEIGHT", category: .body, name: "Height",
                         canonicalUnit: .meter),
        MetricDefinition("BDY_WAIST_CIRCUMFERENCE", category: .body, name: "Waist circumference",
                         canonicalUnit: .meter)
    ]

    // MARK: - Ernaehrung

    static let nutrition: [MetricDefinition] = [
        MetricDefinition("NUT_ENERGY", category: .nutrition, name: "Dietary energy consumed",
                         canonicalUnit: .kilocalorie),
        MetricDefinition("NUT_WATER", category: .nutrition, name: "Water",
                         canonicalUnit: .liter),
        MetricDefinition("NUT_CARBOHYDRATES", category: .nutrition, name: "Carbohydrates", canonicalUnit: .gram),
        MetricDefinition("NUT_PROTEIN", category: .nutrition, name: "Protein", canonicalUnit: .gram),
        MetricDefinition("NUT_FAT_TOTAL", category: .nutrition, name: "Total fat", canonicalUnit: .gram),
        MetricDefinition("NUT_FAT_SATURATED", category: .nutrition, name: "Saturated fat", canonicalUnit: .gram),
        MetricDefinition("NUT_FAT_MONOUNSATURATED", category: .nutrition, name: "Monounsaturated fat", canonicalUnit: .gram),
        MetricDefinition("NUT_FAT_POLYUNSATURATED", category: .nutrition, name: "Polyunsaturated fat", canonicalUnit: .gram),
        MetricDefinition("NUT_SUGAR", category: .nutrition, name: "Sugar", canonicalUnit: .gram),
        MetricDefinition("NUT_FIBER", category: .nutrition, name: "Fiber", canonicalUnit: .gram),
        MetricDefinition("NUT_CHOLESTEROL", category: .nutrition, name: "Cholesterol", canonicalUnit: .milligram),
        MetricDefinition("NUT_SODIUM", category: .nutrition, name: "Sodium", canonicalUnit: .milligram),
        MetricDefinition("NUT_POTASSIUM", category: .nutrition, name: "Potassium", canonicalUnit: .milligram),
        MetricDefinition("NUT_CALCIUM", category: .nutrition, name: "Calcium", canonicalUnit: .milligram),
        MetricDefinition("NUT_IRON", category: .nutrition, name: "Iron", canonicalUnit: .milligram),
        MetricDefinition("NUT_MAGNESIUM", category: .nutrition, name: "Magnesium", canonicalUnit: .milligram),
        MetricDefinition("NUT_ZINC", category: .nutrition, name: "Zinc", canonicalUnit: .milligram),
        MetricDefinition("NUT_CAFFEINE", category: .nutrition, name: "Caffeine", canonicalUnit: .milligram),
        MetricDefinition("NUT_VITAMIN_C", category: .nutrition, name: "Vitamin C", canonicalUnit: .milligram),
        MetricDefinition("NUT_VITAMIN_D", category: .nutrition, name: "Vitamin D", canonicalUnit: .microgram),
        MetricDefinition("NUT_VITAMIN_B12", category: .nutrition, name: "Vitamin B12", canonicalUnit: .microgram)
    ]

    // MARK: - Atmung

    static let respiratory: [MetricDefinition] = [
        MetricDefinition("RSP_RATE", category: .respiratory, name: "Respiratory rate",
                         canonicalUnit: .breathsPerMinute),
        MetricDefinition("RSP_SPO2", category: .respiratory, name: "Oxygen saturation",
                         canonicalUnit: .percent),
        MetricDefinition("RSP_FEV1", category: .respiratory, name: "Forced expiratory volume in 1 second",
                         canonicalUnit: .liter),
        MetricDefinition("RSP_FVC", category: .respiratory, name: "Forced vital capacity",
                         canonicalUnit: .liter),
        MetricDefinition("RSP_PEAK_FLOW", category: .respiratory, name: "Peak expiratory flow rate",
                         canonicalUnit: .litersPerMinute),
        MetricDefinition("RSP_INHALER_USAGE", category: .respiratory, name: "Inhaler usage",
                         canonicalUnit: .count)
    ]

    // MARK: - Temperatur

    static let temperature: [MetricDefinition] = [
        MetricDefinition("TMP_BODY", category: .temperature, name: "Body temperature",
                         canonicalUnit: .celsius),
        MetricDefinition("TMP_BASAL_BODY", category: .temperature, name: "Basal body temperature",
                         canonicalUnit: .celsius),
        MetricDefinition("TMP_SLEEPING_WRIST", category: .temperature, name: "Sleeping wrist temperature",
                         canonicalUnit: .celsius),
        MetricDefinition("TMP_SKIN_DELTA", category: .temperature, name: "Skin temperature deviation",
                         description: "Deviation from the personal baseline, as reported by several wearables.",
                         canonicalUnit: .celsius)
    ]

    // MARK: - Vitalwerte

    static let vitals: [MetricDefinition] = [
        MetricDefinition("VTL_BLOOD_GLUCOSE", category: .vitals, name: "Blood glucose",
                         canonicalUnit: .milligramPerDeciliter),
        MetricDefinition("VTL_INSULIN_DELIVERY", category: .vitals, name: "Insulin delivery",
                         canonicalUnit: .internationalUnit),
        MetricDefinition("VTL_FALLS", category: .vitals, name: "Number of times fallen",
                         canonicalUnit: .count),
        MetricDefinition("VTL_STRESS_LEVEL", category: .vitals, name: "Stress level",
                         description: "Vendor-neutral 0-100 stress scale, only filled when a provider documents that scale.",
                         canonicalUnit: .index)
    ]

    // MARK: - Umgebung

    static let environment: [MetricDefinition] = [
        MetricDefinition("ENV_AUDIO_EXPOSURE", category: .environment, name: "Environmental audio exposure",
                         canonicalUnit: .decibel),
        MetricDefinition("ENV_HEADPHONE_AUDIO_EXPOSURE", category: .environment, name: "Headphone audio exposure",
                         canonicalUnit: .decibel),
        MetricDefinition("ENV_UV_INDEX", category: .environment, name: "UV exposure index",
                         canonicalUnit: .index)
    ]

    // MARK: - Schlaf

    static let sleepStageCodes = ["AWAKE", "REM", "CORE", "DEEP", "IN_BED", "ASLEEP_UNSPECIFIED"]

    static let sleep: [MetricDefinition] = [
        MetricDefinition("SLP_STAGE", category: .sleep, name: "Sleep stage",
                         description: "One stage segment with start and end time.",
                         valueType: .enumerated,
                         canonicalUnit: nil,
                         allowedCodes: sleepStageCodes),
        MetricDefinition("SLP_DURATION", category: .sleep, name: "Time asleep",
                         canonicalUnit: .second),
        MetricDefinition("SLP_TIME_IN_BED", category: .sleep, name: "Time in bed",
                         canonicalUnit: .second),
        MetricDefinition("SLP_DEEP_DURATION", category: .sleep, name: "Deep sleep duration",
                         canonicalUnit: .second),
        MetricDefinition("SLP_CORE_DURATION", category: .sleep, name: "Core sleep duration",
                         canonicalUnit: .second),
        MetricDefinition("SLP_REM_DURATION", category: .sleep, name: "REM sleep duration",
                         canonicalUnit: .second),
        MetricDefinition("SLP_AWAKE_DURATION", category: .sleep, name: "Awake duration during sleep",
                         canonicalUnit: .second),
        MetricDefinition("SLP_EFFICIENCY", category: .sleep, name: "Sleep efficiency",
                         canonicalUnit: .percent)
    ]

    // MARK: - Zyklus

    static let cycle: [MetricDefinition] = [
        MetricDefinition("CYC_EVENT", category: .cycle, name: "Cycle event",
                         valueType: .enumerated,
                         canonicalUnit: nil,
                         allowedCodes: ["INTERMENSTRUAL_BLEEDING", "OVULATION_TEST",
                                        "CERVICAL_MUCUS", "SEXUAL_ACTIVITY"]),
        MetricDefinition("CYC_MENSTRUAL_FLOW", category: .cycle, name: "Menstrual flow",
                         valueType: .enumerated,
                         canonicalUnit: nil,
                         allowedCodes: ["NONE", "LIGHT", "MEDIUM", "HEAVY", "UNSPECIFIED"]),
        MetricDefinition("CYC_CURRENT_DAY", category: .cycle, name: "Current cycle day",
                         canonicalUnit: .count),
        MetricDefinition("CYC_AVERAGE_LENGTH", category: .cycle, name: "Average cycle length",
                         canonicalUnit: .day),
        MetricDefinition("CYC_AVERAGE_PERIOD_LENGTH", category: .cycle, name: "Average period length",
                         canonicalUnit: .day),
        MetricDefinition("CYC_BLEEDING_DAYS", category: .cycle, name: "Bleeding days in cycle",
                         canonicalUnit: .count)
    ]

    // MARK: - Workout

    static let workout: [MetricDefinition] = [
        MetricDefinition("WRK_DURATION", category: .workout, name: "Workout duration",
                         canonicalUnit: .second),
        MetricDefinition("WRK_DISTANCE", category: .workout, name: "Workout distance",
                         canonicalUnit: .meter),
        MetricDefinition("WRK_ENERGY", category: .workout, name: "Workout energy burned",
                         canonicalUnit: .kilocalorie),
        MetricDefinition("WRK_COUNT_TOTAL", category: .workout, name: "Total workout count",
                         canonicalUnit: .count),
        MetricDefinition("WRK_SPORT", category: .workout, name: "Workout sport type",
                         valueType: .category,
                         canonicalUnit: nil),
        // Krafttraining, aufgeschluesselt.
        //
        // Frueher lag ein ganzer Satz als JSON in `WRK_STRENGTH_SET`. Damit
        // liess sich nichts auswerten: kein Verlauf des Arbeitsgewichts, keine
        // Summe des Volumens, kein Vergleich zwischen Anbietern. Jede Groesse
        // hat jetzt ihre eigene Entitaet mit Einheit.
        MetricDefinition("WRK_EXERCISE", category: .workout, name: "Exercise",
                         description: "Which exercise a set belongs to.",
                         valueType: .category,
                         canonicalUnit: nil),
        MetricDefinition("WRK_SET_REPS", category: .workout, name: "Repetitions",
                         canonicalUnit: .count),
        MetricDefinition("WRK_SET_WEIGHT", category: .workout, name: "Set weight",
                         canonicalUnit: .kilogram),
        MetricDefinition("WRK_SET_VOLUME", category: .workout, name: "Set volume",
                         description: "Repetitions times weight – the load actually moved.",
                         canonicalUnit: .kilogram),
        MetricDefinition("WRK_SET_RPE", category: .workout, name: "Rate of perceived exertion",
                         description: "How hard the set felt, 1–10.",
                         canonicalUnit: .score),
        MetricDefinition("WRK_SET_TYPE", category: .workout, name: "Set type",
                         description: "Warm-up, working set, drop set and so on.",
                         valueType: .enumerated,
                         canonicalUnit: nil,
                         allowedCodes: ["WARMUP", "WORKING", "DROPSET", "FAILURE",
                                        "SUPERSET", "COOLDOWN"]),
        MetricDefinition("WRK_SET_IS_PERSONAL_RECORD", category: .workout,
                         name: "Set is a personal record",
                         valueType: .boolean,
                         canonicalUnit: nil),

        // Geraeteeinstellungen. Keine Messwerte im engeren Sinn, aber genau
        // das, was man beim naechsten Mal wieder braucht – und was sonst in
        // einer Notiz verschwindet.
        MetricDefinition("WRK_EQUIPMENT_NAME", category: .workout, name: "Equipment",
                         valueType: .string,
                         canonicalUnit: nil),
        MetricDefinition("WRK_EQUIPMENT_SEAT", category: .workout, name: "Seat setting",
                         valueType: .string,
                         canonicalUnit: nil),
        MetricDefinition("WRK_EQUIPMENT_BACKREST", category: .workout, name: "Backrest setting",
                         valueType: .string,
                         canonicalUnit: nil),
        MetricDefinition("WRK_EQUIPMENT_HANDLE", category: .workout, name: "Handle setting",
                         valueType: .string,
                         canonicalUnit: nil),
        MetricDefinition("WRK_EQUIPMENT_RANGE", category: .workout, name: "Range setting",
                         valueType: .string,
                         canonicalUnit: nil),
        MetricDefinition("WRK_ROUTE", category: .workout, name: "Workout route",
                         description: "GPS track belonging to a workout.",
                         valueType: .series,
                         canonicalUnit: nil),
        MetricDefinition("WRK_WEATHER", category: .workout, name: "Workout weather",
                         valueType: .json,
                         canonicalUnit: nil),
        MetricDefinition("WRK_INJURY", category: .workout, name: "Workout injury note",
                         valueType: .json,
                         canonicalUnit: nil)
    ]

    // MARK: - Proprietaere Anbieterwerte

    /// Herstellereigene Scores. Sie tragen den Provider-Code als Praefix und
    /// sind ausdruecklich nicht untereinander vergleichbar – ein Body Battery
    /// von 70 ist kein Readiness Score von 70.
    static let proprietary: [MetricDefinition] = [
        MetricDefinition("GAR_BODY_BATTERY", category: .proprietary, name: "Garmin Body Battery",
                         canonicalUnit: .score,
                         isProprietary: true, proprietaryProvider: .garmin),
        MetricDefinition("GAR_STRESS_SCORE", category: .proprietary, name: "Garmin stress score",
                         canonicalUnit: .score,
                         isProprietary: true, proprietaryProvider: .garmin),
        MetricDefinition("OUR_READINESS_SCORE", category: .proprietary, name: "Oura readiness score",
                         canonicalUnit: .score,
                         isProprietary: true, proprietaryProvider: .oura),
        MetricDefinition("OUR_SLEEP_SCORE", category: .proprietary, name: "Oura sleep score",
                         canonicalUnit: .score,
                         isProprietary: true, proprietaryProvider: .oura),
        MetricDefinition("SAM_ENERGY_SCORE", category: .proprietary, name: "Samsung energy score",
                         canonicalUnit: .score,
                         isProprietary: true, proprietaryProvider: .samsung),
        MetricDefinition("HUA_HEALTH_SCORE", category: .proprietary, name: "Huawei health score",
                         canonicalUnit: .score,
                         isProprietary: true, proprietaryProvider: .huawei)
    ]
}
