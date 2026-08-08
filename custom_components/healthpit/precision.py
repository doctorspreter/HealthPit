"""Consistent numeric precision for HealthPit sensor states and statistics."""

from __future__ import annotations

from typing import Any


_UNIT_PRECISION: dict[str, int] = {
    "%": 0,
    "bpm": 0,
    "kcal": 0,
    "mmHg": 0,
    "W": 0,
    "dB": 0,
    "ms": 0,
    "kg": 1,
    "cm": 1,
    "m": 1,
    "km/h": 1,
    "m/s": 1,
    "°C": 1,
    "h": 1,
    "min": 1,
    "L": 1,
    "L/min": 1,
    "ml/kg·min": 1,
    "km": 2,
}

_INTEGER_SUFFIXES = {
    "count",
    "exercises",
    "personal_records",
    "reps",
    "sessions",
    "sets",
}


def suggested_precision(item: dict[str, Any], key: str = "") -> int | None:
    """Return the intended number of visible decimal places for a sensor."""
    explicit = item.get("display_precision")
    if isinstance(explicit, int) and not isinstance(explicit, bool) and 0 <= explicit <= 6:
        return explicit

    if item.get("device_class") == "timestamp":
        return None

    unit = str(item.get("unit") or "")
    if unit in _UNIT_PRECISION:
        return _UNIT_PRECISION[unit]

    identity = str(item.get("metric_id") or item.get("id") or key)
    suffix = identity.rsplit(":", 1)[-1]
    if suffix in _INTEGER_SUFFIXES:
        return 0
    if identity == "body_mass_index" or suffix == "rpe":
        return 1
    if item.get("aggregation") == "sum" or item.get("state_class") == "total":
        return 0
    return 1


def rounded_value(value: Any, precision: int | None) -> Any:
    """Remove meaningless binary floating-point tails from numeric states."""
    if precision is None or isinstance(value, bool) or not isinstance(value, (int, float)):
        return value
    return round(float(value), precision)
