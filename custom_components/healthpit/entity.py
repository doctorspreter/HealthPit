"""Shared entity base: one Home Assistant device per Healthpit user."""

from __future__ import annotations

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import HealthPitCoordinator


def user_device_info(coordinator: HealthPitCoordinator, user_id: str) -> DeviceInfo:
    """One device per user, so their entities carry their name and stay apart."""
    name = coordinator.store.user_name(user_id)
    return DeviceInfo(
        identifiers={(DOMAIN, user_id)},
        name=name or "Healthpit",
        manufacturer="Healthpit",
        model="Fitness user",
    )


# Namen der Bereiche. Bewusst Englisch und fest: Ein Geraetename ist in Home
# Assistant Teil der Identitaet, er darf nicht mit der Oberflaechensprache
# wechseln.
CATEGORY_NAMES = {
    "activity": "Activity",
    "energy": "Energy",
    "heart": "Heart",
    "body": "Body",
    "nutrition": "Nutrition",
    "respiratory": "Respiratory",
    "temperature": "Temperature",
    "vitals": "Vitals",
    "environment": "Environment",
    "sleep": "Sleep",
    "cycle": "Cycle",
    "workouts": "Workouts",
    "workout": "Workouts",
}


def category_device_info(
    coordinator: HealthPitCoordinator, user_id: str, category: str
) -> DeviceInfo:
    """One device per area, hanging under the user.

    Without this every value of a person sits in one long list. With it, Home
    Assistant groups them the way the app does — body values together, heart
    values together — and the user device stays the roof above them.

    This changes no entity ID. In Home Assistant the device is separate from
    the entity ID, so history and automations survive the regrouping.
    """
    name = CATEGORY_NAMES.get(category, category.title())
    return DeviceInfo(
        identifiers={(DOMAIN, f"{user_id}_{category}")},
        name=name,
        manufacturer="Healthpit",
        model="Health area",
        via_device=(DOMAIN, user_id),
    )


def exercise_device_info(
    coordinator: HealthPitCoordinator, user_id: str, exercise_id: str, name: str
) -> DeviceInfo:
    """One device per exercise: weight, reps, volume and RPE belong together.

    A single "set weight" sensor would jump between exercises with every set —
    45 kg on the abductor, then 80 on the leg press. As a device per exercise
    each history line means one thing.
    """
    return DeviceInfo(
        identifiers={(DOMAIN, f"{user_id}_exercise_{exercise_id}")},
        name=name or exercise_id,
        manufacturer="Healthpit",
        model="Exercise",
        via_device=(DOMAIN, f"{user_id}_workouts"),
    )


class HealthPitUserEntity(CoordinatorEntity[HealthPitCoordinator]):
    """Base for everything that belongs to one user.

    ``has_entity_name`` combined with the per-user device means Home Assistant
    builds entity IDs like ``sensor.peter_schritte`` on its own — two people with
    the same metric never collide.
    """

    _attr_has_entity_name = True

    def __init__(self, coordinator: HealthPitCoordinator, user_id: str) -> None:
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
