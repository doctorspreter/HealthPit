"""Link workouts that describe the same session across sources.

Ported from the bridge's SQLite store so webhook mode behaves the same way.
The Hevy branch is gone — nothing pulls Hevy without a bridge — but the part
that matters for a phone stays: Apple Health and GymPit both record the same
gym session, and the user must see one workout instead of two.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

SOURCE_PRIORITY = {
    "apple_health": 0,
    "gympit": 1,
    "garmin": 2,
    "manual": 3,
    "gpx": 4,
    "tcx": 5,
}
SOURCE_ORDER = ["apple_health", "gympit", "garmin", "manual", "gpx", "tcx"]

# Two recordings of one session rarely start at the same second; the bridge
# allowed twenty minutes of drift and bucketed on the same width.
MATCH_WINDOW_SECONDS = 20 * 60


def unify_workouts(
    imported: list[dict[str, Any]],
    overrides: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Return one merged workout per session, newest first."""
    overrides = overrides or []
    forced_merges = {
        _pair_key(row["primary"], row["linked"])
        for row in overrides
        if row.get("action") == "merge"
    }
    forced_separates = {
        _pair_key(row["primary"], row["linked"])
        for row in overrides
        if row.get("action") == "separate"
    }

    out: list[dict[str, Any]] = []
    for group in _group_imported_workouts(imported, forced_merges, forced_separates):
        out.append(_merge_workout(group))

    out = _apply_forced_import_merges(out, forced_merges)
    out = _dedupe_unified_workouts(out, forced_separates)
    out.sort(key=lambda item: item.get("start_time") or "", reverse=True)
    return out


def _group_imported_workouts(
    items: list[dict[str, Any]],
    forced_merges: set[tuple[str, str]],
    forced_separates: set[tuple[str, str]],
) -> list[list[dict[str, Any]]]:
    if not items:
        return []

    remaining = {_imported_key(item): item for item in items}
    buckets: dict[tuple[str, int], list[str]] = {}
    cross_device_buckets: dict[int, list[str]] = {}
    for key, item in remaining.items():
        bucket = _import_time_bucket(item)
        if bucket is not None:
            buckets.setdefault((str(item.get("device_id") or ""), bucket), []).append(key)
            if item.get("source") in {"apple_health", "gympit"}:
                cross_device_buckets.setdefault(bucket, []).append(key)

    groups: list[list[dict[str, Any]]] = []
    for key in [_imported_key(item) for item in items]:
        item = remaining.pop(key, None)
        if not item:
            continue
        group = [item]
        for other_key in _candidate_import_keys(
            item, remaining, buckets, cross_device_buckets, forced_merges
        ):
            other = remaining.get(other_key)
            if not other:
                continue
            pair = _pair_key(_workout_source_key(item), _workout_source_key(other))
            if pair in forced_separates:
                continue
            if pair in forced_merges or _is_same_imported_workout(item, other):
                group.append(remaining.pop(other_key))
        groups.append(group)
    return groups


def _candidate_import_keys(
    item: dict[str, Any],
    remaining: dict[str, dict[str, Any]],
    buckets: dict[tuple[str, int], list[str]],
    cross_device_buckets: dict[int, list[str]],
    forced_merges: set[tuple[str, str]],
) -> list[str]:
    keys: set[str] = set()
    bucket = _import_time_bucket(item)
    if bucket is not None:
        device_id = str(item.get("device_id") or "")
        # A session can straddle a bucket boundary, so look at the neighbours.
        for offset in (-1, 0, 1):
            keys.update(buckets.get((device_id, bucket + offset), []))
            if item.get("source") in {"apple_health", "gympit"}:
                keys.update(
                    key
                    for key in cross_device_buckets.get(bucket + offset, [])
                    if _is_apple_health_gympit_pair(item, remaining.get(key, {}))
                )
    if forced_merges:
        item_key = _workout_source_key(item)
        keys.update(
            key
            for key, other in remaining.items()
            if _pair_key(item_key, _workout_source_key(other)) in forced_merges
        )
    keys.discard(_imported_key(item))
    return [key for key in keys if key in remaining]


