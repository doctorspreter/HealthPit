"""Validation for payloads pushed straight into Home Assistant.

Webhook mode has no FastAPI in front of it, so the checks the bridge did with
pydantic happen here instead. Everything is normalised to JSON-native types so
the result can go into Home Assistant's ``Store`` unchanged, and the field names
match what the bridge API returns — that way the entity builders work for all
three modes without knowing where the data came from.
"""

from __future__ import annotations

from datetime import datetime, timezone
from math import isfinite
from typing import Any

from .metrics import (
    DEFAULT_INGEST_PROVIDER,
    DEFAULT_ORIGIN_PROVIDER,
    PROVIDERS,
    canonical_metric_id,
    provisional_metric_id,
    registry_category,
)

CATEGORIES = {
    "activity",
    "workouts",
    "heart",
    "sleep",
    "body",
    "nutrition",
    "vitals",
    "cycle",
}
AGGREGATIONS = {"sum", "average", "latest"}
STATE_CLASSES = {"measurement", "total", "total_increasing"}
WORKOUT_SOURCES = {"manual", "apple_health", "gpx", "tcx", "garmin", "gympit"}

_SOURCE_ALIASES = {
    "apple": "apple_health",
    "applehealth": "apple_health",
    "apple_healthkit": "apple_health",
    "healthkit": "apple_health",
    "health": "apple_health",
    "gym_pit": "gympit",
    "gympit_iphone": "gympit",
    "gympit_(iphone)": "gympit",
    "healthpit_iphone": "apple_health",
    "healthpit_(iphone)": "apple_health",
}

# What a person can decide about a proposed duplicate.
LINK_ACTIONS = {"merge", "separate"}

MAX_METRICS_PER_BATCH = 500
MAX_WORKOUTS_PER_BATCH = 1000
MAX_EXERCISES_PER_WORKOUT = 500
MAX_SETS_PER_EXERCISE = 1000
MAX_ROUTE_POINTS = 20000
MAX_RECONCILE_IDS = 50000
MAX_HISTORY_POINTS_PER_BATCH = 5000

# Ein Lauf traegt einige tausend GPS-Punkte. So viele braucht niemand, um die
# Strecke zu erkennen, und sie machen den Speicher unnoetig gross.
STORED_ROUTE_POINTS = 500


class PayloadError(ValueError):
    """Raised when a pushed payload cannot be used."""


def normalize_workout_source(value: Any) -> str:
    """Map the various spellings the apps use onto one stable source name."""
    if value is None:
        return "manual"
    key = str(value).strip().lower().replace("-", "_").replace(" ", "_")
    if not key:
        return "manual"
    return _SOURCE_ALIASES.get(key, key)


def _first(raw: dict[str, Any], *names: str) -> Any:
    """Return the first present alias, mirroring the bridge's AliasChoices."""
    for name in names:
        if name in raw and raw[name] not in (None, ""):
            return raw[name]
    return None


def _text(value: Any, *, field: str, default: str = "", max_length: int = 0) -> str:
    text = default if value is None else str(value)
    if max_length and len(text) > max_length:
        raise PayloadError(f"{field} is longer than {max_length} characters")
    return text


def _required_text(value: Any, *, field: str, default: str = "", max_length: int = 0) -> str:
    text = "" if value is None else str(value).strip()
    text = text or default
    if not text:
        raise PayloadError(f"{field} is required")
    if max_length and len(text) > max_length:
        raise PayloadError(f"{field} is longer than {max_length} characters")
    return text


def _number(value: Any) -> float | None:
    if value in (None, "") or isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    # NaN and infinities would poison later aggregations and JSON storage.
    return number if isfinite(number) else None


def _required_number(value: Any, *, field: str) -> float:
    number = _number(value)
    if number is None:
        raise PayloadError(f"{field} must be a number")
    return number


def _datetime_text(value: Any, *, field: str, required: bool = True) -> str | None:
    """Return an ISO-8601 string, or None when the field is optional and absent."""
    if value in (None, ""):
        if required:
            raise PayloadError(f"{field} is required")
        return None
    if isinstance(value, datetime):
        parsed = value
    else:
        try:
            parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError as err:
            raise PayloadError(f"{field} is not a valid timestamp") from err
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.isoformat()


def _timestamp(value: str | None) -> float | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value).timestamp()
    except ValueError:
        return None


