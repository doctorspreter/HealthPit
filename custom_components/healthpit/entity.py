"""Shared entity base: one Home Assistant device per Healthpit user."""

from __future__ import annotations

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import HealthpitCoordinator


def user_device_info(coordinator: HealthpitCoordinator, user_id: str) -> DeviceInfo:
    """One device per user, so their entities carry their name and stay apart."""
    name = coordinator.store.user_name(user_id)
    return DeviceInfo(
        identifiers={(DOMAIN, user_id)},
        name=name or "Healthpit",
        manufacturer="Healthpit",
        model="Fitness user",
    )


class HealthpitUserEntity(CoordinatorEntity[HealthpitCoordinator]):
    """Base for everything that belongs to one user.

    ``has_entity_name`` combined with the per-user device means Home Assistant
    builds entity IDs like ``sensor.peter_schritte`` on its own — two people with
    the same metric never collide.
    """

    _attr_has_entity_name = True

    def __init__(self, coordinator: HealthpitCoordinator, user_id: str) -> None:
        super().__init__(coordinator)
        self._user_id = user_id
        self._attr_device_info = user_device_info(coordinator, user_id)

    @property
    def _user_data(self) -> dict:
        return self.coordinator.user_data(self._user_id)

    @property
    def available(self) -> bool:
        # A user whose data was forgotten has no bucket left; saying "unknown"
        # is more honest than keeping the last value on screen forever.
        return super().available and bool(self._user_data)
