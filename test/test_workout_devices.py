"""Every sport gets its own device, and GymPit keeps its exercises company.

All sports used to share one "Workouts" device, and each exercise additionally
appeared there as a second, German-named copy of what the canonical values
already carried. This file holds the new layout in place:

    Peter
    ├── Peter Body, Peter Heart, Peter Sleep …
    ├── Peter Gym workouts   (GymPit: sessions and exercises)
    ├── Peter Run
    └── Peter Cycling

Home Assistant is not importable here, so the routing is read from the source.
That is enough to catch the mistake that actually happens: a sensor pointed at
the wrong device, or an old device left behind with nothing in it.
"""

from __future__ import annotations

import ast
from pathlib import Path

_COMPONENT = Path(__file__).parents[1] / "custom_components" / "healthpit"
_ENTITY_SOURCE = (_COMPONENT / "entity.py").read_text(encoding="utf-8")
_ENTITY_TREE = ast.parse(_ENTITY_SOURCE)
_SENSOR_SOURCE = (_COMPONENT / "sensor.py").read_text(encoding="utf-8")
_SENSOR_TREE = ast.parse(_SENSOR_SOURCE)


def _function(tree: ast.Module, name: str) -> ast.FunctionDef | ast.AsyncFunctionDef:
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name:
            return node
    raise AssertionError(f"{name} is missing")


def test_a_sport_gets_its_own_device_under_the_person():
    source = ast.unparse(_function(_ENTITY_TREE, "sport_device_info"))
    assert "user_name" in source, "the device name must carry the person"
    assert "_sport_" in source, "the identifier must keep sports apart"
    assert "via_device" in source, "a sport hangs under its person"


def test_the_sport_device_name_does_not_move_with_the_language():
    """The name goes into entity IDs. „Laufen" today and "Run" tomorrow would
    rename every sensor on the device."""
    assert "SPORT_DEVICE_NAMES" in _ENTITY_SOURCE
    names = _function(_ENTITY_TREE, "sport_device_info")
    assert "SPORT_DEVICE_NAMES" in ast.unparse(names)


def test_strength_training_from_gympit_lands_on_the_gym_device():
    source = ast.unparse(_function(_SENSOR_TREE, "workout_device_info"))
    assert "gympit" in source
    assert "gym_device_info" in source
    assert "sport_device_info" in source


def test_an_exercise_aggregate_always_lands_on_the_gym_device():
    source = ast.unparse(_function(_SENSOR_TREE, "workout_device_info"))
    # Die Uebungs-Kennung wird vor der Sportart geprueft; sonst zoege eine
    # Uebung aus einem Lauf-Workout auf das Lauf-Geraet.
    assert source.index("exercise_key") < source.index("sport_key")


def test_the_old_workout_sensors_are_removed_rather_than_left_dangling():
    source = ast.unparse(_function(_SENSOR_TREE, "_retire_old_workout_entities"))
    assert "_workout_" in source, "the old unique_id prefix is what identifies them"
    assert "async_remove" in source


def test_the_new_workout_sensors_carry_a_different_unique_id():
    """Reusing the old one would keep the old entity — and with it its German
    entity ID, which is the whole reason for the rebuild."""
    assert '_wk_{descriptor_key}' in _SENSOR_SOURCE
    assert '_workout_{descriptor_key}' not in _SENSOR_SOURCE

    history = (_COMPONENT / "history.py").read_text(encoding="utf-8")
    assert "_wk_{descriptor_key}" in history, "the backfill must find the new sensors"


def test_the_empty_devices_of_the_old_layout_are_cleared_out():
    which = ast.unparse(_function(_SENSOR_TREE, "_is_from_the_previous_layout"))
    assert "is_exercise_device" in which
    assert "is_legacy_workouts_device" in which

    source = ast.unparse(_function(_SENSOR_TREE, "_remove_empty_legacy_devices"))
    assert "_is_from_the_previous_layout" in source
    # Nur leere Geraete: sonst naehme das Loeschen die Entitaeten mit.
    assert "async_entries_for_device" in source


def test_the_clean_up_stops_for_good_once_it_is_done():
    """A deleter that matches a name pattern must not stand forever.

    This one removes entities whose unique_id starts with the old prefix. Left
    as a standing rule, the day something legitimately carries that shape again
    it would vanish, and nobody would be told why. It runs until one pass finds
    nothing left, and the store remembers that."""
    assert "PREVIOUS_LAYOUT_MARK" in _SENSOR_SOURCE
    once = ast.unparse(_function(_SENSOR_TREE, "_clear_the_previous_layout"))
    assert "_anything_left_of_the_previous_layout" in once

    setup = ast.unparse(_function(_SENSOR_TREE, "async_setup_entry"))
    assert "is_completed(PREVIOUS_LAYOUT_MARK)" in setup
    assert "mark_completed(PREVIOUS_LAYOUT_MARK)" in setup

    # Und der Merker muss einen Neustart ueberleben, sonst laeuft es doch wieder.
    store = (_COMPONENT / "store.py").read_text(encoding="utf-8")
    assert "def mark_completed" in store
    assert '"completed"' in store


def test_a_new_workout_sensor_gets_its_past_without_being_asked():
    """A new sensor starts empty, but everything it shows is a calculation over
    workouts Home Assistant already holds. Until now only GymPit's sync and the
    app's history import triggered the backfill — whoever did neither saw empty
    curves over data that was right there."""
    setup = ast.unparse(_function(_SENSOR_TREE, "async_setup_entry"))
    assert "async_import_history" in setup
    assert "_fill_in_the_past" in setup
    # Nach dem Hinzufuegen, nicht davor: ohne Registrierungseintrag haengt
    # keine Statistik an der Entitaet.
    assert setup.index("async_add_entities(initial)") < setup.index(
        "_fill_in_the_past(initial)"
    )


def test_the_sensors_of_the_folded_spellings_are_dropped_once():
    """Folding "Outdoor Run" into "Laufen" leaves its sensors without anything
    feeding them. They are removed — but only once, and never while the
    descriptions are missing, or an empty store would take everything with it."""
    source = ast.unparse(_function(_SENSOR_TREE, "_drop_orphaned_workout_entities"))
    assert "workout_metrics" in source
    assert "if not current:" in source, "an empty store must not delete anything"
    assert "async_remove" in source
    assert "SPLIT_SPORTS_MARK" in _SENSOR_SOURCE


def test_a_cross_sport_total_sits_with_the_person():
    """"Workouts" is not an area any more, so a total across all sports has no
    area device left to sit on."""
    assert 'if category in {"workouts", "workout"}' in _SENSOR_SOURCE


def test_a_merged_workout_keeps_the_canonical_sport():
    """Otherwise the same session lands under a different sport once it has
    been merged than it did before."""
    merge = (_COMPONENT / "workout_merge.py").read_text(encoding="utf-8")
    assert '"sport_type": _first_present(imported, "sport_type")' in merge