def _provider_code(value: Any, default: str) -> str:
    """A three-letter provider code, or the default when nothing usable came."""
    if not isinstance(value, str):
        return default
    code = value.strip().upper()
    if code in PROVIDERS:
        return code
    if len(code) == 3 and code.isalpha():
        # An unknown provider is fine: the registry is meant to grow. Only the
        # shape is enforced here.
        return code
    return default


def normalize_metric(raw: Any) -> dict[str, Any]:
    """Validate one health metric and return it in bridge-API shape."""
    if not isinstance(raw, dict):
        raise PayloadError("Each metric must be an object")

    category = _required_text(raw.get("category"), field="category", max_length=40)
    if category not in CATEGORIES:
        raise PayloadError(f"category must be one of {sorted(CATEGORIES)}")

    aggregation = _required_text(
        raw.get("aggregation"), field="aggregation", default="latest", max_length=20
    )
    if aggregation not in AGGREGATIONS:
        raise PayloadError(f"aggregation must be one of {sorted(AGGREGATIONS)}")

    state_class = raw.get("state_class")
    state_class = None if state_class in (None, "") else str(state_class)
    if state_class is not None and state_class not in STATE_CLASSES:
        raise PayloadError(f"state_class must be one of {sorted(STATE_CLASSES)}")

    display_precision = raw.get("display_precision", raw.get("displayPrecision"))
    if display_precision is not None:
        if (
            isinstance(display_precision, bool)
            or not isinstance(display_precision, int)
            or not 0 <= display_precision <= 6
        ):
            raise PayloadError("display_precision must be an integer from 0 to 6")

    legacy_id = _required_text(raw.get("id"), field="id", max_length=120)

    # The canonical id may come with the payload; otherwise it is derived from
    # the id the app has always sent. Unknown values keep a provisional id so
    # they stay visible instead of vanishing.
    origin_provider = _provider_code(
        _first(raw, "origin_provider", "originProvider"), DEFAULT_ORIGIN_PROVIDER
    )
    ingest_provider = _provider_code(
        _first(raw, "ingest_provider", "ingestProvider"), DEFAULT_INGEST_PROVIDER
    )
    canonical = canonical_metric_id(
        _first(raw, "metric_id", "metricId")
    ) or canonical_metric_id(legacy_id) or provisional_metric_id(origin_provider, legacy_id)

    return {
        # The storage key stays the id the app has always sent, so existing
        # sensors keep their entity id and their history.
        "metric_id": legacy_id,
        "legacy_metric_id": legacy_id,
        "canonical_metric_id": canonical,
        "registry_category": registry_category(canonical) if canonical else None,
        "origin_provider": origin_provider,
        "ingest_provider": ingest_provider,
        "source_app_id": _text(
            _first(raw, "source_app_id", "sourceAppId"), field="source_app_id", max_length=120
        )
        or None,
        "observation_id": _text(
            _first(raw, "observation_id", "observationId"),
            field="observation_id",
            max_length=64,
        )
        or None,
        "unit_code": _text(
            _first(raw, "unit_code", "unitCode"), field="unit_code", max_length=16
        )
        or None,
        "period_type": _text(
            _first(raw, "period_type", "periodType"), field="period_type", max_length=16
        )
        or None,
        "category": category,
        "title": _required_text(raw.get("title"), field="title", max_length=120),
        "value": _required_number(raw.get("value"), field="value"),
        "unit": _text(raw.get("unit"), field="unit", max_length=40),
        "measured_at": _datetime_text(
            _first(raw, "measured_at", "measuredAt"), field="measured_at"
        ),
        "aggregation": aggregation,
        "icon": raw.get("icon") or None,
        "device_class": raw.get("device_class") or None,
        "state_class": state_class,
        "display_precision": display_precision,
    }


def normalize_health_batch(
    raw: Any,
) -> tuple[str, list[dict[str, Any]], list[str]]:
    """Validate a metric batch.

    Returns (device_id, metrics, problems). A malformed envelope is still a hard
    error, but a single unusable metric only gets skipped: a released app that
    starts sending one new kind of value must not be able to stop every other
    value from arriving.
    """
    if not isinstance(raw, dict):
        raise PayloadError("The payload must be an object")
    device_id = _required_text(
        _first(raw, "device_id", "deviceId"), field="device_id", max_length=80
    )
    metrics = raw.get("metrics")
    if not isinstance(metrics, list) or not metrics:
        raise PayloadError("metrics must be a non-empty list")
    if len(metrics) > MAX_METRICS_PER_BATCH:
        raise PayloadError(f"metrics holds more than {MAX_METRICS_PER_BATCH} entries")

    out: list[dict[str, Any]] = []
    problems: list[str] = []
    for item in metrics:
        try:
            out.append(normalize_metric(item))
        except PayloadError as err:
            identifier = item.get("id") if isinstance(item, dict) else "?"
            problems.append(f"{identifier}: {err}")
    if not out:
        raise PayloadError("; ".join(problems) or "No usable metric in the batch")
    return device_id, out, problems


