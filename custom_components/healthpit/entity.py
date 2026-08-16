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
    # Der Name traegt den Anwender mit: „Peter Body“, nicht „Body“. Bei zwei
    # Personen im Haushalt stuenden sonst zwei Geraete gleichen Namens
    # nebeneinander, und Home Assistant leitet aus dem Geraetenamen auch die
    # Entitaets-IDs ab – aus sensor.body_weight wuerde sensor.body_weight_2.
    area = CATEGORY_NAMES.get(category, category.title())
    name = f"{coordinator.store.user_name(user_id) or 'Healthpit'} {area}"
    return DeviceInfo(
        identifiers={(DOMAIN, f"{user_id}_{category}")},
        name=name,
        manufacturer="Healthpit",
        model="Health area",
        via_device=(DOMAIN, user_id),
    )


def gym_device_info(coordinator: HealthPitCoordinator, user_id: str) -> DeviceInfo:
    """Where every strength value lives: one device for the whole gym.

    Each exercise used to get a device of its own. In Home Assistant's device
    list those are not nested under anything — "Peter Leg press" stood next to
    "Peter Body", and fifteen machines meant fifteen entries at the same level
    as the health areas. The grouping the hierarchy promised was nowhere to be
    seen.

    Now the exercises are entities on this single device and carry their name
    in the entity name instead. One line in the device list, everything about
    strength training behind it.

    It gets its own device rather than reusing the workouts area, because
    "Leg press" belongs with strength training, not with a run.
    """
    person = coordinator.store.user_name(user_id) or "Healthpit"
    return DeviceInfo(
        identifiers={(DOMAIN, f"{user_id}_gym")},
        name=f"{person} Gym workouts",
        manufacturer="Healthpit",
        model="Strength training",
        via_device=(DOMAIN, user_id),
    )


# Englische Namen der Sportarten fuer die Geraete.
#
# Die Sportart kommt aus den Daten und ist dort deutsch („Laufen"), weil die
# App deutsch ist. Ein Geraetename steckt aber in den Entitaets-IDs und darf
# sich mit der Sprache nicht aendern — deshalb hier die feste Uebersetzung.
SPORT_DEVICE_NAMES = {
    "laufen": "Run",
    "gehen": "Walk",
    "wandern": "Hike",
    "radfahren": "Cycling",
    "schwimmen": "Swim",
    "krafttraining": "Strength training",
    "rudern": "Rowing",
    "klettern": "Climbing",
    "yoga": "Yoga",
    "pilates": "Pilates",
    "hiit": "HIIT",
}


def sport_device_info(
    coordinator: HealthPitCoordinator,
    user_id: str,
    sport_key: str,
    sport: str,
) -> DeviceInfo:
    """One device per sport: „Peter Run", „Peter Cycling".

    All sports used to share a single "Workouts" device, which meant a run, a
    ride and every strength session hung in one list together. A sport is the
    natural drawer here — everything about running belongs together, and
    nothing about running belongs with a bench press.

    Only sports that actually have workouts get a device; the entity brings it
    into being.
    """
    person = coordinator.store.user_name(user_id) or "Healthpit"
    name = SPORT_DEVICE_NAMES.get(sport_key, sport)
    return DeviceInfo(
        identifiers={(DOMAIN, f"{user_id}_sport_{sport_key}")},
        name=f"{person} {name}",
        manufacturer="Healthpit",
        model="Sport",
        via_device=(DOMAIN, user_id),
    )


# Wie eine Uebung frueher ein eigenes Geraet bekam, und wie alle Sportarten
# frueher zusammen in einem Geraet lagen. Beides wird nur noch gebraucht, um
# genau diese Geraete wieder aufzuraeumen.
EXERCISE_DEVICE_PREFIX = "_exercise_"


def is_exercise_device(identifier: str, user_id: str) -> bool:
    """War das einmal ein Geraet je Uebung?"""
    return identifier.startswith(f"{user_id}{EXERCISE_DEVICE_PREFIX}")


def is_legacy_workouts_device(identifier: str, user_id: str) -> bool:
    """Das eine Sammelgeraet, das alle Sportarten zusammen hielt."""
    return identifier in {f"{user_id}_workouts", f"{user_id}_workout"}


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
