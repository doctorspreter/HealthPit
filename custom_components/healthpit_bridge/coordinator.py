"""Data coordinator for Healthpit metric sensors."""

from __future__ import annotations

import asyncio
from datetime import timedelta
import logging
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .api import BridgeAuthError, BridgeConnectionError, HealthpitBridgeClient
from .route_entities import build_route_points
from .workout_entities import build_workout_metrics

_LOGGER = logging.getLogger(__name__)


class HealthpitCoordinator(DataUpdateCoordinator[dict[str, Any]]):
    """Poll only the bridge metrics consumed by sensor entities."""

    def __init__(
        self,
        hass: HomeAssistant,
        client: HealthpitBridgeClient,
        *,
        username: str,
        scan_interval: int,
    ) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name="Healthpit Bridge",
            update_interval=timedelta(seconds=scan_interval),
            always_update=False,
        )
        self.client = client
        self.username = username

    async def _async_update_data(self) -> dict[str, Any]:
        try:
            metrics, workouts = await asyncio.gather(
                self.client.async_latest_metrics(),
                self.client.async_workouts(),
            )
        except BridgeAuthError as err:
            raise UpdateFailed(f"Authentication failed: {err}") from err
        except BridgeConnectionError as err:
            raise UpdateFailed(f"Cannot reach bridge: {err}") from err

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
                }
            )
        for items in by_category.values():
            items.sort(
                key=lambda item: (
                    str(item.get("device_id") or ""),
                    str(item.get("title") or item.get("id") or ""),
                )
            )
        route_points = build_route_points(workouts)
        return {
            "by_category": by_category,
            "metric_count": len(metrics),
            "workout_metrics": build_workout_metrics(workouts),
            "workout_count": len(workouts),
            "route_points": route_points,
            "route_point_count": len(route_points),
        }