def normalize_metric_history_batch(
    raw: Any,
) -> tuple[str, str, str, list[dict[str, Any]]]:
    """Validate one chunk of hourly long-term statistics.

    Metric metadata is deliberately not accepted from this endpoint. The
    corresponding current metric must have been pushed first, and its stored
    metadata decides the unit and whether this is a mean or a cumulative
    series. That prevents a client from changing an existing statistic's type
    halfway through its history.
    """
    if not isinstance(raw, dict):
        raise PayloadError("The payload must be an object")

    device_id = _required_text(
        _first(raw, "device_id", "deviceId"), field="device_id", max_length=80
    )
    category = _required_text(raw.get("category"), field="category", max_length=40)
    if category not in CATEGORIES:
        raise PayloadError(f"category must be one of {sorted(CATEGORIES)}")
    metric_id = _required_text(
        _first(raw, "metric_id", "metricId"), field="metric_id", max_length=120
    )

    raw_points = raw.get("points")
    if not isinstance(raw_points, list) or not raw_points:
        raise PayloadError("points must be a non-empty list")
    if len(raw_points) > MAX_HISTORY_POINTS_PER_BATCH:
        raise PayloadError(
            f"points holds more than {MAX_HISTORY_POINTS_PER_BATCH} entries"
        )

    points: list[dict[str, Any]] = []
    previous_timestamp: float | None = None
    for item in raw_points:
        if not isinstance(item, dict):
            raise PayloadError("Each history point must be an object")
        start = _datetime_text(item.get("start"), field="start")
        assert start is not None
        timestamp = _timestamp(start)
        if timestamp is None:
            raise PayloadError("start is not a valid timestamp")
        if previous_timestamp is not None and timestamp <= previous_timestamp:
            raise PayloadError("history points must be strictly ordered by start")
        previous_timestamp = timestamp

        point = {"start": start}
        for field in ("state", "sum", "mean", "min", "max"):
            if field not in item or item[field] is None:
                continue
            value = _number(item[field])
            if value is None:
                raise PayloadError(f"{field} must be a finite number")
            point[field] = value
        if len(point) == 1:
            raise PayloadError("Each history point needs statistic values")
        points.append(point)

    return device_id, category, metric_id, points


def _normalize_set(raw: Any, *, index: int) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise PayloadError("Each set must be an object")
    reps = _number(raw.get("reps"))
    weight_kg = _number(_first(raw, "weight_kg", "weightKg"))
    volume_kg = _number(_first(raw, "volume_kg", "volumeKg"))
    if volume_kg is None and reps is not None and weight_kg is not None:
        volume_kg = reps * weight_kg
    set_index = raw.get("index")
    set_index = index + 1 if set_index in (None, "") else int(set_index)
    return {
        "set_id": _text(raw.get("id"), field="set id", max_length=120)
        or f"set-{set_index}",
        "index": max(0, set_index),
        "type": _text(raw.get("type"), field="set type", default="Arbeit", max_length=80),
        "reps": reps,
        "weight_kg": weight_kg,
        "rpe": _number(raw.get("rpe")),
        "volume_kg": volume_kg,
        "is_personal_record": bool(
            _first(raw, "is_personal_record", "isPersonalRecord") or False
        ),
    }


