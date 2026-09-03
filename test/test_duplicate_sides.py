"""What a duplicate proposal must carry so the app can act on it.

The app offers to delete the discarded copy in Apple Health. To find that
entry it needs the UUID of the ``HKWorkout``, and the only place it can read it
is the ``keys`` list of a side: ``apple_health:<uuid>``. If that list stopped
being sent, the app would silently fall back to "not from Apple Health" and the
offer would quietly disappear — no error anywhere.
"""

from __future__ import annotations

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys
import types

_COMPONENT = Path(__file__).parents[1] / "custom_components" / "healthpit"


def _load(name: str):
    package = "healthpit_component"
    if package not in sys.modules:
        shim = types.ModuleType(package)
        shim.__path__ = [str(_COMPONENT)]
        sys.modules[package] = shim
    full_name = f"{package}.{name}"
    if full_name in sys.modules:
        return sys.modules[full_name]
    spec = spec_from_file_location(full_name, _COMPONENT / f"{name}.py")
    assert spec and spec.loader
    module = module_from_spec(spec)
    sys.modules[full_name] = module
    spec.loader.exec_module(module)
    return module


duplicates = _load("duplicates")

_HK_UUID = "0F3D3F2E-1C2B-4A5D-9E8F-7A6B5C4D3E2F"


def _workout(**overrides):
    workout = {
        "device_id": "iphone",
        "workout_id": _HK_UUID,
        "source": "apple_health",
        "sport": "Laufen",
        "title": "Laufen",
        "start_time": "2026-08-11T17:00:00+00:00",
        "end_time": "2026-08-11T17:40:00+00:00",
        "duration_seconds": 2400,
        "distance_km": 6.2,
    }
    workout.update(overrides)
    return workout


def test_an_apple_health_side_carries_its_health_kit_uuid():
    candidates = duplicates.find_candidates(
        [
            _workout(),
            _workout(workout_id="gym-1", source="gympit"),
        ],
        links=[],
    )

    assert candidates, "the same session from two sources is a proposal"
    sides = [candidates[0]["left"], candidates[0]["right"]]
    apple = next(side for side in sides if side["source"] == "apple_health")
    assert f"apple_health:{_HK_UUID}" in apple["keys"]


def test_a_merged_side_keeps_the_apple_health_key_among_the_others():
    """After a merge one side carries several ids. The Apple Health one has to
    survive, or the offer to delete it there would vanish with the merge."""
    merged = _workout(
        source="merged",
        sources=["apple_health", "gympit"],
        source_ids={"apple_health": _HK_UUID, "gympit": "gym-1"},
    )
    candidates = duplicates.find_candidates(
        [merged, _workout(workout_id="other-1", source="gympit")],
        links=[],
    )

    assert candidates
    sides = [candidates[0]["left"], candidates[0]["right"]]
    keys = {key for side in sides for key in side["keys"]}
    assert f"apple_health:{_HK_UUID}" in keys


def test_a_decision_says_which_workouts_it_was_about():
    """"As one workout" and an undo button, with nothing to tell them apart,
    is not a decision anyone can review."""
    apple = _workout()
    gym = _workout(workout_id="gym-1", source="gympit", sport="Krafttraining")
    described = duplicates.describe_decisions(
        [apple, gym],
        links=[
            {
                "primary": f"apple_health:{_HK_UUID}",
                "linked": "gympit:gym-1",
                "action": "merge",
            }
        ],
    )

    assert len(described) == 1
    decision = described[0]
    for name in ("primary_side", "linked_side"):
        side = decision[name]
        assert side is not None, name
        # Genau die Felder, die die App in der Zeile zeigt.
        for field in ("sport", "source", "start", "duration_seconds"):
            assert field in side, f"{name}.{field}"
    assert decision["primary_side"]["source"] == "apple_health"
    assert decision["linked_side"]["sport"] == "Krafttraining"


def test_a_decision_about_a_deleted_workout_stays_undoable():
    described = duplicates.describe_decisions(
        [],
        links=[{"primary": "apple_health:gone", "linked": "gympit:gone", "action": "merge"}],
    )

    assert len(described) == 1
    assert described[0]["primary_side"] is None
    assert described[0]["action"] == "merge"


def test_a_side_without_apple_health_says_so_by_omission():
    candidates = duplicates.find_candidates(
        [
            _workout(workout_id="gym-1", source="gympit"),
            _workout(workout_id="gym-2", source="gympit"),
        ],
        links=[],
    )

    assert candidates
    for side in (candidates[0]["left"], candidates[0]["right"]):
        assert not any(key.startswith("apple_health:") for key in side["keys"])


def test_the_canonical_sport_type_survives_the_payload():
    """The app sends the sport as an identifier now. If the payload dropped it,
    the integration would silently fall back to guessing from a translated
    name — and nothing anywhere would say so."""
    payload = _load("payload")
    workout = payload.normalize_workout(
        {
            "id": "w1",
            "source": "apple_health",
            "sport": "Running",
            "sport_type": "RUNNING",
            "start": "2026-08-11T17:00:00+00:00",
            "end": "2026-08-11T17:40:00+00:00",
        },
        device_id="iphone",
    )
    assert workout["sport_type"] == "RUNNING"
    assert workout["sport"] == "Running"


def test_a_workout_without_the_canonical_type_is_still_accepted():
    """Older app versions do not send it, and neither does anything already
    stored."""
    payload = _load("payload")
    workout = payload.normalize_workout(
        {
            "id": "w2",
            "source": "gympit",
            "sport": "Krafttraining",
            "start": "2026-08-11T17:00:00+00:00",
            "end": "2026-08-11T18:00:00+00:00",
        },
        device_id="iphone",
    )
    assert workout["sport_type"] is None
