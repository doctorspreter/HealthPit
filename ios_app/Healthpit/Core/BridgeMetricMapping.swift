//
//  BridgeMetricMapping.swift
//  HealthPitCore
//
//  Die Sensorkennungen, die HealthPit bisher an Home Assistant geschickt hat,
//  und was sie fachlich bedeuten.
//
//  Die linke Spalte bleibt im Einsatz: Aus ihr entsteht in Home Assistant die
//  Entity-ID. Wuerde sie sich aendern, verloere der Nutzer dort Verlaeufe und
//  Automationen. Die Metric ID reist deshalb als zusaetzliches Feld mit,
//  statt den Sensornamen zu ersetzen.
//
//  Dieselbe Tabelle steht in `custom_components/healthpit/metrics.py`. Der
//  Test `test_swift_and_python_tables_agree` haelt beide Seiten zusammen.
//

import Foundation

enum BridgeMetricMapping {

    /// Bisherige Sensorkennung → fachliche Kennung.
    static let legacyToMetricID: [String: MetricID] = [
        "step_count": "ACT_STEPS",
        "distance_walking_running": "ACT_DISTANCE_WALK_RUN",
        "distance_cycling": "ACT_DISTANCE_CYCLING",
        "distance_swimming": "ACT_DISTANCE_SWIMMING",
        "swimming_stroke_count": "ACT_SWIM_STROKES",
        "distance_wheelchair": "ACT_DISTANCE_WHEELCHAIR",
        "push_count": "ACT_WHEELCHAIR_PUSHES",
        "distance_downhill_snow_sports": "ACT_DISTANCE_SNOW_SPORTS",
        "flights_climbed": "ACT_FLIGHTS_CLIMBED",
        "apple_exercise_time": "ACT_EXERCISE_TIME",
        "apple_stand_time": "ACT_STAND_TIME",
        "apple_move_time": "ACT_MOVE_TIME",
        "walking_speed": "ACT_WALKING_SPEED",
        "walking_step_length": "ACT_WALKING_STEP_LENGTH",
        "walking_asymmetry_percentage": "ACT_WALKING_ASYMMETRY",
        "walking_double_support_percentage": "ACT_WALKING_DOUBLE_SUPPORT",
        "apple_walking_steadiness": "ACT_WALKING_STEADINESS",
        "six_minute_walk_test_distance": "ACT_SIX_MINUTE_WALK_DISTANCE",
        "stair_ascent_speed": "ACT_STAIR_ASCENT_SPEED",
        "stair_descent_speed": "ACT_STAIR_DESCENT_SPEED",
        "running_speed": "ACT_RUNNING_SPEED",
        "running_power": "ACT_RUNNING_POWER",
        "running_stride_length": "ACT_RUNNING_STRIDE_LENGTH",
        "running_vertical_oscillation": "ACT_RUNNING_VERTICAL_OSCILLATION",
        "running_ground_contact_time": "ACT_RUNNING_GROUND_CONTACT_TIME",
        "cycling_speed": "ACT_CYCLING_SPEED",
        "cycling_power": "ACT_CYCLING_POWER",
        "cycling_cadence": "ACT_CYCLING_CADENCE",
        "cycling_functional_threshold_power": "ACT_CYCLING_FTP",
        "active_energy_burned": "NRG_ACTIVE",
        "basal_energy_burned": "NRG_BASAL",
        "heart_rate": "HRT_RATE",
        "resting_heart_rate": "HRT_RESTING_RATE",
        "walking_heart_rate_average": "HRT_WALKING_AVERAGE",
        "heart_rate_recovery_one_minute": "HRT_RECOVERY_ONE_MINUTE",
        "heart_rate_variability_sdnn": "HRT_HRV_SDNN",
        "vo2_max": "HRT_VO2_MAX",
        "blood_pressure_systolic": "HRT_BLOOD_PRESSURE_SYSTOLIC",
        "blood_pressure_diastolic": "HRT_BLOOD_PRESSURE_DIASTOLIC",
        "peripheral_perfusion_index": "HRT_PERFUSION_INDEX",
        "atrial_fibrillation_burden": "HRT_AFIB_BURDEN",
        "body_mass": "BDY_WEIGHT",
        "body_mass_index": "BDY_BMI",
        "body_fat_percentage": "BDY_FAT",
        "lean_body_mass": "BDY_LEAN_MASS",
        "height": "BDY_HEIGHT",
        "waist_circumference": "BDY_WAIST_CIRCUMFERENCE",
        "dietary_energy_consumed": "NUT_ENERGY",
        "dietary_water": "NUT_WATER",
        "dietary_carbohydrates": "NUT_CARBOHYDRATES",
        "dietary_protein": "NUT_PROTEIN",
        "dietary_fat_total": "NUT_FAT_TOTAL",
        "dietary_fat_saturated": "NUT_FAT_SATURATED",
        "dietary_fat_monounsaturated": "NUT_FAT_MONOUNSATURATED",
        "dietary_fat_polyunsaturated": "NUT_FAT_POLYUNSATURATED",
        "dietary_sugar": "NUT_SUGAR",
        "dietary_fiber": "NUT_FIBER",
        "dietary_cholesterol": "NUT_CHOLESTEROL",
        "dietary_sodium": "NUT_SODIUM",
        "dietary_potassium": "NUT_POTASSIUM",
        "dietary_calcium": "NUT_CALCIUM",
        "dietary_iron": "NUT_IRON",
        "dietary_magnesium": "NUT_MAGNESIUM",
        "dietary_zinc": "NUT_ZINC",
        "dietary_caffeine": "NUT_CAFFEINE",
        "dietary_vitamin_c": "NUT_VITAMIN_C",
        "dietary_vitamin_d": "NUT_VITAMIN_D",
        "dietary_vitamin_b12": "NUT_VITAMIN_B12",
        "respiratory_rate": "RSP_RATE",
        "oxygen_saturation": "RSP_SPO2",
        "forced_expiratory_volume1": "RSP_FEV1",
        "forced_vital_capacity": "RSP_FVC",
        "peak_expiratory_flow_rate": "RSP_PEAK_FLOW",
        "inhaler_usage": "RSP_INHALER_USAGE",
        "body_temperature": "TMP_BODY",
        "basal_body_temperature": "TMP_BASAL_BODY",
        "apple_sleeping_wrist_temperature": "TMP_SLEEPING_WRIST",
        "blood_glucose": "VTL_BLOOD_GLUCOSE",
        "insulin_delivery": "VTL_INSULIN_DELIVERY",
        "number_of_times_fallen": "VTL_FALLS",
        "environmental_audio_exposure": "ENV_AUDIO_EXPOSURE",
        "headphone_audio_exposure": "ENV_HEADPHONE_AUDIO_EXPOSURE",
        "uv_exposure": "ENV_UV_INDEX",
        "sleep_duration": "SLP_DURATION",
        "sleep_time_in_bed": "SLP_TIME_IN_BED",
        "sleep_efficiency": "SLP_EFFICIENCY",
        "sleep_deep_duration": "SLP_DEEP_DURATION",
        "sleep_core_duration": "SLP_CORE_DURATION",
        "sleep_rem_duration": "SLP_REM_DURATION",
        "sleep_awake_duration": "SLP_AWAKE_DURATION",
        "cycle_current_day": "CYC_CURRENT_DAY",
        "cycle_average_length": "CYC_AVERAGE_LENGTH",
        "cycle_average_period_length": "CYC_AVERAGE_PERIOD_LENGTH",
        "cycle_bleeding_days": "CYC_BLEEDING_DAYS",
        "workout_count_all_time": "WRK_COUNT_TOTAL",
    ]

    static func metricID(forBridgeID bridgeID: String) -> MetricID? {
        legacyToMetricID[bridgeID.lowercased()]
    }

    /// Umgekehrt: Unter welchem Sensornamen laeuft diese Metrik in Home
    /// Assistant? Nur fuer Werte, die es dort schon gibt.
    static let metricIDToLegacy: [MetricID: String] = {
        var result: [MetricID: String] = [:]
        for (legacy, metricID) in legacyToMetricID where result[metricID] == nil {
            result[metricID] = legacy
        }
        return result
    }()
}
