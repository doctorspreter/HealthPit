"""Find workouts that are probably the same session recorded twice.

``workout_merge`` already folds an Apple Health recording together with the
GymPit one automatically, because those two never share a source. What it
deliberately refuses is a pair with the *same* source: one source is supposed
to report a session once, so folding two of them together would silently hide
a genuine back-to-back workout.

That assumption broke once GymPit and the Healthpit app both started pushing
to Home Assistant on their own. The same gym session can now arrive twice as
``gympit`` under two device IDs. Guessing is the wrong fix here — two sets of
squats really can follow each other. So this module only *proposes* pairs and
leaves the decision to the person, which is what ``store.save_link`` records.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from .workout_entities import slug, sport_name

# Wider than the merge window: a proposal may be wrong, an automatic merge may
# not. Half an hour still covers a session that one side timed from the first
# set and the other from entering the gym.
CANDIDATE_WINDOW_SECONDS = 30 * 60

# Below this the pair is not worth showing; it would only add noise to a list
# the user has to work through by hand.
MINIMUM_CONFIDENCE = 0.35


def find_candidates(
    workouts: list[dict[str, Any]],
    links: list[dict[str, str]] | None = None,
    *,
    limit: int = 200,
) -> list[dict[str, Any]]:
    """Return pairs that look like one session, best guess first.

    ``workouts`` are unified workouts as the app sees them, so a pair the user
    merges earlier never shows up again: it has become a single entry.
    """
    decided = {
        _pair_key(row.get("primary", ""), row.get("linked", ""))
        for row in (links or [])
    }

    ordered = sorted(workouts, key=lambda item: _timestamp(item) or 0.0)
    out: list[dict[str, Any]] = []
    for index, left in enumerate(ordered):
        left_start = _timestamp(left)
        if left_start is None:
            continue
        for right in ordered[index + 1 :]:
            right_start = _timestamp(right)
            if right_start is None:
                continue
            # Sorted by start, so everything further right is further away.
            if right_start - left_start > CANDIDATE_WINDOW_SECONDS:
                break
            if _shares_a_source_id(left, right):
                continue
            pair = _pair_key(_key_of(left), _key_of(right))
            if pair in decided:
                continue
            if _rules_it_out(left, right, right_start - left_start):
                continue
            confidence, reason = _score(left, right, right_start - left_start)
            if confidence < MINIMUM_CONFIDENCE:
                continue
            out.append(
                {
                    "id": "|".join(pair),
                    "reason": reason,
                    "confidence": round(confidence, 2),
                    "left": _side(left),
                    "right": _side(right),
                }
            )

    out.sort(key=lambda item: item["confidence"], reverse=True)
    return out[:limit]


def _rules_it_out(
    left: dict[str, Any],
    right: dict[str, Any],
    start_gap: float,
) -> bool:
    """Reject pairs no amount of other agreement should rescue.

    A proposal the user has to read and dismiss costs more than a missed one,
    so anything that contradicts "same session" ends it here rather than
    merely lowering the score.
    """
    distance_difference = _relative_difference(
        left.get("distance_km"), right.get("distance_km")
    )
    if distance_difference is not None and distance_difference > 0.30:
        # Two recordings of one route disagree by metres, not kilometres.
        return True

    duration_difference = _relative_difference(
        left.get("duration_seconds"), right.get("duration_seconds")
    )
    if duration_difference is not None and duration_difference > 0.50:
        return True

    if not _same_sport(left, right):
        # Different sports overlapping in time are normally a superset and a
        # circuit, not one session twice. The exception that must survive is
        # the same sport spelled in two languages, where start and length are
        # identical because it is literally the same recording.
        if start_gap > 180:
            return True
        if duration_difference is not None and duration_difference > 0.10:
            return True

    return False


def _score(
    left: dict[str, Any],
    right: dict[str, Any],
    start_gap: float,
) -> tuple[float, str]:
    """Rate how likely the pair is one session, and say what drove the rating."""
    # Starting at the same minute is the strongest single hint there is.
    score = 1.0 - (start_gap / CANDIDATE_WINDOW_SECONDS) * 0.5
    reason = "same_start" if start_gap <= 120 else "close_start"

    duration_difference = _relative_difference(
        left.get("duration_seconds"), right.get("duration_seconds")
    )
    if duration_difference is not None and duration_difference < 0.10:
        score += 0.15
        if reason == "same_start":
            reason = "same_duration"

    distance_difference = _relative_difference(
        left.get("distance_km"), right.get("distance_km")
    )
    if distance_difference is not None and distance_difference < 0.05:
        score += 0.10
        reason = "same_distance"
    # One side having a route and the other not is normal for a phone paired
    # with a watch, so a missing distance never counts against the pair.

    if _same_sport(left, right):
        score += 0.10
    else:
        score -= 0.20

    if _sources_of(left) == _sources_of(right):
        # The case this whole module exists for.
        reason = "same_source"

    return max(0.0, min(1.0, score)), reason


def _relative_difference(left: Any, right: Any) -> float | None:
    """How far two values are apart, relative to the larger one."""
    left_value = _number(left)
    right_value = _number(right)
    if not left_value or not right_value:
        return None
    return abs(left_value - right_value) / max(left_value, right_value)


def _side(workout: dict[str, Any]) -> dict[str, Any]:
    """The half of a pair the app needs to show it and to act on it."""
    return {
        # What a decision is recorded against. The merge honours any one key of
        # a group, so a single representative is enough to link two entries.
        "key": _key_of(workout),
        "keys": sorted(_source_keys(workout)),
        "workout_id": workout.get("workout_id") or workout.get("id"),
        "sport": workout.get("sport"),
        "title": workout.get("title"),
        "source": workout.get("source"),
        "sources": workout.get("sources") or [],
        "device_id": workout.get("device_id"),
        "start": workout.get("start_time") or workout.get("start"),
        "end": workout.get("end_time") or workout.get("end"),
        "duration_seconds": _number(workout.get("duration_seconds")) or 0.0,
        "distance_km": _number(workout.get("distance_km")),
        "energy_kcal": _number(workout.get("energy_kcal")),
        "exercise_count": workout.get("exercise_count") or 0,
        "set_count": workout.get("set_count") or 0,
        "route_points": workout.get("route_points") or 0,
    }


def describe_decisions(
    workouts: list[dict[str, Any]], links: list[dict[str, str]]
) -> list[dict[str, Any]]:
    """Past decisions with the workouts they were made about.

    A decision used to travel as two opaque keys, so the app could only say
    "merged" without saying what. The keys are still what a decision hangs on;
    the description is added next to them.
    """
    by_key: dict[str, dict[str, Any]] = {}
    for workout in workouts:
        side = _side(workout)
        for key in side["keys"] or [side["key"]]:
            by_key.setdefault(key, side)

    described: list[dict[str, Any]] = []
    for link in links:
        primary = str(link.get("primary", ""))
        linked = str(link.get("linked", ""))
        described.append(
            {
                "primary": primary,
                "linked": linked,
                "action": link.get("action", ""),
                # Missing when the workout has since been deleted. The app
                # shows the decision anyway, so it can still be undone.
                "primary_side": by_key.get(primary),
                "linked_side": by_key.get(linked),
            }
        )
    return described


def _shares_a_source_id(left: dict[str, Any], right: dict[str, Any]) -> bool:
    """True once the two already describe the same underlying recording."""
    return bool(_source_keys(left) & _source_keys(right))


def _source_keys(workout: dict[str, Any]) -> set[str]:
    keys = set()
    for source, workout_id in (workout.get("source_ids") or {}).items():
        if source and workout_id:
            keys.add(f"{source}:{workout_id}")
    if workout.get("source") and workout.get("workout_id"):
        keys.add(f"{workout['source']}:{workout['workout_id']}")
    return keys


def _key_of(workout: dict[str, Any]) -> str:
    keys = sorted(_source_keys(workout))
    return keys[0] if keys else ""


def _sources_of(workout: dict[str, Any]) -> frozenset[str]:
    sources = workout.get("sources") or []
    if not sources and workout.get("source"):
        sources = [workout["source"]]
    return frozenset(str(item) for item in sources)


def _same_sport(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return _sport_key(left) == _sport_key(right)


def _sport_key(workout: dict[str, Any]) -> str:
    # sport_name folds the spellings that mean one sport onto one name, which
    # matters here because the apps send "running" or "Laufen" depending on the
    # display language they were set to at the time.
    return slug(sport_name(workout))


def _pair_key(left: str, right: str) -> tuple[str, str]:
    return tuple(sorted((left, right)))


def _timestamp(workout: dict[str, Any]) -> float | None:
    value = workout.get("start_time") or workout.get("start")
    if isinstance(value, datetime):
        return value.timestamp()
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _number(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
