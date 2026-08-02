"""Build stable geolocation descriptions from workout routes."""

from __future__ import annotations

import hashlib
from typing import Any


def build_route_points(
    workouts: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """Return every valid route coordinate, keyed by workout and point index."""
    result: dict[str, dict[str, Any]] = {}
    for workout in workouts:
        if not isinstance(workout, dict):
            continue
        route = workout.get("route") or []
        if not isinstance(route, list) or not route:
            continue

        workout_id = str(
            workout.get("id")
            or workout.get("workout_id")
            or _fallback_workout_id(workout)
        )
        sport = str(workout.get("sport") or workout.get("title") or "Workout")
        start = workout.get("start_time") or workout.get("start")
        workout_date = str(start or "").strip()[:10]
        name_prefix = f"{sport} {workout_date}" if workout_date else sport
        point_count = len(route)
        for index, point in enumerate(route):
            if not isinstance(point, dict):
                continue
            latitude = _coordinate(point.get("latitude"), minimum=-90, maximum=90)
            longitude = _coordinate(point.get("longitude"), minimum=-180, maximum=180)
            if latitude is None or longitude is None:
                continue

            key = f"{workout_id}:{index}"
            result[key] = {
                "key": key,
                "workout_id": workout_id,
                "name": f"{name_prefix} route point {index + 1}",
                "sport": sport,
                "title": workout.get("title"),
                "source": workout.get("source"),
                "sources": workout.get("sources") or [],
                "start": start,
                "end": workout.get("end_time") or workout.get("end"),
                "point_number": index + 1,
                "point_count": point_count,
                "latitude": latitude,
                "longitude": longitude,
                "elevation": _number(point.get("elevation")),
                "timestamp": point.get("timestamp"),
                "heart_rate": _number(point.get("heart_rate")),
            }
    return result


def _fallback_workout_id(workout: dict[str, Any]) -> str:
    """Create a deterministic identity if an old workout has no ID."""
    identity = "|".join(
        str(workout.get(field) or "")
        for field in ("source", "sport", "title", "start_time", "start")
    )
    return f"legacy-{hashlib.sha256(identity.encode()).hexdigest()[:20]}"


def _coordinate(value: Any, *, minimum: float, maximum: float) -> float | None:
    number = _number(value)
    if number is None or not minimum <= number <= maximum:
        return None
    return number


def _number(value: Any) -> float | None:
    if value in (None, "") or isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None
