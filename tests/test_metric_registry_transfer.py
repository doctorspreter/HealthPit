"""Home Assistant side of the metric-id rebuild.

Two things must hold: values already stored keep their entity id, and every
one of them gets a canonical metric id without anything being dropped.

Modules are loaded by path, like the existing tests do, so pytest runs without
Home Assistant installed.
"""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys
import types

import pytest


_COMPONENT = Path(__file__).parents[1] / "custom_components" / "healthpit"


def _load(name: str):
    """Load one module of the integration standalone.

    ``payload.py`` imports ``.metrics``; a small package shim keeps that
    relative import working without pulling in Home Assistant.
    """
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


metrics = _load("metrics")
payload = _load("payload")


# ---------------------------------------------------------------------------
# Mapping
# ---------------------------------------------------------------------------


def test_legacy_sensor_ids_map_to_canonical_ids() -> None:
    assert metrics.canonical_metric_id("step_count") == "ACT_STEPS"
    assert metrics.canonical_metric_id("heart_rate") == "HRT_RATE"
    assert metrics.canonical_metric_id("body_mass") == "BDY_WEIGHT"
    assert metrics.canonical_metric_id("sleep_deep_duration") == "SLP_DEEP_DURATION"
    assert metrics.canonical_metric_id("cycle_current_day") == "CYC_CURRENT_DAY"
    assert metrics.canonical_metric_id("workout_count_all_time") == "WRK_COUNT_TOTAL"


def test_canonical_ids_pass_through_unchanged() -> None:
    assert metrics.canonical_metric_id("ACT_STEPS") == "ACT_STEPS"
    assert metrics.canonical_metric_id("GAR_BODY_BATTERY") == "GAR_BODY_BATTERY"


def test_unknown_ids_are_not_guessed() -> None:
    # A wrong mapping would silently merge two different values. Better none.
    assert metrics.canonical_metric_id("something_new") is None
    assert metrics.canonical_metric_id("") is None
    assert metrics.canonical_metric_id(None) is None


def test_registry_category_follows_the_prefix() -> None:
    assert metrics.registry_category("HRT_RATE") == "heart"
    assert metrics.registry_category("NRG_ACTIVE") == "energy"
    assert metrics.registry_category("GAR_BODY_BATTERY") == "proprietary"


# ---------------------------------------------------------------------------
# Transfer of stored data
# ---------------------------------------------------------------------------


def _legacy_storage() -> dict:
    return {
        "users": {
            "user-1": {
                "name": "Peter",
                "metrics": {
                    "iphone|activity|step_count": {
                        "metric_id": "step_count",
                        "category": "activity",
                        "title": "Schritte",
                        "value": 8431.0,
                        "unit": "Schritte",
                        "measured_at": "2026-08-12T10:00:00+00:00",
                        "aggregation": "sum",
                        "device_id": "iphone",
                    },
                    "iphone|sleep|sleep_deep_duration": {
                        "metric_id": "sleep_deep_duration",
                        "category": "sleep",
                        "title": "Tiefschlaf",
                        "value": 1.2,
                        "unit": "h",
                        "measured_at": "2026-08-12T06:00:00+00:00",
                        "aggregation": "sum",
                        "device_id": "iphone",
                    },
                    "iphone|vitals|something_new": {
                        "metric_id": "something_new",
                        "category": "vitals",
                        "title": "Unbekannt",
                        "value": 42.0,
                        "unit": "",
                        "measured_at": "2026-08-12T06:00:00+00:00",
                        "aggregation": "latest",
                        "device_id": "iphone",
                    },
                },
                "workouts": {
                    "iphone|abc": {
                        "workout_id": "abc",
                        "source": "apple_health",
                        "start_time": "2026-08-11T07:00:00+00:00",
                    },
                    "iphone|def": {
                        "workout_id": "def",
                        "source": "gympit",
                        "start_time": "2026-08-10T18:00:00+00:00",
                    },
                },
                "links": [],
            }
        }
    }


def test_transfer_keeps_every_storage_key() -> None:
    original = _legacy_storage()
    migrated = metrics.upgrade_storage(original)

    before = set(original["users"]["user-1"]["metrics"])
    after = set(migrated["users"]["user-1"]["metrics"])
    # The key builds the entity id. A changed key means a lost sensor and a
    # lost history.
    assert before == after
    assert set(original["users"]["user-1"]["workouts"]) == set(
        migrated["users"]["user-1"]["workouts"]
    )


def test_transfer_adds_canonical_ids_and_providers() -> None:
    migrated = metrics.upgrade_storage(_legacy_storage())
    stored = migrated["users"]["user-1"]["metrics"]

    steps = stored["iphone|activity|step_count"]
    assert steps["canonical_metric_id"] == "ACT_STEPS"
    assert steps["legacy_metric_id"] == "step_count"
    assert steps["metric_id"] == "step_count", "Der Sensorschlüssel bleibt"
    assert steps["registry_category"] == "activity"
    assert steps["origin_provider"] == "APP"
    assert steps["ingest_provider"] == "APP"
    # Nothing of the old value is lost.
    assert steps["value"] == 8431.0
    assert steps["title"] == "Schritte"

    sleep = stored["iphone|sleep|sleep_deep_duration"]
    assert sleep["canonical_metric_id"] == "SLP_DEEP_DURATION"


