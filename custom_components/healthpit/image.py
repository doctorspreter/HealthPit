"""The last route as a picture — one entity per user, not one per GPS sample."""

from __future__ import annotations

from datetime import datetime
import logging

from homeassistant.components.image import ImageEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util

from .const import DOMAIN
from .coordinator import HealthpitCoordinator
from .entity import HealthpitUserEntity
from .route import as_svg

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Create one route picture per user."""
    coordinator: HealthpitCoordinator = hass.data[DOMAIN]
    known: set[str] = set()

    def _new_entities() -> list[ImageEntity]:
        entities: list[ImageEntity] = []
        for user_id in coordinator.user_ids():
            if user_id in known:
                continue
            known.add(user_id)
            entities.append(HealthpitRouteImage(hass, coordinator, user_id))
        return entities

    async_add_entities(_new_entities())

    @callback
    def _add_new() -> None:
        if new_entities := _new_entities():
            async_add_entities(new_entities)

    entry.async_on_unload(coordinator.async_add_listener(_add_new))


class HealthpitRouteImage(HealthpitUserEntity, ImageEntity):
    """Draws the newest recorded track.

    SVG keeps this dependency-free and tiny: the line is generated as text, so
    there is no image library involved and no map tile fetched.
    """

    _attr_translation_key = "last_route"
    _attr_icon = "mdi:map-marker-path"
    _attr_content_type = "image/svg+xml"

    def __init__(
        self,
        hass: HomeAssistant,
        coordinator: HealthpitCoordinator,
        user_id: str,
    ) -> None:
        HealthpitUserEntity.__init__(self, coordinator, user_id)
        ImageEntity.__init__(self, hass)
        self._attr_unique_id = f"{user_id}_last_route"
        self._drawn_workout: str | None = None

    @property
    def available(self) -> bool:
        return super().available and self._route is not None

    @property
    def _route(self) -> dict | None:
        return self._user_data.get("route")

    @callback
    def _handle_coordinator_update(self) -> None:
        route = self._route
        workout_id = str(route.get("workout_id")) if route else None
        if workout_id != self._drawn_workout:
            # A different run: tell Home Assistant the picture changed, otherwise
            # it keeps serving the cached one.
            self._drawn_workout = workout_id
            self._attr_image_last_updated = dt_util.utcnow()
        super()._handle_coordinator_update()

    async def async_image(self) -> bytes | None:
        route = self._route
        if route is None:
            return None
        workout = self.coordinator.store.workout(
            self._user_id, str(route.get("workout_id") or "")
        )
        if workout is None:
            return None
        return as_svg(workout)

    @property
    def extra_state_attributes(self) -> dict:
        route = self._route or {}
        return {
            "workout_id": route.get("workout_id"),
            "sport": route.get("sport"),
            "start": route.get("start"),
            "distance_km": route.get("distance_km"),
            "point_count": route.get("point_count"),
        }
