"""Two people must not end up with two devices called "Body".

The identifier already carries the user id, so nothing collides in storage. On
screen it would: two devices with the same name, and Home Assistant derives
entity IDs from the device name — the second person would silently get
``sensor.body_weight_2``.

The second rule here is about where the strength values live. Home Assistant
lists devices flat, so a device per exercise put fifteen machines next to the
health areas, no matter what ``via_device`` claimed. They belong on the one gym
device.
"""

from __future__ import annotations

import ast
from pathlib import Path

_COMPONENT = Path(__file__).parents[1] / "custom_components" / "healthpit"
_ENTITY = _COMPONENT / "entity.py"
_SOURCE = _ENTITY.read_text(encoding="utf-8")
_TREE = ast.parse(_SOURCE)
_SENSOR = (_COMPONENT / "sensor.py").read_text(encoding="utf-8")


def _function(name: str) -> ast.FunctionDef:
    for node in _TREE.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} is missing")


def _names() -> set[str]:
    return {
        node.name for node in _TREE.body if isinstance(node, ast.FunctionDef)
    }


def test_area_devices_carry_the_person():
    source = ast.unparse(_function("category_device_info"))
    assert "user_name" in source, "the area name must include the person"


def test_the_gym_device_carries_the_person():
    source = ast.unparse(_function("gym_device_info"))
    assert "user_name" in source, "the gym name must include the person"


def test_exercises_no_longer_get_a_device_each():
    assert "exercise_device_info" not in _names(), (
        "a device per exercise puts every machine next to the health areas"
    )
    assert "exercise_device_info" not in _SENSOR


def test_the_exercise_sensor_sits_on_the_gym_device():
    marker = "self._attr_device_info = gym_device_info(coordinator, user_id)"
    assert marker in _SENSOR


def test_identifiers_stay_unique_per_person():
    """The identifier is what keeps two households apart in storage."""
    for name in ("category_device_info", "gym_device_info"):
        source = ast.unparse(_function(name))
        assert "user_id" in source, name


def test_every_via_device_has_something_that_creates_it():
    """A device pointing at a parent that nobody creates ends up at the top.

    That happened twice: the area devices named the user device before anything
    created it, and the exercises named a workouts device that only existed if a
    workout sensor happened to carry it. Devices without entities of their own
    must be registered explicitly during setup.
    """
    parents = set()
    for name in ("category_device_info", "gym_device_info"):
        source = ast.unparse(_function(name))
        if "via_device" not in source:
            continue
        if "user_id})" in source or "DOMAIN, user_id)" in source:
            parents.add("user_device_info")
        if "_gym" in source:
            parents.add("gym_device_info")

    for parent in parents:
        assert parent in _SENSOR, f"{parent} is never registered during setup"