def _normalize_exercise(raw: Any, *, index: int) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise PayloadError("Each exercise must be an object")
    raw_sets = _first(raw, "sets") or []
    if not isinstance(raw_sets, list):
        raw_sets = []
    if len(raw_sets) > MAX_SETS_PER_EXERCISE:
        raise PayloadError(f"An exercise holds more than {MAX_SETS_PER_EXERCISE} sets")
    sets = [_normalize_set(item, index=position) for position, item in enumerate(raw_sets)]

    weights = [item["weight_kg"] for item in sets if item["weight_kg"] is not None]
    volumes = [item["volume_kg"] for item in sets if item["volume_kg"] is not None]
    device_settings = _first(raw, "device_settings", "deviceSettings")
    return {
        "exercise_id": _text(raw.get("id"), field="exercise id", max_length=120)
        or f"exercise-{index + 1}",
        "catalog_id": _text(
            _first(raw, "catalog_id", "catalogId"), field="catalog_id", max_length=160
        ),
        "name": _required_text(raw.get("name") or raw.get("title"), field="name", default="Übung", max_length=180),
        "category": _text(raw.get("category"), field="category", max_length=120),
        "start": _datetime_text(
            _first(raw, "start", "start_time", "startTime", "startDate"),
            field="exercise start",
            required=False,
        ),
        "end": _datetime_text(
            _first(raw, "end", "end_time", "endTime", "endDate"),
            field="exercise end",
            required=False,
        ),
        "duration_seconds": _number(
            _first(raw, "duration_seconds", "durationSeconds")
        ),
        "notes": _text(raw.get("notes"), field="notes", max_length=2000),
        "device_settings": device_settings if isinstance(device_settings, dict) else {},
        "sets": sets,
        "set_count": len(sets),
        "volume_kg": sum(volumes),
        "best_weight_kg": max(weights) if weights else None,
        "personal_records": sum(1 for item in sets if item["is_personal_record"]),
    }


