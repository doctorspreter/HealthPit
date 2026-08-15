"""Sensor entities, created per Healthpit user as their data arrives."""

from __future__ import annotations

from typing import Any
from urllib.parse import quote

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import API_BASE, DOMAIN
from .coordinator import HealthPitCoordinator
from .entity import (
    category_device_info,
    user_device_info,
    exercise_device_info,
    HealthPitUserEntity,
)
from .precision import rounded_value, suggested_precision


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Create an entity for every value received, for every user."""
    coordinator: HealthPitCoordinator = hass.data[DOMAIN]
    known: set[str] = set()

    def _ensure_devices() -> None:
        """Create the user device before anything points at it.

        The area devices name the user device as their ``via_device``. If that
        parent does not exist yet, Home Assistant refuses the child — and with
        it the entity, which is why the history import then answered 409: the
        sensor it was looking for had never been created.
        """
        registry = dr.async_get(hass)
        for user_id in coordinator.user_ids():
            registry.async_get_or_create(
                config_entry_id=entry.entry_id, **user_device_info(coordinator, user_id)
            )

    def _new_entities() -> list[SensorEntity]:
        _ensure_devices()
        entities: list[SensorEntity] = []
        for user_id in coordinator.user_ids():
            entities.extend(_new_metric_sensors(coordinator, user_id, known))
            entities.extend(_new_workout_sensors(coordinator, user_id, known))
            entities.extend(_new_exercise_sensors(coordinator, user_id, known))
            route_key = f"{user_id}:route"
            if route_key not in known:
                known.add(route_key)
                entities.append(HealthPitRouteSensor(coordinator, user_id))
        return entities

    async_add_entities(_new_entities())

    @callback
    def _add_new() -> None:
        # A new phone, a new metric or a whole new user shows up while running.
        if new_entities := _new_entities():
            async_add_entities(new_entities)

    entry.async_on_unload(coordinator.async_add_listener(_add_new))


def _new_metric_sensors(
    coordinator: HealthPitCoordinator,
    user_id: str,
    known: set[str],
) -> list[SensorEntity]:
    entities: list[SensorEntity] = []
    user_data = coordinator.user_data(user_id)
    for category, items in (user_data.get("by_category") or {}).items():
        for item in items:
            metric_id = item.get("id")
            device_id = item.get("device_id") or "healthpit"
            key = f"{user_id}:{device_id}:{category}:{metric_id}"
            if metric_id and key not in known:
                known.add(key)
                entities.append(
                    HealthPitMetricSensor(
                        coordinator, user_id, metric_id, category, device_id
                    )
                )
    return entities


def _new_workout_sensors(
    coordinator: HealthPitCoordinator,
    user_id: str,
    known: set[str],
) -> list[SensorEntity]:
    entities: list[SensorEntity] = []
    user_data = coordinator.user_data(user_id)
    for descriptor in user_data.get("workout_metrics") or []:
        descriptor_key = str(descriptor.get("key") or "")
        key = f"{user_id}:workout:{descriptor_key}"
        if descriptor_key and key not in known:
            known.add(key)
            entities.append(
                HealthPitWorkoutSensor(coordinator, user_id, descriptor_key)
            )
    return entities


def _new_exercise_sensors(
    coordinator: HealthPitCoordinator,
    user_id: str,
    known: set[str],
) -> list[SensorEntity]:
    """One sensor per exercise and value.

    Entities appear for exercises that actually have data — training fifteen
    machines gives about sixty sensors, not one for every entry in the
    catalogue.
    """
    entities: list[SensorEntity] = []
    for value in coordinator.store.exercise_values(user_id):
        exercise_id = str(value.get("exercise_id") or "")
        metric_id = str(value.get("metric_id") or "")
        if not metric_id:
            continue
        key = f"{user_id}:exercise:{exercise_id}:{metric_id}"
        if key in known:
            continue
        known.add(key)
        entities.append(
            HealthPitExerciseSensor(coordinator, user_id, exercise_id, metric_id)
        )
    return entities


class HealthPitExerciseSensor(HealthPitUserEntity, SensorEntity):
    """A value that belongs to one exercise – weight, reps, volume, RPE."""

    def __init__(
        self,
        coordinator: HealthPitCoordinator,
        user_id: str,
        exercise_id: str,
        metric_id: str,
    ) -> None:
        super().__init__(coordinator, user_id)
        self._exercise_id = exercise_id
        self._metric_id = metric_id
        self._attr_unique_id = f"{user_id}_exercise_{exercise_id}_{metric_id}"
        self._attr_device_info = (
            exercise_device_info(coordinator, user_id, exercise_id, self._exercise_name())
            if exercise_id
            else category_device_info(coordinator, user_id, "workouts")
        )

    def _value(self) -> dict[str, Any] | None:
        for item in self.coordinator.store.exercise_values(self._user_id):
            if (
                str(item.get("exercise_id") or "") == self._exercise_id
                and item.get("metric_id") == self._metric_id
            ):
                return item
        return None

    def _exercise_name(self) -> str:
        value = self._value() or {}
        return str(value.get("exercise_name") or self._exercise_id)

    @property
    def name(self) -> str | None:
        # Der Geraetename traegt schon die Uebung; hier steht nur noch, welcher
        # Wert es ist.
        return METRIC_LABELS.get(self._metric_id, self._metric_id)

    @property
    def native_value(self) -> Any:
        value = self._value()
        if value is None:
            return None
        for key in ("value", "text", "boolean"):
            if key in value:
                return value[key]
        return None

    @property
    def native_unit_of_measurement(self) -> str | None:
        value = self._value() or {}
        return UNIT_SYMBOLS.get(str(value.get("unit") or ""))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        value = self._value() or {}
        return {
            "metric_id": self._metric_id,
            "exercise_id": self._exercise_id,
            "exercise": value.get("exercise_name"),
            "set_index": value.get("set_index"),
            "measured_at": value.get("end"),
        }


# Beschriftungen der Kraftwerte. Englisch und fest, wie die Geraetenamen.
METRIC_LABELS = {
    "WRK_SET_WEIGHT": "Weight",
    "WRK_SET_REPS": "Repetitions",
    "WRK_SET_VOLUME": "Volume",
    "WRK_SET_RPE": "RPE",
    "WRK_SET_TYPE": "Set type",
    "WRK_SET_IS_PERSONAL_RECORD": "Personal record",
    "WRK_EXERCISE": "Exercise",
    "WRK_EQUIPMENT_SEAT": "Seat",
    "WRK_EQUIPMENT_BACKREST": "Backrest",
    "WRK_EQUIPMENT_HANDLE": "Handle",
    "WRK_EQUIPMENT_RANGE": "Range",
    "WRK_DURATION": "Duration",
    "WRK_ENERGY": "Energy",
}

UNIT_SYMBOLS = {"KG": "kg", "CNT": "", "SCORE": "", "S": "s", "KCAL": "kcal", "M": "m"}


class HealthPitMetricSensor(HealthPitUserEntity, SensorEntity):
    """A single Apple Health metric exposed as a Home Assistant sensor."""

    def __init__(
        self,
        coordinator: HealthPitCoordinator,
        user_id: str,
        metric_id: str,
        category: str,
        device_id: str,
    ) -> None:
        super().__init__(coordinator, user_id)
        self._metric_id = metric_id
        self._category = category
        self._device_id = device_id
        self._attr_unique_id = f"{user_id}_{device_id}_{category}_{metric_id}"
        # Nach Bereich gruppiert statt alles in einer langen Liste. Die
        # unique_id bleibt unveraendert, damit bestehende Entitaeten ihre ID
        # und ihre Historie behalten.
        self._attr_device_info = category_device_info(coordinator, user_id, category)

    def _item(self) -> dict[str, Any] | None:
        items = (self._user_data.get("by_category") or {}).get(self._category, [])
        for item in items:
            if item.get("id") == self._metric_id and (
                item.get("device_id") or "healthpit"
            ) == self._device_id:
                return item
        return None

    @property
    def name(self) -> str | None:
        item = self._item()
        return item.get("title") if item else self._metric_id

    @property
    def native_value(self) -> float | None:
        item = self._item()
        if item is None:
            return None
        return rounded_value(item.get("value"), suggested_precision(item))

    @property
    def suggested_display_precision(self) -> int | None:
        item = self._item()
        return suggested_precision(item) if item else None

    @property
    def native_unit_of_measurement(self) -> str | None:
        item = self._item()
        return (item.get("unit") if item else None) or None

    @property
    def icon(self) -> str | None:
        item = self._item()
        return item.get("icon") if item else None

    @property
    def device_class(self) -> str | None:
        item = self._item()
        return item.get("device_class") if item else None

    @property
    def state_class(self) -> str | None:
        item = self._item()
        return item.get("state_class") if item else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        item = self._item() or {}
        attributes: dict[str, Any] = {
            "category": self._category,
            "device_id": self._device_id,
            "aggregation": item.get("aggregation"),
            "measured_at": item.get("measured_at"),
            # The sensor id stays what it always was, so automations keep
            # working. What the value *is* now stands next to it.
            "metric_id": self._metric_id,
            "canonical_metric_id": item.get("canonical_metric_id"),
            "registry_category": item.get("registry_category"),
            "origin_provider": item.get("origin_provider"),
            "ingest_provider": item.get("ingest_provider"),
        }
        # Only worth showing when the value did not come straight from the
        # phone: it says which app or device really produced it.
        for optional in ("source_app_id", "observation_id", "unit_code", "period_type"):
            value = item.get(optional)
            if value:
                attributes[optional] = value
        return attributes


class HealthPitWorkoutSensor(HealthPitUserEntity, SensorEntity):
    """A stable latest/aggregate workout or exercise value."""

    def __init__(
        self,
        coordinator: HealthPitCoordinator,
        user_id: str,
        descriptor_key: str,
    ) -> None:
        super().__init__(coordinator, user_id)
        self._descriptor_key = descriptor_key
        self._attr_unique_id = f"{user_id}_workout_{descriptor_key}"
        self._attr_device_info = category_device_info(coordinator, user_id, "workouts")

    def _descriptor(self) -> dict[str, Any] | None:
        return next(
            (
                item
                for item in self._user_data.get("workout_metrics") or []
                if item.get("key") == self._descriptor_key
            ),
            None,
        )

    @property
    def name(self) -> str | None:
        item = self._descriptor()
        return item.get("name") if item else self._descriptor_key

    @property
    def native_value(self) -> Any:
        item = self._descriptor()
        if item is None:
            return None
        precision = suggested_precision(item, self._descriptor_key)
        return rounded_value(item.get("value"), precision)

    @property
    def suggested_display_precision(self) -> int | None:
        item = self._descriptor()
        return suggested_precision(item, self._descriptor_key) if item else None

    @property
    def native_unit_of_measurement(self) -> str | None:
        item = self._descriptor()
        return (item.get("unit") if item else None) or None

    @property
    def icon(self) -> str | None:
        item = self._descriptor()
        return item.get("icon") if item else "mdi:arm-flex"

    @property
    def device_class(self) -> str | None:
        item = self._descriptor()
        return item.get("device_class") if item else None

    @property
    def state_class(self) -> str | None:
        item = self._descriptor()
        return item.get("state_class") if item else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        item = self._descriptor() or {}
        return {
            "workout_metric": self._descriptor_key,
            **dict(item.get("attributes") or {}),
        }


class HealthPitRouteSensor(HealthPitUserEntity, SensorEntity):
    """The newest recorded track, as one entity instead of thousands.

    Its state is the distance, so it is a number worth charting. The attributes
    carry what a card or automation needs — the workout it belongs to, the
    bounding box to frame a map, and the links to fetch the geometry — but not
    the coordinates themselves: hundreds of them in a state attribute would blow
    up every recorder row.
    """

    _attr_translation_key = "last_route"
    _attr_icon = "mdi:map-marker-path"
    _attr_native_unit_of_measurement = "km"
    _attr_device_class = SensorDeviceClass.DISTANCE
    _attr_suggested_display_precision = 2

    def __init__(self, coordinator: HealthPitCoordinator, user_id: str) -> None:
        super().__init__(coordinator, user_id)
        self._attr_unique_id = f"{user_id}_route"

    @property
    def _route(self) -> dict[str, Any] | None:
        return self._user_data.get("route")

    @property
    def available(self) -> bool:
        return super().available and self._route is not None

    @property
    def native_value(self) -> float | None:
        route = self._route
        if route is None:
            return None
        distance = route.get("distance_km")
        return round(float(distance), 3) if distance is not None else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        route = self._route or {}
        workout_id = route.get("workout_id")
        slug = quote(str(workout_id or ""), safe="")
        base = f"{API_BASE}/workouts/{slug}/route"
        attributes: dict[str, Any] = {
            "workout_id": workout_id,
            "title": route.get("title"),
            "sport": route.get("sport"),
            "start": route.get("start"),
            "end": route.get("end"),
            "duration_seconds": route.get("duration_seconds"),
            "point_count": route.get("point_count"),
            "gpx": f"{base}.gpx" if workout_id else None,
            "geojson": f"{base}.geojson" if workout_id else None,
        }
        if isinstance(route.get("bounds"), dict):
            attributes |= {
                f"bounds_{key}": value for key, value in route["bounds"].items()
            }
        return attributes
