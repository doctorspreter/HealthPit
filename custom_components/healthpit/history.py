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

from homeassistant.components.recorder.models import (
    StatisticData,
    StatisticMeanType,
    StatisticMetaData,
)
from homeassistant.components.recorder.statistics import (
    STATISTIC_UNIT_TO_UNIT_CONVERTER,
    async_import_statistics,
)
from homeassistant.core import HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util

from .const import DOMAIN
from .coordinator import HealthPitCoordinator
from .metrics import group_exercise_history
from .precision import rounded_value, suggested_precision
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


def _metadata(
    *,
    entity_id: str,
    unit: str | None,
    has_sum: bool,
) -> StatisticMetaData:
    """Build recorder metadata using the current statistics API."""
    converter = STATISTIC_UNIT_TO_UNIT_CONVERTER.get(unit)
    return StatisticMetaData(
        # Kept while older supported Home Assistant versions still read it.
        has_mean=not has_sum,
        mean_type=(
            StatisticMeanType.NONE if has_sum else StatisticMeanType.ARITHMETIC
        ),
        has_sum=has_sum,
        name=None,
        source="recorder",
        statistic_id=entity_id,
        # Match the metadata the recorder itself creates for this entity.
        unit_class=converter.UNIT_CLASS if converter else None,
        unit_of_measurement=unit,
    )


def _metric_entity_id(
    registry: er.EntityRegistry,
    user_id: str,
    device_id: str,
    category: str,
    metric_id: str,
) -> str | None:
    return registry.async_get_entity_id(
        "sensor", DOMAIN, f"{user_id}_{device_id}_{category}_{metric_id}"
    )


def _stored_metric(
    coordinator: HealthPitCoordinator,
    user_id: str,
    device_id: str,
    category: str,
    metric_id: str,
) -> dict[str, Any] | None:
    return next(
        (
            metric
            for metric in coordinator.store.latest_metrics(user_id)
            if str(metric.get("device_id") or "healthpit") == device_id
            and metric.get("category") == category
            and metric.get("metric_id") == metric_id
        ),
        None,
    )


async def async_import_metric_history(
    hass: HomeAssistant,
    coordinator: HealthPitCoordinator,
    user_id: str,
    device_id: str,
    category: str,
    metric_id: str,
    points: list[dict[str, Any]],
) -> dict[str, Any]:
    """Import one ordered chunk of hourly HealthKit statistics."""
    metric = _stored_metric(coordinator, user_id, device_id, category, metric_id)
    if metric is None:
        raise HomeAssistantError(
            "Push the current metric before importing its history"
        )

    entity_id = _metric_entity_id(
        er.async_get(hass), user_id, device_id, category, metric_id
    )
    if entity_id is None:
        raise HomeAssistantError(
            "The metric entity is still being created; retry the history chunk"
        )

    has_sum = metric.get("aggregation") == "sum"
    precision = suggested_precision(metric)
    rows: list[StatisticData] = []
    for point in points:
        parsed = dt_util.parse_datetime(str(point["start"]))
        if parsed is None:
            raise HomeAssistantError("History contains an invalid timestamp")
        start = dt_util.as_utc(parsed)
        if start != _hour(start):
            raise HomeAssistantError("History timestamps must be on a full UTC hour")

        if has_sum:
            if "state" not in point or "sum" not in point:
                raise HomeAssistantError(
                    "Cumulative history points need state and sum"
                )
            rows.append(
                StatisticData(
                    start=start,
                    state=rounded_value(float(point["state"]), precision),
                    sum=rounded_value(float(point["sum"]), precision),
                )
            )
        else:
            if "mean" not in point:
                raise HomeAssistantError("Measurement history points need mean")
            mean = rounded_value(float(point["mean"]), precision)
            rows.append(
                StatisticData(
                    start=start,
                    mean=mean,
                    min=rounded_value(float(point.get("min", mean)), precision),
                    max=rounded_value(float(point.get("max", mean)), precision),
                    mean_weight=1.0,
                )
            )

    async_import_statistics(
        hass,
        _metadata(
            entity_id=entity_id,
            unit=str(metric.get("unit") or "") or None,
            has_sum=has_sum,
        ),
        rows,
    )
    _LOGGER.debug("Queued %s metric history rows for %s", len(rows), entity_id)
    return {"accepted": len(rows), "entity_id": entity_id}


