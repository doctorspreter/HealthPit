"""The HealthPit metric registry, as far as Home Assistant needs it.

The apps used to identify a value by the HealthKit type, flattened into
something sensor-shaped: ``step_count``, ``heart_rate``, ``sleep_duration``.
That name says what Apple calls the value, not what the value *is* — and with
Garmin, Huawei and others arriving it stops being a useful key.

From now on every value carries a stable, provider-neutral metric id
(``ACT_STEPS``) plus the provider fields that say where it came from. This
module holds the mapping and the upgrade of data that is already stored.

Deliberately free of Home Assistant imports so it can be tested on its own,
the same way ``payload.py`` and ``precision.py`` are.
"""

from __future__ import annotations

from typing import Any

# The canonical categories of the registry. The app keeps sending its own
# dashboard category (``activity``, ``heart`` …); both are stored, because the
# dashboard grouping and the registry grouping are not the same thing.
METRIC_CATEGORIES = {
    "ACT": "activity",
    "HRT": "heart",
    "SLP": "sleep",
    "BDY": "body",
    "NRG": "energy",
    "RSP": "respiratory",
    "TMP": "temperature",
    "VTL": "vitals",
    "NUT": "nutrition",
    "WRK": "workout",
    "CYC": "cycle",
    "ENV": "environment",
    "PRP": "proprietary",
}

PROVIDERS = {
    "HPT": "HealthPit",
    "APP": "Apple Health",
    "GAR": "Garmin",
    "HUA": "Huawei Health",
    "SAM": "Samsung Health",
    "FIT": "Fitbit",
    "OUR": "Oura",
    "POL": "Polar",
    "GYM": "GymPit",
    "HAS": "Home Assistant",
}

DEFAULT_ORIGIN_PROVIDER = "APP"
DEFAULT_INGEST_PROVIDER = "APP"

# Old sensor id -> canonical metric id.
#
# The left column is exactly what the app sent so far (``HealthMetric.bridgeID``
# plus the hand-written sleep, cycle and workout keys). Nothing here may be
# removed: it is what already sits in Home Assistant's storage.
LEGACY_METRIC_IDS: dict[str, str] = {
    # Activity
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
    # Energy
    "active_energy_burned": "NRG_ACTIVE",
    "basal_energy_burned": "NRG_BASAL",
    # Heart
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
    # Body
    "body_mass": "BDY_WEIGHT",
    "body_mass_index": "BDY_BMI",
    "body_fat_percentage": "BDY_FAT",
    "lean_body_mass": "BDY_LEAN_MASS",
    "height": "BDY_HEIGHT",
    "waist_circumference": "BDY_WAIST_CIRCUMFERENCE",
    # Nutrition
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
    # Respiratory, temperature, vitals, environment
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
    # Sleep, cycle and workout keys the app wrote by hand
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
}

# Workout sources the app used to send, mapped to provider codes.
LEGACY_WORKOUT_SOURCES = {
    "manual": "HPT",
    "gpx": "HPT",
    "tcx": "HPT",
    "apple_health": "APP",
    "gympit": "GYM",
    "garmin": "GAR",
}


def is_metric_id(value: Any) -> bool:
    """Does this look like a canonical metric id (``ACT_STEPS``)?"""
    if not isinstance(value, str) or not value or len(value) > 64:
        return False
    if value[0].isdigit() or value.endswith("_") or "__" in value:
        return False
    return all(character.isupper() or character.isdigit() or character == "_" for character in value)


def canonical_metric_id(value: Any) -> str | None:
    """Canonical id for whatever the app sent, or ``None`` if unknown.

    Accepts a canonical id unchanged, translates a known legacy sensor id, and
    gives up on anything else — a guessed mapping would be worse than an
    honest gap, because it would silently mix two different values.
    """
    if is_metric_id(value):
        return str(value)
    if isinstance(value, str):
        mapped = LEGACY_METRIC_IDS.get(value.strip().lower())
        if mapped:
            return mapped
    return None


