"""GymPit sends its whole history on every sync. It has to land somewhere.

Only the newest value per exercise is kept in the store, and Home Assistant's
states table cannot be backdated — so a set from three weeks ago existed
nowhere. The statistics table can be backdated, and these tests cover the step
that turns sets into hourly statistics rows.
"""

from __future__ import annotations

from datetime import datetime, timezone
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


group_exercise_history = _load("metrics").group_exercise_history


def _set(value, *, end, metric_id="WRK_SET_WEIGHT", exercise="leg-press", unit="KG"):
    return {
        "metric_id": metric_id,
        "unit": unit,
        "value": value,
        "exercise_id": exercise,
        "start": end,
        "end": end,
    }


def test_the_sets_of_one_session_become_one_hour():
    grouped = group_exercise_history(
        "peter",
        [
            _set(80, end="2026-07-02T18:10:00Z"),
            _set(85, end="2026-07-02T18:30:00Z"),
            _set(90, end="2026-07-02T18:50:00Z"),
        ],
    )

    entry = grouped["peter_exercise_leg-press_WRK_SET_WEIGHT"]
    assert entry["unit"] == "kg"
    hour = datetime(2026, 7, 2, 18, tzinfo=timezone.utc)
    assert list(entry["hours"]) == [hour]
    assert entry["hours"][hour] == [80.0, 85.0, 90.0]


def test_sessions_weeks_apart_stay_apart():
    """The point of the whole thing: old sets keep their own place in time."""
    grouped = group_exercise_history(
        "peter",
        [
            _set(70, end="2026-06-10T09:00:00Z"),
            _set(80, end="2026-07-02T18:10:00Z"),
        ],
    )

    hours = grouped["peter_exercise_leg-press_WRK_SET_WEIGHT"]["hours"]
    assert sorted(hours) == [
        datetime(2026, 6, 10, 9, tzinfo=timezone.utc),
        datetime(2026, 7, 2, 18, tzinfo=timezone.utc),
    ]


def test_every_exercise_and_value_gets_its_own_key():
    grouped = group_exercise_history(
        "peter",
        [
            _set(80, end="2026-07-02T18:10:00Z"),
            _set(12, end="2026-07-02T18:10:00Z", metric_id="WRK_SET_REPS", unit="CNT"),
            _set(45, end="2026-07-02T18:20:00Z", exercise="abductor"),
        ],
    )

    assert sorted(grouped) == [
        "peter_exercise_abductor_WRK_SET_WEIGHT",
        "peter_exercise_leg-press_WRK_SET_REPS",
        "peter_exercise_leg-press_WRK_SET_WEIGHT",
    ]


def test_two_people_never_share_a_line():
    peter = group_exercise_history("peter", [_set(80, end="2026-07-02T18:10:00Z")])
    anna = group_exercise_history("anna", [_set(40, end="2026-07-02T18:10:00Z")])
    assert set(peter) & set(anna) == set()


def test_text_and_yes_no_values_are_left_out():
    """An average set type is not a thing, and neither is an average record."""
    grouped = group_exercise_history(
        "peter",
        [
            {"metric_id": "WRK_SET_TYPE", "text": "WORKING", "end": "2026-07-02T18:10:00Z"},
            {
                "metric_id": "WRK_SET_IS_PERSONAL_RECORD",
                "boolean": True,
                "end": "2026-07-02T18:10:00Z",
            },
        ],
    )
    assert grouped == {}


def test_a_value_without_a_usable_time_is_dropped():
    """Better no row than a set filed under the wrong hour."""
    assert group_exercise_history("peter", [_set(80, end="whenever")]) == {}
    assert group_exercise_history("peter", [_set(80, end=None)]) == {}


def test_the_upload_route_actually_calls_the_import():
    """The grouping is worth nothing if nobody asks for it.

    Every bug in this integration so far was a connection, not a unit: a
    function that was right and never called. Home Assistant cannot be imported
    here, so the source has to say it.
    """
    http_api = (_COMPONENT / "http_api.py").read_text(encoding="utf-8")
    assert "async_queue_exercise_history" in http_api
    assert "async_queue_exercise_history(_hass(request), user_id, values)" in http_api


def test_the_import_writes_into_the_statistics_table():
    history = (_COMPONENT / "history.py").read_text(encoding="utf-8")
    queue = history.split("def async_queue_exercise_history", 1)[1]
    assert "group_exercise_history" in queue
    flush = history.split("def async_flush_exercise_history", 1)[1]
    assert "async_import_statistics" in flush
    # Ohne Entitaet keine Statistik: das war der 409-Fehler. Der Wert muss
    # aufgehoben und spaeter erneut versucht werden, nicht verworfen.
    assert "async_get_entity_id" in flush
    assert "async_call_later" in flush


def test_the_exercise_sensor_can_carry_statistics_at_all():
    """Without a state class Home Assistant keeps no long-term statistics."""
    sensor = (_COMPONENT / "sensor.py").read_text(encoding="utf-8")
    exercise = sensor.split("class HealthPitExerciseSensor", 1)[1].split("\nclass ", 1)[0]
    assert "def state_class" in exercise
    assert "measurement" in exercise


def test_local_time_is_moved_onto_the_utc_hour():
    """Statistics rows sit on full UTC hours; 20:30+02:00 is the 18:00 row."""
    grouped = group_exercise_history(
        "peter", [_set(80, end="2026-07-02T20:30:00+02:00")]
    )
    hours = grouped["peter_exercise_leg-press_WRK_SET_WEIGHT"]["hours"]
    assert list(hours) == [datetime(2026, 7, 2, 18, tzinfo=timezone.utc)]