async def async_import_history(
    hass: HomeAssistant,
    coordinator: HealthPitCoordinator,
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

                metadata = _metadata(
                    entity_id=entity_id,
                    unit=unit,
                    has_sum=True,
                )
                async_import_statistics(hass, metadata, rows)
                imported += len(rows)
                _LOGGER.debug(
                    "Imported %s statistics rows for %s", len(rows), entity_id
                )

    return {"rows": imported, "skipped": len(skipped), "users": len(user_ids)}


# Was noch auf seine Entitaet wartet: unique_id -> Einheit und Stundenwerte.
PENDING_EXERCISE_HISTORY = f"{DOMAIN}_pending_exercise_history"

# Wann erneut versucht wird, in Sekunden. Eine Entitaet entsteht erst, nachdem
# der Koordinator die neuen Werte gemeldet hat – der erste Versuch geht also
# regelmaessig ins Leere, und stur weiterzuprobieren waere Verschwendung.
RETRY_DELAYS = (2, 10, 60)


@callback
def async_queue_exercise_history(
    hass: HomeAssistant,
    user_id: str,
    values: list[dict[str, Any]],
) -> None:
    """Write the strength values into the long-term statistics.

    A set from three weeks ago used to vanish here. The store keeps only the
    latest value per exercise, and Home Assistant's ``states`` table cannot be
    backdated, so everything before the last upload existed nowhere — GymPit
    sent its whole history on every sync and Home Assistant showed the newest
    set and nothing else.

    The statistics table can be backdated. That is where the past belongs: one
    row per hour that has sets, with mean, lowest and highest, so a year of
    training is a curve instead of a single point.
    """
    pending: dict[str, dict[str, Any]] = hass.data.setdefault(
        PENDING_EXERCISE_HISTORY, {}
    )
    for unique_id, entry in group_exercise_history(user_id, values).items():
        waiting = pending.setdefault(unique_id, {"unit": entry["unit"], "hours": {}})
        for hour, numbers in entry["hours"].items():
            waiting["hours"].setdefault(hour, []).extend(numbers)

    if pending:
        async_flush_exercise_history(hass, attempt=0)


@callback
def async_flush_exercise_history(hass: HomeAssistant, attempt: int = 0) -> None:
    """Import everything whose sensor exists by now, and wait for the rest."""
    pending: dict[str, dict[str, Any]] = hass.data.get(PENDING_EXERCISE_HISTORY) or {}
    if not pending:
        return

    registry = er.async_get(hass)
    for unique_id in list(pending):
        entity_id = registry.async_get_entity_id("sensor", DOMAIN, unique_id)
        if entity_id is None:
            # Der Sensor entsteht erst, wenn der Koordinator die Werte
            # gemeldet hat. Aufheben und spaeter noch einmal versuchen.
            continue
        entry = pending.pop(unique_id)
        rows = [
            StatisticData(
                start=hour,
                mean=round(sum(numbers) / len(numbers), 3),
                min=round(min(numbers), 3),
                max=round(max(numbers), 3),
                mean_weight=1.0,
            )
            for hour, numbers in sorted(entry["hours"].items())
            if numbers
        ]
        if not rows:
            continue
        async_import_statistics(
            hass,
            _metadata(entity_id=entity_id, unit=entry["unit"] or None, has_sum=False),
            rows,
        )
        _LOGGER.debug("Imported %s exercise history rows for %s", len(rows), entity_id)

    if pending and attempt < len(RETRY_DELAYS):
        async_call_later(
            hass,
            RETRY_DELAYS[attempt],
            lambda _now: async_flush_exercise_history(hass, attempt + 1),
        )


def earliest_workout(coordinator: HealthPitCoordinator, user_id: str) -> datetime | None:
    """When the stored history starts, for reporting back to the caller."""
    starts = [
        start
        for workout in coordinator.store.unified_workouts(user_id)
        if (start := _workout_start(workout))
    ]
    return min(starts, default=None)


def history_span(coordinator: HealthPitCoordinator, user_id: str) -> timedelta | None:
    start = earliest_workout(coordinator, user_id)
    return dt_util.utcnow() - start if start else None