def test_unknown_values_are_kept_and_marked() -> None:
    migrated = metrics.upgrade_storage(_legacy_storage())
    unknown = migrated["users"]["user-1"]["metrics"]["iphone|vitals|something_new"]

    assert unknown["value"] == 42.0, "Der Wert bleibt erhalten"
    assert unknown["canonical_metric_id"].startswith("PRP_")
    assert unknown["registry_category"] == "proprietary"


def test_workouts_get_provider_codes() -> None:
    migrated = metrics.upgrade_storage(_legacy_storage())
    workouts = migrated["users"]["user-1"]["workouts"]

    assert workouts["iphone|abc"]["origin_provider"] == "APP"
    assert workouts["iphone|def"]["origin_provider"] == "GYM"
    assert workouts["iphone|def"]["source"] == "gympit", "Quelle bleibt unverändert"


def test_transfer_is_idempotent() -> None:
    once = metrics.upgrade_storage(_legacy_storage())
    twice = metrics.upgrade_storage(once)
    assert once == twice


def test_transfer_survives_broken_storage() -> None:
    assert metrics.upgrade_storage({}) == {"users": {}}
    assert metrics.upgrade_storage({"users": "kaputt"}) == {"users": {}}
    assert metrics.upgrade_storage({"users": {"u": {"metrics": None}}})["users"]["u"][
        "metrics"
    ] == {}


def test_transfer_summary_counts_what_is_there() -> None:
    summary = metrics.transfer_summary(_legacy_storage())
    assert summary == {"metrics": 3, "unresolved": 1, "workouts": 2}


# ---------------------------------------------------------------------------
# Incoming payloads
# ---------------------------------------------------------------------------


def test_payload_derives_canonical_id_from_a_legacy_push() -> None:
    """An app that has not been updated yet must keep working."""
    normalized = payload.normalize_metric(
        {
            "id": "step_count",
            "category": "activity",
            "title": "Schritte",
            "value": 8431,
            "unit": "Schritte",
            "measured_at": "2026-08-12T10:00:00+00:00",
            "aggregation": "sum",
        }
    )

    assert normalized["metric_id"] == "step_count"
    assert normalized["canonical_metric_id"] == "ACT_STEPS"
    assert normalized["origin_provider"] == "APP"
    assert normalized["ingest_provider"] == "APP"


def test_payload_takes_the_metric_id_and_providers_when_sent() -> None:
    normalized = payload.normalize_metric(
        {
            "id": "heart_rate",
            "metric_id": "HRT_RATE",
            "category": "heart",
            "title": "Herzfrequenz",
            "value": 72,
            "unit": "bpm",
            "measured_at": "2026-08-12T10:00:00+00:00",
            "aggregation": "average",
            "origin_provider": "GAR",
            "ingest_provider": "APP",
            "source_app_id": "com.garmin.connect.mobile",
            "observation_id": "0198abcd-1234-7890-abcd-1234567890ab",
            "unit_code": "BPM",
            "period_type": "INSTANT",
        }
    )

    assert normalized["canonical_metric_id"] == "HRT_RATE"
    assert normalized["origin_provider"] == "GAR"
    assert normalized["ingest_provider"] == "APP"
    assert normalized["source_app_id"] == "com.garmin.connect.mobile"
    assert normalized["unit_code"] == "BPM"
    assert normalized["period_type"] == "INSTANT"


def test_payload_accepts_a_provider_nobody_has_implemented_yet() -> None:
    normalized = payload.normalize_metric(
        {
            "id": "strain",
            "metric_id": "WHO_STRAIN_SCORE",
            "category": "activity",
            "title": "Strain",
            "value": 14.6,
            "measured_at": "2026-08-12T10:00:00+00:00",
            "aggregation": "latest",
            "origin_provider": "WHO",
        }
    )
    assert normalized["origin_provider"] == "WHO"
    assert normalized["canonical_metric_id"] == "WHO_STRAIN_SCORE"


def test_payload_falls_back_when_the_provider_makes_no_sense() -> None:
    normalized = payload.normalize_metric(
        {
            "id": "step_count",
            "category": "activity",
            "title": "Schritte",
            "value": 1,
            "measured_at": "2026-08-12T10:00:00+00:00",
            "aggregation": "sum",
            "origin_provider": "not-a-code",
        }
    )
    assert normalized["origin_provider"] == "APP"


def test_payload_still_rejects_nonsense() -> None:
    with pytest.raises(payload.PayloadError):
        payload.normalize_metric({"id": "step_count", "category": "nope", "value": 1})

