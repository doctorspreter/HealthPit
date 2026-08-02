"""Build stable Home Assistant sensor descriptions from bridge workouts."""

from __future__ import annotations

from datetime import datetime, timezone
import re
import unicodedata
from typing import Any


def build_workout_metrics(workouts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return stable latest/aggregate sport and exercise sensor descriptions."""
    clean_workouts = [item for item in workouts if isinstance(item, dict)]
    clean_workouts.sort(key=_workout_timestamp, reverse=True)

    metrics: list[dict[str, Any]] = []
    by_sport: dict[str, list[dict[str, Any]]] = {}
    for workout in clean_workouts:
        sport = _sport_name(workout)
        by_sport.setdefault(sport, []).append(workout)

    for sport, sport_workouts in sorted(by_sport.items()):
        metrics.extend(_sport_metrics(sport, sport_workouts))

    metrics.extend(_exercise_metrics(clean_workouts))
    return sorted(metrics, key=lambda item: str(item.get("name") or ""))


def _sport_metrics(
    sport: str,
    workouts: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    latest = workouts[0]
    sport_key = _slug(sport)
    prefix = f"sport:{sport_key}"
    icon = _sport_icon(sport)
    attributes = _workout_attributes(latest)
    out: list[dict[str, Any]] = []

    _add(
        out,
        key=f"{prefix}:latest",
        name=f"Letztes Training {sport}",
        value=_parse_datetime(latest.get("start_time") or latest.get("start")),
        icon=icon,
        device_class="timestamp",
        attributes=attributes,
    )
    _add(
        out,
        key=f"{prefix}:count",
        name=f"{sport} Trainings",
        value=len(workouts),
        icon="mdi:counter",
        state_class="total",
        attributes=attributes,
    )

    total_duration_seconds = sum(_number(item.get("duration_seconds")) or 0 for item in workouts)
    _add(
        out,
        key=f"{prefix}:total_duration",
        name=f"{sport} Gesamttrainingszeit",
        value=_rounded(total_duration_seconds / 3600),
        unit="h",
        icon="mdi:timer-outline",
        device_class="duration",
        state_class="total",
        attributes=attributes,
    )

    latest_duration_seconds = _number(latest.get("duration_seconds"))
    if latest_duration_seconds is not None:
        _add(
            out,
            key=f"{prefix}:duration",
            name=f"{sport} Dauer",
            value=_rounded(latest_duration_seconds / 60),
            unit="min",
            icon="mdi:timer-outline",
            device_class="duration",
            state_class="measurement",
            attributes=attributes,
        )

    latest_distance = _number(latest.get("distance_km"))
    total_distance = sum(_number(item.get("distance_km")) or 0 for item in workouts)
    if latest_distance is not None:
        _add(
            out,
            key=f"{prefix}:distance",
            name=f"{sport} Distanz",
            value=_rounded(latest_distance),
            unit="km",
            icon="mdi:map-marker-distance",
            device_class="distance",
            state_class="measurement",
            attributes=attributes,
        )
    if total_distance > 0:
        _add(
            out,
            key=f"{prefix}:total_distance",
            name=f"{sport} Gesamtdistanz",
            value=_rounded(total_distance),
            unit="km",
            icon="mdi:map-marker-distance",
            device_class="distance",
            state_class="total",
            attributes=attributes,
        )

    if latest_distance and latest_distance > 0 and latest_duration_seconds:
        duration_minutes = latest_duration_seconds / 60
        if _supports_pace(sport):
            pace = duration_minutes / latest_distance
            _add(
                out,
                key=f"{prefix}:pace",
                name=f"{sport} Pace",
                value=_rounded(pace),
                unit="min/km",
                icon="mdi:run-fast",
                state_class="measurement",
                attributes={
                    **attributes,
                    "formatted_pace": _formatted_pace(pace),
                },
            )
        _add(
            out,
            key=f"{prefix}:speed",
            name=f"{sport} Geschwindigkeit",
            value=_rounded(latest_distance / (latest_duration_seconds / 3600)),
            unit="km/h",
            icon="mdi:speedometer",
            device_class="speed",
            state_class="measurement",
            attributes=attributes,
        )

    _add_latest_number(
        out,
        latest,
        field="energy_kcal",
        key=f"{prefix}:energy",
        name=f"{sport} Energie",
        unit="kcal",
        icon="mdi:fire",
        device_class="energy",
        state_class="total",
        attributes=attributes,
    )
    _add_latest_number(
        out,
        latest,
        field="average_heart_rate",
        key=f"{prefix}:average_heart_rate",
        name=f"{sport} Durchschnittspuls",
        unit="bpm",
        icon="mdi:heart-pulse",
        attributes=attributes,
    )
    _add_latest_number(
        out,
        latest,
        field="max_heart_rate",
        key=f"{prefix}:max_heart_rate",
        name=f"{sport} Maximalpuls",
        unit="bpm",
        icon="mdi:heart-flash",
        attributes=attributes,
    )

    for field, suffix, label, icon_name, unit, device_class in (
        ("exercise_count", "exercises", "Übungen", "mdi:dumbbell", "", None),
        ("set_count", "sets", "Sätze", "mdi:format-list-numbered", "", None),
        ("volume_kg", "volume", "Volumen", "mdi:weight-kilogram", "kg", "weight"),
        ("max_weight_kg", "max_weight", "Maximalgewicht", "mdi:weight-lifter", "kg", "weight"),
        ("personal_records", "personal_records", "Persönliche Rekorde", "mdi:trophy", "", None),
    ):
        _add_latest_number(
            out,
            latest,
            field=field,
            key=f"{prefix}:{suffix}",
            name=f"{sport} {label}",
            unit=unit,
            icon=icon_name,
            device_class=device_class,
            attributes=attributes,
        )
    return out


def _exercise_metrics(workouts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    aggregates: dict[str, dict[str, Any]] = {}
    for workout in workouts:
        workout_time = _parse_datetime(workout.get("start_time") or workout.get("start"))
        workout_id = str(workout.get("id") or workout.get("workout_id") or _workout_timestamp(workout))
        for exercise in workout.get("exercises") or []:
            if not isinstance(exercise, dict):
                continue
            name = str(exercise.get("name") or exercise.get("title") or "Übung").strip()
            identity = str(exercise.get("catalog_id") or exercise.get("catalogId") or "").strip()
            exercise_key = _slug(identity or name)
            if not exercise_key:
                continue
            sets = [item for item in exercise.get("sets") or [] if isinstance(item, dict)]
            weights = [
                value
                for item in sets
                if (value := _number(item.get("weight_kg"))) is not None
            ]
            reps = [
                value
                for item in sets
                if (value := _number(item.get("reps"))) is not None
            ]
            rpes = [
                value
                for item in sets
                if (value := _number(item.get("rpe"))) is not None
            ]
            volumes = []
            for item in sets:
                volume = _number(item.get("volume_kg"))
                if volume is None:
                    weight = _number(item.get("weight_kg"))
                    repetitions = _number(item.get("reps"))
                    volume = weight * repetitions if weight is not None and repetitions is not None else None
                if volume is not None:
                    volumes.append(volume)

            aggregate = aggregates.setdefault(
                exercise_key,
                {
                    "name": name,
                    "category": exercise.get("category") or "",
                    "sessions": set(),
                    "best_weight": None,
                    "total_volume": 0.0,
                    "personal_records": 0,
                    "latest_time": None,
                    "latest": {},
                },
            )
            aggregate["sessions"].add(workout_id)
            if weights:
                aggregate["best_weight"] = max(
                    float(aggregate["best_weight"] or 0),
                    max(weights),
                )
            aggregate["total_volume"] += sum(volumes)
            aggregate["personal_records"] += sum(
                1 for item in sets if item.get("is_personal_record")
            )
            if aggregate["latest_time"] is None or (
                workout_time is not None and workout_time > aggregate["latest_time"]
            ):
                aggregate["latest_time"] = workout_time
                aggregate["name"] = name
                aggregate["category"] = exercise.get("category") or aggregate["category"]
                aggregate["latest"] = {
                    "set_count": len(sets),
                    "reps": sum(reps),
                    "weight": max(weights) if weights else None,
                    "volume": sum(volumes),
                    "rpe": sum(rpes) / len(rpes) if rpes else None,
                    "duration_seconds": _number(exercise.get("duration_seconds")),
                    "device_settings": exercise.get("device_settings") or {},
                    "workout_title": workout.get("title") or workout.get("sport"),
                    "workout_id": workout_id,
                    "source": workout.get("source"),
                }

    out: list[dict[str, Any]] = []
    for exercise_key, aggregate in sorted(
        aggregates.items(), key=lambda item: str(item[1].get("name") or "")
    ):
        name = str(aggregate["name"])
        prefix = f"exercise:{exercise_key}"
        latest = aggregate["latest"]
        attributes = {
            "exercise": name,
            "category": aggregate["category"],
            "last_workout": latest.get("workout_title"),
            "last_workout_id": latest.get("workout_id"),
            "source": latest.get("source"),
            "device_settings": latest.get("device_settings") or {},
        }
        _add(
            out,
            key=f"{prefix}:latest",
            name=f"{name} Letztes Training",
            value=aggregate["latest_time"],
            icon="mdi:weight-lifter",
            device_class="timestamp",
            attributes=attributes,
        )
        _add(
            out,
            key=f"{prefix}:sessions",
            name=f"{name} Trainings",
            value=len(aggregate["sessions"]),
            icon="mdi:counter",
            state_class="total",
            attributes=attributes,
        )
        for field, suffix, label, icon, unit, device_class in (
            ("set_count", "sets", "Sätze", "mdi:format-list-numbered", "", None),
            ("reps", "reps", "Wiederholungen", "mdi:repeat", "", None),
            ("weight", "weight", "Letztes Gewicht", "mdi:weight-kilogram", "kg", "weight"),
            ("volume", "volume", "Letztes Volumen", "mdi:weight-kilogram", "kg", "weight"),
            ("rpe", "rpe", "RPE", "mdi:gauge", "", None),
        ):
            _add(
                out,
                key=f"{prefix}:{suffix}",
                name=f"{name} {label}",
                value=_rounded(latest.get(field)),
                unit=unit,
                icon=icon,
                device_class=device_class,
                state_class="measurement",
                attributes=attributes,
            )
        _add(
            out,
            key=f"{prefix}:best_weight",
            name=f"{name} Bestgewicht",
            value=_rounded(aggregate["best_weight"]),
            unit="kg",
            icon="mdi:trophy",
            device_class="weight",
            state_class="measurement",
            attributes=attributes,
        )
        _add(
            out,
            key=f"{prefix}:total_volume",
            name=f"{name} Gesamtvolumen",
            value=_rounded(aggregate["total_volume"]),
            unit="kg",
            icon="mdi:weight-kilogram",
            device_class="weight",
            state_class="total",
            attributes=attributes,
        )
        if aggregate["personal_records"]:
            _add(
                out,
                key=f"{prefix}:personal_records",
                name=f"{name} Persönliche Rekorde",
                value=aggregate["personal_records"],
                icon="mdi:trophy-award",
                state_class="total",
                attributes=attributes,
            )
        duration_seconds = latest.get("duration_seconds")
        if duration_seconds is not None:
            _add(
                out,
                key=f"{prefix}:duration",
                name=f"{name} Dauer",
                value=_rounded(float(duration_seconds) / 60),
                unit="min",
                icon="mdi:timer-outline",
                device_class="duration",
                state_class="measurement",
                attributes=attributes,
            )
    return out


def _add_latest_number(
    out: list[dict[str, Any]],
    source: dict[str, Any],
    *,
    field: str,
    key: str,
    name: str,
    unit: str,
    icon: str,
    attributes: dict[str, Any],
    device_class: str | None = None,
    state_class: str = "measurement",
) -> None:
    _add(
        out,
        key=key,
        name=name,
        value=_rounded(_number(source.get(field))),
        unit=unit,
        icon=icon,
        device_class=device_class,
        state_class=state_class,
        attributes=attributes,
    )


def _add(
    out: list[dict[str, Any]],
    *,
    key: str,
    name: str,
    value: Any,
    icon: str,
    unit: str = "",
    device_class: str | None = None,
    state_class: str | None = None,
    attributes: dict[str, Any] | None = None,
) -> None:
    if value is None:
        return
    out.append(
        {
            "key": key,
            "name": name,
            "value": value,
            "unit": unit,
            "icon": icon,
            "device_class": device_class,
            "state_class": state_class,
            "attributes": attributes or {},
        }
    )


def _workout_attributes(workout: dict[str, Any]) -> dict[str, Any]:
    return {
        "workout_id": workout.get("id") or workout.get("workout_id"),
        "title": workout.get("title"),
        "sport": workout.get("sport"),
        "source": workout.get("source"),
        "sources": workout.get("sources") or [],
        "start": workout.get("start_time") or workout.get("start"),
        "end": workout.get("end_time") or workout.get("end"),
    }


def _sport_name(workout: dict[str, Any]) -> str:
    value = str(workout.get("sport") or workout.get("title") or "Workout").strip()
    normalized = _slug(value)
    localized = {
        "strength": "Krafttraining",
        "strength_training": "Krafttraining",
        "weight_training": "Krafttraining",
        "krafttraining": "Krafttraining",
        "run": "Laufen",
        "running": "Laufen",
        "laufen": "Laufen",
        "cycling": "Radfahren",
        "bike": "Radfahren",
        "radfahren": "Radfahren",
        "walking": "Gehen",
        "walk": "Gehen",
        "gehen": "Gehen",
        "bouldering": "Bouldern",
        "bouldern": "Bouldern",
    }
    return localized.get(normalized, value.replace("_", " ").strip() or "Workout")


def _sport_icon(sport: str) -> str:
    key = _slug(sport)
    if any(item in key for item in ("lauf", "run", "jog")):
        return "mdi:run"
    if any(item in key for item in ("rad", "cycling", "bike")):
        return "mdi:bike"
    if any(item in key for item in ("strength", "kraft", "gym")):
        return "mdi:dumbbell"
    if any(item in key for item in ("walk", "geh", "wander")):
        return "mdi:walk"
    if any(item in key for item in ("boulder", "climb", "kletter")):
        return "mdi:carabiner"
    return "mdi:arm-flex"


def _supports_pace(sport: str) -> bool:
    key = _slug(sport)
    return any(item in key for item in ("lauf", "run", "jog", "walk", "geh", "wander"))


def _workout_timestamp(workout: dict[str, Any]) -> float:
    value = _parse_datetime(workout.get("start_time") or workout.get("start"))
    return value.timestamp() if value else 0.0


def _parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    else:
        text = str(value or "").strip()
        if not text:
            return None
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _number(value: Any) -> float | None:
    if value in (None, "") or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _rounded(value: Any) -> float | None:
    number = _number(value)
    return round(number, 3) if number is not None else None


def _formatted_pace(value: float) -> str:
    minutes = int(value)
    seconds = round((value - minutes) * 60)
    if seconds == 60:
        minutes += 1
        seconds = 0
    return f"{minutes}:{seconds:02d} min/km"


def _slug(value: Any) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    ascii_text = text.encode("ascii", "ignore").decode("ascii").lower()
    return re.sub(r"[^a-z0-9]+", "_", ascii_text).strip("_")
