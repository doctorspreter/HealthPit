"""Push-driven coordinator holding one bucket of data per Home Assistant user."""

from __future__ import annotations

import logging
from typing import Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator

from .route import bounds, latest_with_route, route_points
from .store import HealthPitStore
from .workout_entities import build_workout_metrics

_LOGGER = logging.getLogger(__name__)


def build_user_data(
    metrics: list[dict[str, Any]],
    workouts: list[dict[str, Any]],
) -> dict[str, Any]:
    """Turn one user's raw data into what the entity platforms read."""
    by_category: dict[str, list[dict[str, Any]]] = {}
    for metric in metrics:
        category = str(metric.get("category") or "")
        by_category.setdefault(category, []).append(
            {
                "id": metric.get("metric_id"),
                "device_id": metric.get("device_id"),
                "title": metric.get("title"),
                "value": metric.get("value"),
                "unit": metric.get("unit", ""),
                "aggregation": metric.get("aggregation", "latest"),
                "device_class": metric.get("device_class"),
                "icon": metric.get("icon"),
                "measured_at": metric.get("measured_at"),
                "state_class": metric.get("state_class"),
                "display_precision": metric.get("display_precision"),
                # New model: what the value is, and where it came from.
                "canonical_metric_id": metric.get("canonical_metric_id"),
                "registry_category": metric.get("registry_category"),
                "origin_provider": metric.get("origin_provider"),
                "ingest_provider": metric.get("ingest_provider"),
                "source_app_id": metric.get("source_app_id"),
                "observation_id": metric.get("observation_id"),
                "unit_code": metric.get("unit_code"),
                "period_type": metric.get("period_type"),
            }
        )
    for items in by_category.values():
        items.sort(
            key=lambda item: (
                str(item.get("device_id") or ""),
                str(item.get("title") or item.get("id") or ""),
            )
        )
    return {
        "by_category": by_category,
        "metric_count": len(metrics),
        "workout_metrics": build_workout_metrics(workouts),
        "workout_count": len(workouts),
        "route": _route_summary(workouts),
    }


def _route_summary(workouts: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Describe the newest track, without dumping its coordinates.

    The points themselves stay in the store. Putting hundreds of them into a
    state attribute would bloat every recorder row for no benefit.
    """
    workout = latest_with_route(workouts)
    if workout is None:
        return None
    points = route_points(workout)
    return {
        "workout_id": workout.get("workout_id"),
        "title": workout.get("title"),
        "sport": workout.get("sport"),
        "start": workout.get("start_time"),
        "end": workout.get("end_time"),
        "distance_km": workout.get("distance_km"),
        "duration_seconds": workout.get("duration_seconds"),
        "point_count": len(points),
        "bounds": bounds(points),
    }


class HealthPitCoordinator(DataUpdateCoordinator[dict[str, Any]]):
    """Serves what the apps pushed. Nothing is polled, so there is no interval."""

    def __init__(self, hass: HomeAssistant, store: HealthPitStore) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name="Healthpit",
            update_interval=None,
            always_update=False,
        )
        self.store = store

    async def _async_update_data(self) -> dict[str, Any]:
        return self._current_data()

    def _current_data(self) -> dict[str, Any]:
        users: dict[str, Any] = {}
        for user_id in self.store.user_ids():
            users[user_id] = {
                "name": self.store.user_name(user_id),
                **build_user_data(
                    self.store.latest_metrics(user_id),
                    self.store.unified_workouts(user_id),
                ),
            }
        return {"users": users}

    def user_data(self, user_id: str) -> dict[str, Any]:
        return (self.data or {}).get("users", {}).get(user_id, {})

    def user_ids(self) -> list[str]:
        return list((self.data or {}).get("users", {}))

    @callback
    def async_handle_push(self) -> None:
        """Recompute and notify entities after the store changed."""
        self.async_set_updated_data(self._current_data())
