"""Build stable Home Assistant sensor descriptions from bridge workouts.

Every sport gets its own device, so the names here no longer repeat it: the
device is called "Peter Run", the sensor on it simply "Distance". They are
English and fixed, like every other device and entity name in this
integration — a name that travels into an entity ID must not move with the
interface language.
"""

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
    # Woher die Einheiten dieser Sportart stammen. Der Sensor entscheidet
    # daran, auf welches Geraet er gehoert: Krafttraining aus GymPit liegt
    # beim Kraftraum, alles andere bei seiner Sportart.
    sources = sorted({
        source
        for workout in workouts
        for source in ([workout.get("source")] + list(workout.get("sources") or []))
        if source
    })
    out: list[dict[str, Any]] = []

    def add(**kwargs: Any) -> None:
        _add(out, sport=sport, sport_key=sport_key, sources=sources, **kwargs)

    add(
        key=f"{prefix}:latest",
        name="Last workout",
        value=_parse_datetime(latest.get("start_time") or latest.get("start")),
        icon=icon,
        device_class="timestamp",
        attributes=attributes,
    )
    add(
        key=f"{prefix}:count",
        name="Sessions",
        value=len(workouts),
        icon="mdi:counter",
        state_class="total",
        attributes=attributes,
    )

    total_duration_seconds = sum(_number(item.get("duration_seconds")) or 0 for item in workouts)
    add(
        key=f"{prefix}:total_duration",
        name="Total time",
        value=_rounded(total_duration_seconds / 3600),
        unit="h",
        icon="mdi:timer-outline",
        device_class="duration",
        state_class="total",
        attributes=attributes,
    )

    latest_duration_seconds = _number(latest.get("duration_seconds"))
    if latest_duration_seconds is not None:
        add(
            key=f"{prefix}:duration",
            name="Duration",
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
        add(
            key=f"{prefix}:distance",
            name="Distance",
            value=_rounded(latest_distance),
            unit="km",
            icon="mdi:map-marker-distance",
            device_class="distance",
            state_class="measurement",
            attributes=attributes,
        )
    if total_distance > 0:
        add(
            key=f"{prefix}:total_distance",
            name="Total distance",
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
            add(
                key=f"{prefix}:pace",
                name="Pace",
                value=_rounded(pace),
                unit="min/km",
                icon="mdi:run-fast",
                state_class="measurement",
                attributes={
                    **attributes,
                    "formatted_pace": _formatted_pace(pace),
                },
            )
        add(
            key=f"{prefix}:speed",
            name="Speed",
            value=_rounded(latest_distance / (latest_duration_seconds / 3600)),
            unit="km/h",
            icon="mdi:speedometer",
            device_class="speed",
            state_class="measurement",
            attributes=attributes,
        )

    for field, suffix, label, icon_name, unit, device_class, state_class in (
        ("energy_kcal", "energy", "Energy", "mdi:fire", "kcal", "energy", "total"),
        ("average_heart_rate", "average_heart_rate", "Average heart rate",
         "mdi:heart-pulse", "bpm", None, "measurement"),
        ("max_heart_rate", "max_heart_rate", "Maximum heart rate",
         "mdi:heart-flash", "bpm", None, "measurement"),
        ("exercise_count", "exercises", "Exercises", "mdi:dumbbell", "", None, "measurement"),
        ("set_count", "sets", "Sets", "mdi:format-list-numbered", "", None, "measurement"),
        ("volume_kg", "volume", "Volume", "mdi:weight-kilogram", "kg", "weight", "measurement"),
        ("max_weight_kg", "max_weight", "Top weight", "mdi:weight-lifter", "kg", "weight", "measurement"),
        ("personal_records", "personal_records", "Personal records", "mdi:trophy", "", None, "measurement"),
    ):
        add(
            key=f"{prefix}:{suffix}",
            name=label,
            value=_rounded(_number(latest.get(field))),
            unit=unit,
            icon=icon_name,
            device_class=device_class,
            state_class=state_class,
            attributes=attributes,
        )
    return out


def exercise_name(exercise: dict[str, Any]) -> str:
    """Wie die Uebung heisst."""
    return str(exercise.get("name") or exercise.get("title") or "Übung").strip()


def exercise_identity(exercise: dict[str, Any]) -> str:
    """Der stabile Schluessel einer Uebung.

    Der Katalogeintrag zaehlt, nicht der Name: dieselbe Maschine unter zwei
    Schreibweisen waere sonst zweimal da. Ohne Katalog bleibt der Name.
    """
    identity = str(exercise.get("catalog_id") or exercise.get("catalogId") or "").strip()
    return _slug(identity or exercise_name(exercise))


def exercise_volume(exercise: dict[str, Any]) -> float:
    """Bewegtes Gewicht einer Uebung in einer Einheit: Summe aus Kilo × Wiederholungen."""
    total = 0.0
    for item in exercise.get("sets") or []:
        if not isinstance(item, dict):
            continue
        volume = _number(item.get("volume_kg"))
        if volume is None:
            weight = _number(item.get("weight_kg"))
            repetitions = _number(item.get("reps"))
            volume = weight * repetitions if weight is not None and repetitions is not None else None
        if volume is not None:
            total += volume
    return total


def _exercise_metrics(workouts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """What only the whole history knows about an exercise.

    The last weight, the last repetitions, the last set — those arrive as their
    own values from GymPit and become their own sensors. Duplicating them here
    is what put every machine into two places at once.

    What is left is what a single value cannot say: how often the exercise was
    trained, the heaviest weight ever moved, the volume of all sessions, the
    number of personal records, and when it last happened.
    """
    aggregates: dict[str, dict[str, Any]] = {}
    for workout in workouts:
        workout_time = _parse_datetime(workout.get("start_time") or workout.get("start"))
        workout_id = str(workout.get("id") or workout.get("workout_id") or _workout_timestamp(workout))
        for exercise in workout.get("exercises") or []:
            if not isinstance(exercise, dict):
                continue
            name = exercise_name(exercise)
            exercise_key = exercise_identity(exercise)
            if not exercise_key:
                continue
            sets = [item for item in exercise.get("sets") or [] if isinstance(item, dict)]
            weights = [
                value
                for item in sets
                if (value := _number(item.get("weight_kg"))) is not None
            ]
            volumes = [exercise_volume(exercise)]

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

        def add(**kwargs: Any) -> None:
            # Die Uebung steht im Namen, nicht im Geraet: alle Uebungen teilen
            # sich das eine Kraftraum-Geraet.
            _add(out, exercise=name, exercise_key=exercise_key, **kwargs)

        add(
            key=f"{prefix}:latest",
            name=f"{name} Last workout",
            value=aggregate["latest_time"],
            icon="mdi:weight-lifter",
            device_class="timestamp",
            attributes=attributes,
        )
        add(
            key=f"{prefix}:sessions",
            name=f"{name} Sessions",
            value=len(aggregate["sessions"]),
            icon="mdi:counter",
            state_class="total",
            attributes=attributes,
        )
        add(
            key=f"{prefix}:best_weight",
            name=f"{name} Best weight",
            value=_rounded(aggregate["best_weight"]),
            unit="kg",
            icon="mdi:trophy",
            device_class="weight",
            state_class="measurement",
            attributes=attributes,
        )
        add(
            key=f"{prefix}:total_volume",
            name=f"{name} Total volume",
            value=_rounded(aggregate["total_volume"]),
            unit="kg",
            icon="mdi:weight-kilogram",
            device_class="weight",
            state_class="total",
            attributes=attributes,
        )
        if aggregate["personal_records"]:
            add(
                key=f"{prefix}:personal_records",
                name=f"{name} Personal records",
                value=aggregate["personal_records"],
                icon="mdi:trophy-award",
                state_class="total",
                attributes=attributes,
            )
    return out


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
    sport: str | None = None,
    sport_key: str | None = None,
    sources: list[str] | None = None,
    exercise: str | None = None,
    exercise_key: str | None = None,
) -> None:
    if value is None:
        return
    descriptor: dict[str, Any] = {
        "key": key,
        "name": name,
        "value": value,
        "unit": unit,
        "icon": icon,
        "device_class": device_class,
        "state_class": state_class,
        "attributes": attributes or {},
    }
    # Woran der Sensor haengt. Ohne diese Angaben muesste der Sensor den
    # Schluessel zerlegen, um sein Geraet zu finden — und jede Aenderung am
    # Schluesselformat wuerde still die Zuordnung kippen.
    if sport is not None:
        descriptor |= {"sport": sport, "sport_key": sport_key, "sources": sources or []}
    if exercise is not None:
        descriptor |= {"exercise": exercise, "exercise_key": exercise_key}
    out.append(descriptor)


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


# Welche Schreibweise welche Sportart meint.
#
# Die Sportart kommt als *uebersetzter Anzeigename* herein: die App schickt,
# was sie auf dem Bildschirm zeigt, also „Laufen" auf Deutsch und „Running" auf
# Englisch — und je nach Quelle auch „Outdoor Run" oder „Laufen im Freien".
# Verglichen wurde bisher auf genaue Gleichheit, und damit zerfiel eine
# Sportart in mehrere: „Peter Run" zaehlte nur die Einheiten, die zufaellig
# genau „Laufen" hiessen, der Rest lag daneben unter eigenem Namen.
#
# Erkannt wird deshalb am Wortanfang, Wort fuer Wort — nicht irgendwo in der
# Zeichenkette. „t-rad-itional strength training" ist kein Radfahren.
SPORT_ALIASES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("Gehen", ("geh", "walk", "spazier")),
    ("Wandern", ("wander", "hike", "hiking", "trek")),
    ("Laufen", ("lauf", "run", "jog", "trail", "sprint", "marathon")),
    ("Radfahren", ("rad", "cycl", "bike", "velo", "spinning")),
    ("Schwimmen", ("schwimm", "swim")),
    ("Krafttraining", ("kraft", "strength", "hantel", "gym")),
    ("Rudern", ("ruder", "row")),
    ("Yoga", ("yoga",)),
    ("Pilates", ("pilates",)),
    ("Klettern", ("klett", "climb", "boulder")),
    ("HIIT", ("hiit", "intervall", "interval")),
)


def _sport_name(workout: dict[str, Any]) -> str:
    """Der Name, unter dem eine Sportart gefuehrt wird.

    Alles, was dieselbe Sportart meint, muss hier denselben Namen bekommen —
    er ist der Schluessel, unter dem die Einheiten zusammenkommen, und aus ihm
    entsteht das Geraet.
    """
    value = str(workout.get("sport") or workout.get("title") or "Workout").strip()
    normalized = _slug(value)
    if not normalized:
        return "Workout"
    words = normalized.split("_")
    for name, parts in SPORT_ALIASES:
        if any(word.startswith(part) for word in words for part in parts):
            return name
    return value.replace("_", " ").strip() or "Workout"


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


# Public names for the same helpers, so other modules in this package do not
# have to reach for the underscore versions.
sport_name = _sport_name
slug = _slug
