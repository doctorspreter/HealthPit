"""Validation tests for the hourly history upload envelope."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

import pytest


_PATH = (
    Path(__file__).parents[1]
    / "custom_components"
    / "healthpit"
    / "payload.py"
)
_SPEC = spec_from_file_location("healthpit_payload", _PATH)
assert _SPEC and _SPEC.loader
payload = module_from_spec(_SPEC)
_SPEC.loader.exec_module(payload)

_PRECISION_SPEC = spec_from_file_location(
    "healthpit_precision",
    _PATH.with_name("precision.py"),
)
assert _PRECISION_SPEC and _PRECISION_SPEC.loader
precision = module_from_spec(_PRECISION_SPEC)
_PRECISION_SPEC.loader.exec_module(precision)


def test_normalize_metric_history_batch() -> None:
    device_id, category, metric_id, points = payload.normalize_metric_history_batch(
        {
            "device_id": "Peter iPhone",
            "category": "body",
            "metric_id": "body_mass",
            "points": [
                {
                    "start": "2024-01-02T08:00:00Z",
                    "mean": 81.2,
                    "min": 81.0,
                    "max": 81.4,
                },
                {"start": "2024-01-03T08:00:00Z", "mean": 80.9},
            ],
        }
    )

    assert (device_id, category, metric_id) == (
        "Peter iPhone",
        "body",
        "body_mass",
    )
    assert points[0]["mean"] == 81.2
    assert points[1]["start"].endswith("+00:00")


def test_metric_display_precision_is_kept() -> None:
    metric = payload.normalize_metric(
        {
            "id": "body_mass",
            "category": "body",
            "title": "Gewicht",
            "value": 91.40000152587891,
            "unit": "kg",
            "measured_at": "2026-08-05T09:42:56Z",
            "display_precision": 1,
        }
    )
    assert metric["display_precision"] == 1


@pytest.mark.parametrize("value", [-1, 7, 1.5, True])
def test_metric_rejects_invalid_display_precision(value: object) -> None:
    with pytest.raises(payload.PayloadError, match="display_precision"):
        payload.normalize_metric(
            {
                "id": "body_mass",
                "category": "body",
                "title": "Gewicht",
                "value": 91.4,
                "unit": "kg",
                "measured_at": "2026-08-05T09:42:56Z",
                "display_precision": value,
            }
        )


def test_weight_precision_removes_healthkit_float_tail() -> None:
    item = {"metric_id": "body_mass", "unit": "kg"}
    digits = precision.suggested_precision(item)
    assert digits == 1
    assert precision.rounded_value(91.40000152587891, digits) == 91.4


def test_workout_counts_are_integers() -> None:
    assert precision.suggested_precision({}, "sport:strength_training:count") == 0


@pytest.mark.parametrize(
    "points, message",
    [
        (
            [
                {"start": "2024-01-02T09:00:00Z", "mean": 1},
                {"start": "2024-01-02T08:00:00Z", "mean": 2},
            ],
            "strictly ordered",
        ),
        ([{"start": "2024-01-02T08:00:00Z", "mean": "nan"}], "finite"),
        ([{"start": "2024-01-02T08:00:00Z"}], "needs statistic values"),
    ],
)
def test_rejects_invalid_history_points(points: list[dict], message: str) -> None:
    with pytest.raises(payload.PayloadError, match=message):
        payload.normalize_metric_history_batch(
            {
                "device_id": "iPhone",
                "category": "body",
                "metric_id": "body_mass",
                "points": points,
            }
        )
