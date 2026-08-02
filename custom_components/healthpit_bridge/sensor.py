"""Sensor entities for the Healthpit Bridge integration."""

from __future__ import annotations

from typing import Any

from homeassistant.components.sensor import SensorEntity, SensorStateClass
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import CONF_USERNAME, DOMAIN
from .coordinator import HealthpitCoordinator


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Create one Home Assistant entity for every received health value."""
    coordinator: HealthpitCoordinator = hass.data[DOMAIN][entry.entry_id]

    known: set[str] = set()
    entities: list[SensorEntity] = [
        HealthpitBridgeContentSensor(coordinator, entry),
        *_new_metric_sensors(coordinator, entry, known),
        *_new_workout_sensors(coordinator, entry, known),
    ]

    async_add_entities(entities)

    @callback
    def _add_new_metric_sensors() -> None:
        new_entities = [
            *_new_metric_sensors(coordinator, entry, known),
            *_new_workout_sensors(coordinator, entry, known),
        ]
        if new_entities:
            async_add_entities(new_entities)

    entry.async_on_unload(coordinator.async_add_listener(_add_new_metric_sensors))


def _new_metric_sensors(
    coordinator: HealthpitCoordinator,
    entry: ConfigEntry,
    known: set[str],
) -> list[SensorEntity]:
    """Create sensors for metrics that appeared after setup."""
    entities: list[SensorEntity] = []
    for category, items in (coordinator.data or {}).get("by_category", {}).items():
        for item in items:
            metric_id = item.get("id")
            device_id = item.get("device_id") or "healthpit"
            sensor_key = f"{device_id}:{category}:{metric_id}"
            if metric_id and sensor_key not in known:
                known.add(sensor_key)
                entities.append(
                    HealthpitMetricSensor(
                        coordinator,
                        entry,
                        metric_id,
                        category,
                        device_id,
                    )
                )
    return entities


def _new_workout_sensors(
    coordinator: HealthpitCoordinator,
    entry: ConfigEntry,
    known: set[str],
) -> list[SensorEntity]:
    """Create stable sport and strength-exercise sensors."""
    entities: list[SensorEntity] = []
    for descriptor in (coordinator.data or {}).get("workout_metrics", []):
        key = str(descriptor.get("key") or "")
        sensor_key = f"workout:{key}"
        if key and sensor_key not in known:
            known.add(sensor_key)
            entities.append(HealthpitWorkoutSensor(coordinator, entry, key))
    return entities


def _healthpit_device_info(entry: ConfigEntry, device_id: str) -> DeviceInfo:
    return DeviceInfo(
        identifiers={(DOMAIN, entry.entry_id)},
        name=str(entry.data.get(CONF_USERNAME) or entry.title or "Fitness").strip() or "Fitness",
        manufacturer="Healthpit",
        model="Fitness user (slave)",
    )


class HealthpitMetricSensor(CoordinatorEntity[HealthpitCoordinator], SensorEntity):
    """A single Apple Health metric exposed as an HA sensor."""

    _attr_has_entity_name = False

    def __init__(
        self,
        coordinator: HealthpitCoordinator,
        entry: ConfigEntry,
        metric_id: str,
        category: str,
        device_id: str,
    ) -> None:
        super().__init__(coordinator)
        self._metric_id = metric_id
        self._category = category
        self._device_id = device_id
        self._attr_unique_id = f"{entry.entry_id}_{device_id}_{category}_{metric_id}"
        self._attr_device_info = _healthpit_device_info(entry, device_id)

    def _item(self) -> dict[str, Any] | None:
        for item in (self.coordinator.data or {}).get("by_category", {}).get(self._category, []):
            if item.get("id") == self._metric_id and (item.get("device_id") or "healthpit") == self._device_id:
                return item
        return None

    @property
    def name(self) -> str | None:
        item = self._item()
        return item.get("title") if item else self._metric_id

    @property
    def native_value(self) -> float | None:
        item = self._item()
        return item.get("value") if item else None

    @property
    def native_unit_of_measurement(self) -> str | None:
        item = self._item()
        unit = item.get("unit") if item else None
        return unit or None

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
        return {
            "category": self._category,
            "device_id": self._device_id,
            "aggregation": item.get("aggregation"),
            "measured_at": item.get("measured_at"),
            "metric_id": self._metric_id,
            "node_role": "slave",
        }


class HealthpitWorkoutSensor(CoordinatorEntity[HealthpitCoordinator], SensorEntity):
    """A stable latest/aggregate workout or exercise value."""

    _attr_has_entity_name = False

    def __init__(
        self,
        coordinator: HealthpitCoordinator,
        entry: ConfigEntry,
        descriptor_key: str,
    ) -> None:
        super().__init__(coordinator)
        self._descriptor_key = descriptor_key
        self._attr_unique_id = f"{entry.entry_id}_workout_{descriptor_key}"
        self._attr_device_info = _healthpit_device_info(entry, "workouts")

    def _descriptor(self) -> dict[str, Any] | None:
        return next(
            (
                item
                for item in (self.coordinator.data or {}).get("workout_metrics", [])
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
        return item.get("value") if item else None

    @property
    def native_unit_of_measurement(self) -> str | None:
        item = self._descriptor()
        unit = item.get("unit") if item else None
        return unit or None

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
            "node_role": "slave",
            **dict(item.get("attributes") or {}),
        }


class HealthpitBridgeContentSensor(CoordinatorEntity[HealthpitCoordinator], SensorEntity):
    """What the bridge actually stores, broken down by source and device.

    Without this it is impossible to tell from Home Assistant whether a source
    such as GymPit never reached the bridge or merely has not produced entities
    yet.
    """

    _attr_has_entity_name = True
    _attr_name = "Workouts on the bridge"
    _attr_icon = "mdi:database-search"
    _attr_state_class = SensorStateClass.MEASUREMENT
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(
        self,
        coordinator: HealthpitCoordinator,
        entry: ConfigEntry,
    ) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_bridge_content"
        self._attr_device_info = _healthpit_device_info(entry, "workouts")

    @property
    def native_value(self) -> int:
        return int((self.coordinator.data or {}).get("workout_count") or 0)

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        data = self.coordinator.data or {}
        return {
            "by_source": data.get("workouts_by_source", {}),
            "by_device": data.get("workouts_by_device", {}),
            "metric_count": data.get("metric_count", 0),
            "route_point_count": data.get("route_point_count", 0),
        }