def thin_route(points: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    """Reduce a track to at most ``limit`` points, keeping its shape.

    The apps send every GPS sample — a few thousand for one run. Sampling evenly
    and always keeping the first and last point preserves the visible route while
    keeping the stored payload small.
    """
    if limit <= 0 or len(points) <= limit:
        return points
    if limit == 1:
        return [points[0]]
    step = (len(points) - 1) / (limit - 1)
    out: list[dict[str, Any]] = []
    seen: set[int] = set()
    for index in range(limit):
        # Rounding can land on the same sample twice at the seams.
        position = round(index * step)
        if position not in seen:
            seen.add(position)
            out.append(points[position])
    return out


def _normalize_route_point(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    latitude = _number(raw.get("latitude"))
    longitude = _number(raw.get("longitude"))
    if latitude is None or longitude is None:
        return None
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        return None
    return {
        "latitude": latitude,
        "longitude": longitude,
        "elevation": _number(raw.get("elevation")),
        "timestamp": _datetime_text(raw.get("timestamp"), field="timestamp", required=False),
        "heart_rate": _number(_first(raw, "heart_rate", "heartRate")),
    }


def normalize_workout(raw: Any, *, device_id: str) -> dict[str, Any]:
    """Validate one workout and pre-compute everything the sensors aggregate."""
    if not isinstance(raw, dict):
        raise PayloadError("Each workout must be an object")

    workout_id = _required_text(
        _first(raw, "id", "workout_id", "workoutId", "uuid"),
        field="id",
        max_length=120,
    )
    source = normalize_workout_source(raw.get("source"))
    if source not in WORKOUT_SOURCES:
        raise PayloadError(f"source must be one of {sorted(WORKOUT_SOURCES)}")

    start = _datetime_text(
        _first(raw, "start", "start_time", "startTime", "startDate"), field="start"
    )
    # The bridge treated a missing end as "same as start" rather than rejecting
    # the workout, and the apps rely on that for open-ended manual entries.
    end = _datetime_text(
        _first(raw, "end", "end_time", "endTime", "endDate"),
        field="end",
        required=False,
    ) or start

    raw_exercises = raw.get("exercises") or []
    if not isinstance(raw_exercises, list):
        raw_exercises = []
    if len(raw_exercises) > MAX_EXERCISES_PER_WORKOUT:
        raise PayloadError(
            f"A workout holds more than {MAX_EXERCISES_PER_WORKOUT} exercises"
        )
    exercises = [
        _normalize_exercise(item, index=index)
        for index, item in enumerate(raw_exercises)
    ]

    raw_route = raw.get("route") or []
    if not isinstance(raw_route, list):
        raw_route = []
    if len(raw_route) > MAX_ROUTE_POINTS:
        raise PayloadError(f"A workout holds more than {MAX_ROUTE_POINTS} route points")
    full_route = [
        point for point in (_normalize_route_point(item) for item in raw_route) if point
    ]
    route = thin_route(full_route, STORED_ROUTE_POINTS)

    explicit_duration = (
        _number(_first(raw, "duration_minutes", "durationMinutes")) or 0
    ) * 60
    span = (_timestamp(end) or 0) - (_timestamp(start) or 0)
    duration_seconds = max(span, explicit_duration, 0)

    weights = [
        item["best_weight_kg"] for item in exercises if item["best_weight_kg"] is not None
    ]
    set_volumes = [
        workout_set["volume_kg"]
        for item in exercises
        for workout_set in item["sets"]
        if workout_set["volume_kg"] is not None
    ]

    weather = raw.get("weather")
    injury = raw.get("injury")
    return {
        "device_id": device_id,
        "workout_id": workout_id,
        "id": workout_id,
        "source": source,
        "sport": _required_text(raw.get("sport"), field="sport", default="Workout", max_length=80),
        "title": _required_text(raw.get("title"), field="title", default="Workout", max_length=160),
        "start_time": start,
        "start": start,
        "end_time": end,
        "end": end,
        "duration_seconds": duration_seconds,
        "distance_km": _number(_first(raw, "distance_km", "distanceKm")),
        "energy_kcal": _number(
            _first(raw, "energy_kcal", "energyKcal", "calories", "kcal")
        ),
        "average_heart_rate": _number(
            _first(raw, "average_heart_rate", "averageHeartRate", "avgHeartRate")
        ),
        "max_heart_rate": _number(_first(raw, "max_heart_rate", "maxHeartRate")),
        "notes": _text(raw.get("notes"), field="notes", max_length=2000),
        "weather": weather if isinstance(weather, dict) else None,
        "injury": injury if isinstance(injury, dict) else None,
        "exercises": exercises,
        "exercise_count": len(exercises),
        "set_count": sum(item["set_count"] for item in exercises),
        "volume_kg": sum(item["volume_kg"] for item in exercises),
        "max_weight_kg": max(weights) if weights else None,
        "best_set_volume_kg": max(set_volumes) if set_volumes else None,
        "personal_records": sum(item["personal_records"] for item in exercises),
        "route": route,
        "route_points": len(route),
        "route_points_total": len(full_route),
    }


def normalize_workout_batch(raw: Any) -> tuple[str, list[dict[str, Any]]]:
    """Validate a workout batch and return (device_id, workouts)."""
    if not isinstance(raw, dict):
        raise PayloadError("The payload must be an object")
    device_id = _required_text(
        _first(raw, "device_id", "deviceId"), field="device_id", max_length=120
    )
    workouts = raw.get("workouts")
    if not isinstance(workouts, list):
        raise PayloadError("workouts must be a list")
    if len(workouts) > MAX_WORKOUTS_PER_BATCH:
        raise PayloadError(f"workouts holds more than {MAX_WORKOUTS_PER_BATCH} entries")
    return device_id, [
        normalize_workout(item, device_id=device_id) for item in workouts
    ]


def normalize_link(raw: Any, *, require_action: bool) -> tuple[str, str, str]:
    """Validate a duplicate decision and return (primary, linked, action).

    ``primary`` and ``linked`` are ``source:workout_id`` keys as handed out by
    the duplicates endpoint. They are opaque here on purpose: the merge decides
    what they mean, and a decision must survive a workout being re-imported.
    """
    if not isinstance(raw, dict):
        raise PayloadError("The payload must be an object")
    primary = _required_text(raw.get("primary"), field="primary", max_length=200)
    linked = _required_text(raw.get("linked"), field="linked", max_length=200)
    if primary == linked:
        raise PayloadError("primary and linked must be two different workouts")
    if not require_action:
        return primary, linked, ""
    action = str(raw.get("action") or "").strip().lower()
    if action not in LINK_ACTIONS:
        raise PayloadError(f"action must be one of {sorted(LINK_ACTIONS)}")
    return primary, linked, action


def normalize_reconcile(raw: Any) -> tuple[str, str, list[str]]:
    """Validate a reconcile request and return (device_id, source, workout_ids)."""
    if not isinstance(raw, dict):
        raise PayloadError("The payload must be an object")
    device_id = _required_text(
        _first(raw, "device_id", "deviceId"), field="device_id", max_length=80
    )
    source = normalize_workout_source(raw.get("source"))
    if source not in WORKOUT_SOURCES:
        raise PayloadError(f"source must be one of {sorted(WORKOUT_SOURCES)}")
    workout_ids = raw.get("workout_ids")
    if workout_ids is None:
        workout_ids = raw.get("workoutIds")
    if not isinstance(workout_ids, list):
        raise PayloadError("workout_ids must be a list")
    if len(workout_ids) > MAX_RECONCILE_IDS:
        raise PayloadError(f"workout_ids holds more than {MAX_RECONCILE_IDS} entries")
    return device_id, source, [str(item) for item in workout_ids if item not in (None, "")]