def _is_apple_health_gympit_pair(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return {left.get("source"), right.get("source")} == {"apple_health", "gympit"}


def _is_same_imported_workout(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if left.get("source") == right.get("source"):
        return False

    left_start = _import_timestamp(left.get("start_time"))
    right_start = _import_timestamp(right.get("start_time"))
    if left_start is None or right_start is None:
        return False
    if abs(left_start - right_start) > MATCH_WINDOW_SECONDS:
        return False

    left_duration = float(left.get("duration_seconds") or 0)
    right_duration = float(right.get("duration_seconds") or 0)
    if left_duration and right_duration:
        allowed = max(15 * 60, max(left_duration, right_duration) * 0.35)
        if abs(left_duration - right_duration) > allowed:
            return False

    left_distance = left.get("distance_km")
    right_distance = right.get("distance_km")
    if left_distance is not None and right_distance is not None:
        allowed = max(0.75, max(float(left_distance), float(right_distance)) * 0.3)
        if abs(float(left_distance) - float(right_distance)) > allowed:
            return False

    return True


def _import_time_bucket(item: dict[str, Any]) -> int | None:
    timestamp = _import_timestamp(item.get("start_time"))
    if timestamp is None:
        return None
    return int(timestamp // MATCH_WINDOW_SECONDS)


def _import_timestamp(value: Any) -> float | None:
    parsed = _parse_dt(value)
    return parsed.timestamp() if parsed else None


def _merge_workout(imported: list[dict[str, Any]]) -> dict[str, Any]:
    imported = [item for item in imported if item]
    primary = _best_imported_workout(imported) or {}
    detail_owner = next((item for item in imported if item.get("exercises")), None) or primary
    route_owner = max(
        imported,
        key=lambda item: int(item.get("route_points") or len(item.get("route") or [])),
        default=None,
    )
    sources = sorted(
        {item.get("source") for item in imported if item.get("source")},
        key=lambda value: SOURCE_ORDER.index(value) if value in SOURCE_ORDER else 99,
    )

    start = primary.get("start_time")
    end = primary.get("end_time") or start
    workout_id = _unified_id(imported)
    title = primary.get("title") or primary.get("sport") or "Workout"
    sport = primary.get("sport") or primary.get("title") or "Workout"

    merged = {
        "device_id": primary.get("device_id", ""),
        "workout_id": workout_id,
        "id": workout_id,
        "source": "merged" if len(sources) > 1 else (sources[0] if sources else "bridge"),
        "sources": sources,
        "source_ids": {
            item.get("source"): item.get("workout_id")
            for item in imported
            if item.get("source") and item.get("workout_id")
        },
        "sport": sport,
        # Die sprachneutrale Sportart geht mit. Ohne sie faellt ein
        # zusammengefuehrtes Training zurueck auf das Erraten aus dem
        # uebersetzten Namen — und landete unter einer anderen Sportart als
        # dieselbe Einheit ohne Zusammenfuehrung.
        "sport_type": _first_present(imported, "sport_type"),
        "title": title,
        "start_time": start,
        "start": start,
        "end_time": end,
        "end": end,
        "duration_seconds": _first_present(imported, "duration_seconds") or 0,
        "distance_km": _first_present(imported, "distance_km"),
        "energy_kcal": _first_present(imported, "energy_kcal"),
        "average_heart_rate": _first_present(imported, "average_heart_rate"),
        "max_heart_rate": _first_present(imported, "max_heart_rate"),
        "notes": "\n\n".join(
            item.get("notes") or "" for item in imported if item.get("notes")
        ),
        "weather": _first_present(imported, "weather"),
        "injury": _first_present(imported, "injury"),
        "exercises": detail_owner.get("exercises", []),
        "exercise_count": detail_owner.get("exercise_count", 0),
        "set_count": detail_owner.get("set_count", 0),
        "volume_kg": detail_owner.get("volume_kg", 0),
        "max_weight_kg": detail_owner.get("max_weight_kg"),
        "best_set_volume_kg": detail_owner.get("best_set_volume_kg"),
        "personal_records": detail_owner.get("personal_records", 0),
        "route_points": route_owner.get("route_points", 0) if route_owner else 0,
        "route_points_total": (
            route_owner.get("route_points_total") or route_owner.get("route_points", 0)
            if route_owner
            else 0
        ),
        "route": route_owner.get("route", []) if route_owner else [],
        "updated_at": max(
            (item.get("updated_at") or "" for item in imported), default=""
        ),
        "stats": [],
    }
    if int(detail_owner.get("set_count") or 0) > 0:
        merged["stats"].extend(
            [
                {
                    "label": "Übungen",
                    "value": detail_owner.get("exercise_count"),
                    "systemImage": "dumbbell",
                },
                {
                    "label": "Sätze",
                    "value": detail_owner.get("set_count"),
                    "systemImage": "list.number",
                },
                {
                    "label": "Volumen",
                    "value": f"{round(float(detail_owner.get('volume_kg') or 0))} kg",
                    "systemImage": "scalemass",
                },
            ]
        )
    merged["stats"].extend(_base_workout_stats(primary))
    merged["stats"] = _dedupe_stats(merged["stats"])
    return merged


def _apply_forced_import_merges(
    workouts: list[dict[str, Any]],
    forced_merges: set[tuple[str, str]],
) -> list[dict[str, Any]]:
    if not forced_merges:
        return workouts
    out: list[dict[str, Any]] = []
    consumed: set[int] = set()
    for index, workout in enumerate(workouts):
        if index in consumed:
            continue
        group = [workout]
        keys = _merged_source_keys(workout)
        changed = True
        while changed:
            changed = False
            for other_index, other in enumerate(workouts):
                if other_index == index or other_index in consumed:
                    continue
                other_keys = _merged_source_keys(other)
                if any(
                    _pair_key(left, right) in forced_merges
                    for left in keys
                    for right in other_keys
                ):
                    group.append(other)
                    keys.update(other_keys)
                    consumed.add(other_index)
                    changed = True
        out.append(workout if len(group) == 1 else _merge_already_merged(group))
    return out


def _dedupe_unified_workouts(
    workouts: list[dict[str, Any]],
    forced_separates: set[tuple[str, str]],
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    consumed: set[int] = set()
    for index, workout in enumerate(workouts):
        if index in consumed:
            continue
        group = [workout]
        keys = _merged_source_keys(workout)
        changed = True
        while changed:
            changed = False
            for other_index, other in enumerate(workouts):
                if other_index == index or other_index in consumed:
                    continue
                other_keys = _merged_source_keys(other)
                if _has_forced_separate(keys, other_keys, forced_separates):
                    continue
                if keys.intersection(other_keys):
                    group.append(other)
                    keys.update(other_keys)
                    consumed.add(other_index)
                    changed = True
        out.append(group[0] if len(group) == 1 else _merge_already_merged(group))
    return out


def _merge_already_merged(items: list[dict[str, Any]]) -> dict[str, Any]:
    imported: list[dict[str, Any]] = []
    for item in items:
        source_ids = item.get("source_ids") or {}
        if source_ids:
            for source, workout_id in source_ids.items():
                imported.append(_import_from_merged_item(item, source, workout_id))
        elif item.get("source"):
            imported.append(
                _import_from_merged_item(item, item.get("source"), item.get("workout_id"))
            )
    return _merge_workout(imported)


def _import_from_merged_item(
    item: dict[str, Any],
    source: Any,
    workout_id: Any,
) -> dict[str, Any]:
    return {
        "device_id": item.get("device_id", ""),
        "workout_id": workout_id,
        "source": source,
        "sport": item.get("sport"),
        "title": item.get("title"),
        "start_time": item.get("start_time"),
        "end_time": item.get("end_time"),
        "duration_seconds": item.get("duration_seconds"),
        "distance_km": item.get("distance_km"),
        "energy_kcal": item.get("energy_kcal"),
        "average_heart_rate": item.get("average_heart_rate"),
        "max_heart_rate": item.get("max_heart_rate"),
        "notes": item.get("notes", ""),
        "weather": item.get("weather"),
        "injury": item.get("injury"),
        "exercises": item.get("exercises", []),
        "exercise_count": item.get("exercise_count", 0),
        "set_count": item.get("set_count", 0),
        "volume_kg": item.get("volume_kg", 0),
        "max_weight_kg": item.get("max_weight_kg"),
        "best_set_volume_kg": item.get("best_set_volume_kg"),
        "personal_records": item.get("personal_records", 0),
        "route_points": item.get("route_points", 0),
        "route_points_total": item.get("route_points_total", item.get("route_points", 0)),
        "route": item.get("route", []),
        "updated_at": item.get("updated_at", ""),
    }


def _has_forced_separate(
    left_keys: set[str],
    right_keys: set[str],
    forced_separates: set[tuple[str, str]],
) -> bool:
    return any(
        _pair_key(left, right) in forced_separates
        for left in left_keys
        for right in right_keys
    )


def _merged_source_keys(workout: dict[str, Any]) -> set[str]:
    keys = set()
    for source, workout_id in (workout.get("source_ids") or {}).items():
        if source and workout_id:
            keys.add(_source_key(source, workout_id))
    if workout.get("source") and workout.get("workout_id"):
        keys.add(_source_key(workout["source"], workout["workout_id"]))
    return keys


def _best_imported_workout(items: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not items:
        return None
    return sorted(
        items,
        key=lambda item: (
            SOURCE_PRIORITY.get(item.get("source"), 9),
            -int(item.get("route_points") or len(item.get("route") or [])),
        ),
    )[0]


def _unified_id(imported: list[dict[str, Any]]) -> str:
    parts = [
        f"{item.get('source')}-{item.get('workout_id')}"
        for item in imported
        if item.get("workout_id")
    ]
    if len(parts) > 1:
        return "merged-" + "-".join(parts)
    return parts[0] if parts else "workout"


def _imported_key(item: dict[str, Any] | None) -> str:
    if not item:
        return ""
    return f"{item.get('device_id')}|{item.get('workout_id')}"


def _workout_source_key(item: dict[str, Any]) -> str:
    return _source_key(item.get("source"), item.get("workout_id"))


def _source_key(source: Any, workout_id: Any) -> str:
    return f"{source}:{workout_id}"


def _pair_key(left: str, right: str) -> tuple[str, str]:
    return tuple(sorted((left, right)))


def _first_present(items: list[dict[str, Any]], key: str) -> Any:
    for item in items:
        value = item.get(key)
        if value:
            return value
    return None


def _base_workout_stats(item: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not item:
        return []
    stats = []
    if item.get("duration_seconds"):
        stats.append(
            {
                "label": "Dauer",
                "value": _format_duration(item["duration_seconds"]),
                "systemImage": "clock",
            }
        )
    if item.get("distance_km"):
        stats.append(
            {
                "label": "Distanz",
                "value": f"{float(item['distance_km']):.2f} km",
                "systemImage": "map",
            }
        )
    if item.get("energy_kcal"):
        stats.append(
            {
                "label": "Kalorien",
                "value": f"{round(float(item['energy_kcal']))} kcal",
                "systemImage": "flame",
            }
        )
    if item.get("average_heart_rate"):
        stats.append(
            {
                "label": "Ø Puls",
                "value": f"{round(float(item['average_heart_rate']))} bpm",
                "systemImage": "heart",
            }
        )
    if item.get("max_heart_rate"):
        stats.append(
            {
                "label": "Max Puls",
                "value": f"{round(float(item['max_heart_rate']))} bpm",
                "systemImage": "heart.fill",
            }
        )
    return stats


def _dedupe_stats(stats: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    seen = set()
    for stat in stats:
        label = str(stat.get("label") or "").strip().lower()
        value = stat.get("value")
        if not label or value in (None, "") or label in seen:
            continue
        seen.add(label)
        out.append(stat)
    return out


def _format_duration(seconds: Any) -> str:
    minutes = round(float(seconds or 0) / 60)
    hours, rest = divmod(minutes, 60)
    return f"{hours} Std {rest} Min" if hours else f"{rest} Min"


def _parse_dt(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
