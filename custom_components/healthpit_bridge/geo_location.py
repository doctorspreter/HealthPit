"""Workout route points for Home Assistant's native map."""

from __future__ import annotations

from math import asin, cos, radians, sin, sqrt
from typing import Any

from homeassistant.components.geo_location import GeolocationEvent
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import UnitOfLength
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import HealthpitCoordinator

SOURCE = DOMAIN


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Create one geolocation entity for every stored workout route point."""
    coordinator: HealthpitCoordinator = hass.data[DOMAIN][entry.entry_id]
    known: set[str] = set()

    async_add_entities(_new_route_points(coordinator, entry, known))

    @callback
    def _add_new_route_points() -> None:
        new_entities = _new_route_points(coordinator, entry, known)
        if new_entities:
            async_add_entities(new_entities)

    entry.async_on_unload(coordinator.async_add_listener(_add_new_route_points))


def _new_route_points(
    coordinator: HealthpitCoordinator,
    entry: ConfigEntry,
    known: set[str],
) -> list[HealthpitRoutePoint]:
    """Create entities for route points that appeared after setup."""
    entities: list[HealthpitRoutePoint] = []
    for key in (coordinator.data or {}).get("route_points", {}):
        if key in known:
            continue
        known.add(key)
        entities.append(HealthpitRoutePoint(coordinator, entry, key, known))
    return entities


class HealthpitRoutePoint(CoordinatorEntity[HealthpitCoordinator], GeolocationEvent):
    """A single historical workout GPS sample shown on the native map."""

    _attr_should_poll = False
    _attr_source = SOURCE
    _attr_unit_of_measurement = UnitOfLength.KILOMETERS
    _attr_icon = "mdi:map-marker-path"

    def __init__(
        self,
        coordinator: HealthpitCoordinator,
        entry: ConfigEntry,
        point_key: str,
        known: set[str],
    ) -> None:
        super().__init__(coordinator)
        self._point_key = point_key
        self._known = known
        self._attr_unique_id = f"{entry.entry_id}_route_{point_key}"
        self._apply_descriptor()

    def _descriptor(self) -> dict[str, Any] | None:
        return (self.coordinator.data or {}).get("route_points", {}).get(
            self._point_key
        )

    def _apply_descriptor(self) -> None:
        descriptor = self._descriptor()
        if descriptor is None:
            return
        self._attr_name = str(descriptor.get("name") or "Workout route point")
        self._attr_latitude = float(descriptor["latitude"])
        self._attr_longitude = float(descriptor["longitude"])
        self._attr_distance = _distance_from_home(
            self.coordinator.hass,
            self._attr_latitude,
            self._attr_longitude,
        )

    @callback
    def _handle_coordinator_update(self) -> None:
        if self._descriptor() is None:
            self._known.discard(self._point_key)
            self.hass.async_create_task(self.async_remove(force_remove=True))
            return
        self._apply_descriptor()
        self.async_write_ha_state()

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        """Return route and workout context for this point."""
        descriptor = self._descriptor() or {}
        return {
            "node_role": "slave",
            "workout_id": descriptor.get("workout_id"),
            "sport": descriptor.get("sport"),
            "workout_title": descriptor.get("title"),
            "workout_source": descriptor.get("source"),
            "workout_sources": descriptor.get("sources") or [],
            "workout_start": descriptor.get("start"),
            "workout_end": descriptor.get("end"),
            "route_point": descriptor.get("point_number"),
            "route_points": descriptor.get("point_count"),
            "recorded_at": descriptor.get("timestamp"),
            "elevation": descriptor.get("elevation"),
            "heart_rate": descriptor.get("heart_rate"),
        }


def _distance_from_home(
    hass: HomeAssistant,
    latitude: float,
    longitude: float,
) -> float:
    """Return great-circle distance from Home Assistant's home in kilometres."""
    home_latitude = radians(float(hass.config.latitude))
    home_longitude = radians(float(hass.config.longitude))
    point_latitude = radians(latitude)
    point_longitude = radians(longitude)
    latitude_delta = point_latitude - home_latitude
    longitude_delta = point_longitude - home_longitude
    value = (
        sin(latitude_delta / 2) ** 2
        + cos(home_latitude)
        * cos(point_latitude)
        * sin(longitude_delta / 2) ** 2
    )
    return 6371.0088 * 2 * asin(sqrt(min(1.0, max(0.0, value))))
