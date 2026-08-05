"""Write past workouts into Home Assistant's long-term statistics.

Home Assistant keeps two separate books. Its ``states`` table cannot be
backdated — there is no API for it, and writing into it by hand would have to
reproduce the recorder's internal bookkeeping and would break on every schema
migration. Its ``statistics`` table *can* be backdated, and that is the one that
matters here: for a sensor carrying a ``state_class``, Home Assistant draws long
ranges from the statistics, so a filled statistics series is exactly the
multi-year graph the user is after.

Only genuinely cumulative values can be reconstructed this way. "Last workout"
or "last distance" describe a moment, not a series, and are left alone.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import logging
from typing import Any

from homeassistant.components.recorder.models import StatisticData, StatisticMetaData
from homeassistant.components.recorder.statistics import async_import_statistics
from homeassistant.core import HomeAssistant
from homeassistant.helpers import entity_registry as er
from homeassistant.util import dt as dt_util

from .const import DOMAIN
from .coordinator import HealthpitCoordinator
from .workout_entities import slug, sport_name

_LOGGER = logging.getLogger(__name__)

# descriptor suffix -> (unit, how to derive the per-workout contribution)
CUMULATIVE_METRICS: dict[str, tuple[str | None, str]] = {
    "count": (None, "one"),
    "total_duration": ("h", "duration_hours"),
    "total_distance": ("km", "distance_km"),
}


def _contribution(workout: dict[str, Any], kind: str) -> float:
    if kind == "one":
        return 1.0
    if kind == "duration_hours":
        return float(workout.get("duration_seconds") or 0) / 3600
    if kind == "distance_km":
        return float(workout.get("distance_km") or 0)
    return 0.0


def _hour(value: datetime) -> datetime:
    """Statistics rows must sit on full hours."""
    return value.replace(minute=0, second=0, microsecond=0)


def _workout_start(workout: dict[str, Any]) -> datetime | None:
    parsed = dt_util.parse_datetime(str(workout.get("start_time") or ""))
    if parsed is None:
        return None
    return dt_util.as_utc(parsed)


def _series(
    workouts: list[dict[str, Any]],
    kind: str,
) -> list[StatisticData]:
    """Turn workouts into a running total, one row per hour that has data."""
    dated = sorted(
        ((start, workout) for workout in workouts if (start := _workout_start(workout))),
        key=lambda pair: pair[0],
    )
    if not dated:
        return []

    rows: list[StatisticData] = []
    running = 0.0
    current_hour: datetime | None = None
    for start, workout in dated:
        bucket = _hour(start)
        if current_hour is not None and bucket != current_hour:
            rows.append(StatisticData(start=current_hour, state=running, sum=running))
        current_hour = bucket
        running += _contribution(workout, kind)
    if current_hour is not None:
        rows.append(StatisticData(start=current_hour, state=running, sum=running))
    return rows


def _entity_id(
    registry: er.EntityRegistry,
    user_id: str,
    descriptor_key: str,
) -> str | None:
    """Find the sensor a descriptor belongs to, by the unique ID we gave it."""
    return registry.async_get_entity_id(
        "sensor", DOMAIN, f"{user_id}_workout_{descriptor_key}"
    )


async def async_import_history(
    hass: HomeAssistant,
    coordinator: HealthpitCoordinator,
    user_id: str | None = None,
) -> dict[str, Any]:
    """Backfill the cumulative sport statistics from stored workouts."""
    registry = er.async_get(hass)
    user_ids = [user_id] if user_id else coordinator.store.user_ids()

    imported = 0
    skipped: list[str] = []
    for current_user in user_ids:
        workouts = coordinator.store.unified_workouts(current_user)
        if not workouts:
            continue

        by_sport: dict[str, list[dict[str, Any]]] = {}
        for workout in workouts:
            by_sport.setdefault(sport_name(workout), []).append(workout)

        for sport, sport_workouts in by_sport.items():
            prefix = f"sport:{slug(sport)}"
            for suffix, (unit, kind) in CUMULATIVE_METRICS.items():
                descriptor_key = f"{prefix}:{suffix}"
                entity_id = _entity_id(registry, current_user, descriptor_key)
                if entity_id is None:
                    # The sensor does not exist yet, which happens when a sport
                    # has no value for this metric at all. Nothing to attach to.
                    skipped.append(descriptor_key)
                    continue

                rows = _series(sport_workouts, kind)
                if not rows:
                    continue

                metadata = StatisticMetaData(
                    has_mean=False,
                    has_sum=True,
                    name=None,
                    source="recorder",
                    statistic_id=entity_id,
                    unit_of_measurement=unit,
                )
                async_import_statistics(hass, metadata, rows)
                imported += len(rows)
                _LOGGER.debug(
                    "Imported %s statistics rows for %s", len(rows), entity_id
                )

    return {"rows": imported, "skipped": len(skipped), "users": len(user_ids)}


def earliest_workout(coordinator: HealthpitCoordinator, user_id: str) -> datetime | None:
    """When the stored history starts, for reporting back to the caller."""
    starts = [
        start
        for workout in coordinator.store.unified_workouts(user_id)
        if (start := _workout_start(workout))
    ]
    return min(starts, default=None)


def history_span(coordinator: HealthpitCoordinator, user_id: str) -> timedelta | None:
    start = earliest_workout(coordinator, user_id)
    return dt_util.utcnow() - start if start else None
