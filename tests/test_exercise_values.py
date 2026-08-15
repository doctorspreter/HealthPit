"""The strength values from GymPit have to survive the trip intact.

They arrive under HealthPit's own identifiers now — ``WRK_SET_WEIGHT`` instead
of ``weight_kg``. Nothing is translated on the way any more, which means the
only thing that can still go wrong is that something is accepted which should
not be, or dropped which should not be.
"""

from __future__ import annotations

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys
import types

_COMPONENT = Path(__file__).parents[1] / "custom_components" / "healthpit"


def _load(name: str):
    """Load one module of the integration without pulling in Home Assistant."""
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


normalize_metric_values = _load("payload").normalize_metric_values


def _batch(*values):
    return {"device_id": "iphone", "model_version": 2, "values": list(values)}


def test_a_set_arrives_with_its_exercise_and_index():
    values = normalize_metric_values(
        _batch(
            {
                "metric_id": "WRK_SET_WEIGHT",
                "unit": "KG",
                "value": 80,
                "exercise_id": "leg-press",
                "exercise_name": "Beinpresse",
                "set_index": 0,
                "start": "2026-08-14T18:00:00Z",
                "end": "2026-08-14T18:40:00Z",
            }
        )
    )

    assert len(values) == 1
    value = values[0]
    assert value["metric_id"] == "WRK_SET_WEIGHT"
    assert value["unit"] == "KG"
    assert value["value"] == 80
    assert value["exercise_id"] == "leg-press"
    assert value["set_index"] == 0


def test_text_and_boolean_values_come_through():
    values = normalize_metric_values(
        _batch(
            {"metric_id": "WRK_SET_TYPE", "text": "WORKING", "exercise_id": "squat"},
            {
                "metric_id": "WRK_SET_IS_PERSONAL_RECORD",
                "boolean": True,
                "exercise_id": "squat",
            },
        )
    )

    assert [value["metric_id"] for value in values] == [
        "WRK_SET_TYPE",
        "WRK_SET_IS_PERSONAL_RECORD",
    ]
    assert values[0]["text"] == "WORKING"
    assert values[1]["boolean"] is True


def test_a_value_without_any_content_is_dropped():
    """Metric id alone is not a measurement."""
    assert normalize_metric_values(_batch({"metric_id": "WRK_SET_REPS"})) == []


def test_identifiers_that_are_not_canonical_are_refused():
    """``weight_kg`` is the old shape; accepting it would reopen the translation."""
    values = normalize_metric_values(
        _batch(
            {"metric_id": "weight_kg", "value": 80},
            {"metric_id": "", "value": 80},
            {"metric_id": "WRK_SET_WEIGHT", "unit": "KG", "value": 80},
        )
    )

    assert [value["metric_id"] for value in values] == ["WRK_SET_WEIGHT"]


def test_a_batch_without_values_is_not_an_error():
    """Older app versions send no values at all. That is allowed."""
    assert normalize_metric_values({"device_id": "iphone", "workouts": []}) == []
    assert normalize_metric_values(None) == []