def provisional_metric_id(provider: str, legacy_id: str) -> str | None:
    """Placeholder id for a value nobody has mapped yet.

    Keeps the value visible instead of dropping it. ``PRP`` marks it as
    unclassified, so it is easy to find and give a real id later.
    """
    cleaned = "".join(
        character if character.isalnum() else "_" for character in str(legacy_id).upper()
    )
    while "__" in cleaned:
        cleaned = cleaned.replace("__", "_")
    cleaned = cleaned.strip("_")
    if not cleaned:
        return None
    candidate = f"PRP_{provider.upper()}_{cleaned}"[:64].rstrip("_")
    return candidate if is_metric_id(candidate) else None


def registry_category(metric_id: str) -> str:
    """Registry category behind a metric id (``HRT_RATE`` -> ``heart``)."""
    prefix = metric_id.split("_", 1)[0]
    return METRIC_CATEGORIES.get(prefix, "proprietary")


def provider_name(code: Any) -> str:
    return PROVIDERS.get(str(code or "").upper(), str(code or ""))


# ---------------------------------------------------------------------------
# Transfer of data that is already stored
# ---------------------------------------------------------------------------

STORAGE_VERSION_WITH_METRIC_IDS = 2


def upgrade_metric(entry: dict[str, Any]) -> dict[str, Any]:
    """Give one stored metric its canonical id and provider fields.

    The old key stays in ``legacy_metric_id``. Home Assistant entity ids are
    built from the storage key, and those must not change — a renamed sensor
    loses its history and breaks every automation pointing at it.
    """
    upgraded = dict(entry)
    legacy_id = str(entry.get("metric_id") or "")
    upgraded.setdefault("legacy_metric_id", legacy_id)

    canonical = canonical_metric_id(entry.get("canonical_metric_id")) or canonical_metric_id(legacy_id)
    if canonical is None:
        canonical = provisional_metric_id(DEFAULT_ORIGIN_PROVIDER, legacy_id)
    if canonical:
        upgraded["canonical_metric_id"] = canonical
        upgraded["registry_category"] = registry_category(canonical)

    # Everything stored so far arrived through Apple Health on the phone.
    upgraded.setdefault("origin_provider", DEFAULT_ORIGIN_PROVIDER)
    upgraded.setdefault("ingest_provider", DEFAULT_INGEST_PROVIDER)
    return upgraded


def upgrade_workout(entry: dict[str, Any]) -> dict[str, Any]:
    """Add provider fields to a stored workout, keeping ``source`` as it was."""
    upgraded = dict(entry)
    source = str(entry.get("source") or "")
    upgraded.setdefault("origin_provider", LEGACY_WORKOUT_SOURCES.get(source, "HPT"))
    upgraded.setdefault(
        "ingest_provider",
        "APP" if source == "apple_health" else upgraded["origin_provider"],
    )
    return upgraded


def upgrade_storage(data: dict[str, Any]) -> dict[str, Any]:
    """Transfer a whole storage payload to the new model.

    Runs once, from Home Assistant's storage migration. Nothing is dropped and
    no key changes, so a downgrade would still find its data.
    """
    users = data.get("users")
    if not isinstance(users, dict):
        return {"users": {}}

    migrated: dict[str, Any] = {}
    for user_id, bucket in users.items():
        if not isinstance(bucket, dict):
            continue
        metrics = bucket.get("metrics")
        workouts = bucket.get("workouts")
        migrated[str(user_id)] = {
            **bucket,
            "metrics": {
                key: upgrade_metric(value)
                for key, value in (metrics or {}).items()
                if isinstance(value, dict)
            },
            "workouts": {
                key: upgrade_workout(value)
                for key, value in (workouts or {}).items()
                if isinstance(value, dict)
            },
        }
    return {**data, "users": migrated}


def transfer_summary(data: dict[str, Any]) -> dict[str, int]:
    """What an upgrade would touch — for the log line after a migration."""
    users = data.get("users") or {}
    metrics = 0
    unresolved = 0
    workouts = 0
    for bucket in users.values():
        if not isinstance(bucket, dict):
            continue
        for entry in (bucket.get("metrics") or {}).values():
            if not isinstance(entry, dict):
                continue
            metrics += 1
            if canonical_metric_id(entry.get("metric_id")) is None:
                unresolved += 1
        workouts += len(bucket.get("workouts") or {})
    return {"metrics": metrics, "unresolved": unresolved, "workouts": workouts}
