"""Sensor entities, created per Healthpit user as their data arrives."""

from __future__ import annotations

import logging
from typing import Any
from urllib.parse import quote

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import device_registry as dr, entity_registry as er
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.event import async_call_later

from .const import API_BASE, DOMAIN
from .coordinator import HealthPitCoordinator
from .entity import (
    category_device_info,
    gym_device_info,
    is_exercise_device,
    is_legacy_workouts_device,
    sport_device_info,
    user_device_info,
    HealthPitUserEntity,
)
from .history import async_import_history
from .metrics import EXERCISE_METRIC_LABELS, EXERCISE_UNIT_SYMBOLS
from .precision import rounded_value, suggested_precision

_LOGGER = logging.getLogger(__name__)


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
            # Dasselbe fuer das Dach ueber den Uebungen: Es traegt selbst keine
            # Entitaet, entstuende also nie von allein – und die Uebungen
            # lagen dann oben statt darunter.
            registry.async_get_or_create(
                config_entry_id=entry.entry_id, **gym_device_info(coordinator, user_id)
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

    def _clear_the_previous_layout_once() -> None:
        """Aufraeumen, bis es nichts mehr aufzuraeumen gibt — und dann nie wieder."""
        if coordinator.store.is_completed(PREVIOUS_LAYOUT_MARK):
            return
        if _clear_the_previous_layout(hass, entry, coordinator.user_ids()):
            coordinator.store.mark_completed(PREVIOUS_LAYOUT_MARK)

    def _drop_the_split_sports_once() -> None:
        """Die Reste der zersplitterten Sportarten, ein einziges Mal.

        „Outdoor Run" und „Laufen" waren zwei Sportarten, seit die Sportart als
        uebersetzter Anzeigename hereinkommt. Jetzt sind sie eine — und die
        Sensoren der aufgeloesten Schreibweisen entstehen nicht mehr, blieben
        aber als „nicht verfuegbar" stehen.

        Wieder mit Merker: eine Regel, die dauerhaft Entitaeten wegraeumt, weil
        gerade keine Beschreibung zu ihnen passt, wuerde beim ersten leeren
        Speicher alles mitnehmen.
        """
        if coordinator.store.is_completed(SPLIT_SPORTS_MARK):
            return
        if _drop_orphaned_workout_entities(hass, coordinator):
            coordinator.store.mark_completed(SPLIT_SPORTS_MARK)

    @callback
    def _fill_in_the_past(entities: list[SensorEntity]) -> None:
        """Nachtragen, sobald ein Trainings-Sensor neu entstanden ist.

        Ein neuer Sensor faengt bei null an. Alles, was er zeigt, ist aber eine
        Rechnung ueber Trainings, die Home Assistant laengst haelt — die
        Vergangenheit ist also da und muss nur geschrieben werden.

        Bisher tat das nur, wer danach fragte: GymPit nach dem Abgleich, die
        App beim Verlaufsimport. Wer beides nicht anstiess, sah leere Kurven,
        obwohl jede Zahl darin schon vorlag.

        Mit Verzoegerung, weil die Entitaet erst in der Registrierung stehen
        muss, bevor eine Statistik an ihr haengen kann.
        """
        if not any(isinstance(item, HealthPitWorkoutSensor) for item in entities):
            return

        async def _import(_now: Any = None) -> None:
            result = await async_import_history(hass, coordinator)
            _LOGGER.debug("Filled in %s statistics rows for new sensors", result)

        async_call_later(hass, 10, lambda now: hass.async_create_task(_import(now)))

    _clear_the_previous_layout_once()
    _drop_the_split_sports_once()
    initial = _new_entities()
    async_add_entities(initial)
    _fill_in_the_past(initial)

    @callback
    def _add_new() -> None:
        # A new phone, a new metric or a whole new user shows up while running.
        _clear_the_previous_layout_once()
        _drop_the_split_sports_once()
        if new_entities := _new_entities():
            async_add_entities(new_entities)
            _fill_in_the_past(new_entities)

    entry.async_on_unload(coordinator.async_add_listener(_add_new))


def workout_device_info(
    coordinator: HealthPitCoordinator,
    user_id: str,
    descriptor: dict[str, Any],
) -> DeviceInfo:
    """Which device a workout sensor belongs on.

    Strength training from GymPit goes to the gym device, where its exercises
    already are — splitting a session from the machines it was done on would
    put one training in two places. Everything else goes to the device of its
    sport, and an exercise aggregate always goes to the gym.
    """
    if descriptor.get("exercise_key") is not None:
        return gym_device_info(coordinator, user_id)
    sources = descriptor.get("sources") or []
    if "gympit" in sources:
        return gym_device_info(coordinator, user_id)
    sport_key = str(descriptor.get("sport_key") or "")
    if not sport_key:
        # Ohne Sportart bliebe nur das alte Sammelgeraet. Der Kraftraum ist die
        # bessere Heimat als ein Geraet, das wir gerade abschaffen.
        return gym_device_info(coordinator, user_id)
    return sport_device_info(
        coordinator, user_id, sport_key, str(descriptor.get("sport") or sport_key)
    )


# Der Umbau auf ein Geraet je Sportart (2.5.0). Der Name bleibt stehen, auch
# wenn spaeter weitere dazukommen: Er ist die Quittung dafuer, dass genau
# dieses Aufraeumen schon gelaufen ist.
PREVIOUS_LAYOUT_MARK = "cleared_workout_layout_before_2_5_0"


# Das Zusammenfuehren der Schreibweisen einer Sportart (2.5.2).
SPLIT_SPORTS_MARK = "dropped_split_sports_2_5_2"


def _drop_orphaned_workout_entities(
    hass: HomeAssistant,
    coordinator: HealthPitCoordinator,
) -> bool:
    """Remove workout sensors that no description produces any more.

    "Outdoor Run" and "Laufen" were two sports as long as the sport arrived as
    a translated display name and was compared letter for letter. Now they are
    one, and the sensors of the spellings that were folded in have nothing left
    feeding them.

    Returns whether it could do its work — which needs the descriptions to be
    there. Right after a restart the store may still be empty, and removing
    everything then would be exactly wrong.
    """
    entities = er.async_get(hass)
    done = True
    for user_id in coordinator.user_ids():
        current = {
            f"{user_id}_wk_{item.get('key')}"
            for item in coordinator.user_data(user_id).get("workout_metrics") or []
        }
        if not current:
            # Keine Beschreibungen: entweder hat der Anwender keine Trainings,
            # oder sie sind noch nicht geladen. Beides ist kein Grund, etwas zu
            # loeschen.
            done = False
            continue
        prefix = f"{user_id}_wk_sport:"
        for item in list(entities.entities.values()):
            if item.platform != DOMAIN or not item.unique_id.startswith(prefix):
                continue
            if item.unique_id not in current:
                entities.async_remove(item.entity_id)
    return done


def _clear_the_previous_layout(
    hass: HomeAssistant,
    entry: ConfigEntry,
    user_ids: list[str],
) -> bool:
    """Clear out the workout entities and devices of the layout before 2.5.0.

    Returns whether nothing of that layout is left — then the store notes it
    down and this never runs again.

    It must not become a standing rule: it deletes entities by a name pattern,
    and a pattern that keeps matching forever is a trap. The day something
    legitimately carries the old shape again it would disappear, and nobody
    would be told why.

    It can take two passes. A device is only removed once it holds nothing, and
    the exercise sensors of the version before move to the gym device at the
    moment they are added — a fraction later than this runs. So it keeps its
    hand in until one pass finds nothing left to do.
    """
    _retire_old_workout_entities(hass, user_ids)
    _remove_empty_legacy_devices(hass, entry, user_ids)
    return not _anything_left_of_the_previous_layout(hass, entry, user_ids)


def _anything_left_of_the_previous_layout(
    hass: HomeAssistant,
    entry: ConfigEntry,
    user_ids: list[str],
) -> bool:
    entities = er.async_get(hass)
    prefixes = tuple(f"{user_id}_workout_" for user_id in user_ids)
    if prefixes and any(
        item.platform == DOMAIN and item.unique_id.startswith(prefixes)
        for item in entities.entities.values()
    ):
        return True
    devices = dr.async_get(hass)
    return any(
        _is_from_the_previous_layout(device, user_ids)
        for device in dr.async_entries_for_config_entry(devices, entry.entry_id)
    )


def _is_from_the_previous_layout(device: dr.DeviceEntry, user_ids: list[str]) -> bool:
    return any(
        domain == DOMAIN
        and (
            is_exercise_device(identifier, user)
            or is_legacy_workouts_device(identifier, user)
        )
        for domain, identifier in device.identifiers
        for user in user_ids
    )


def _retire_old_workout_entities(hass: HomeAssistant, user_ids: list[str]) -> None:
    """Remove the workout sensors of the previous layout.

    They were all called ``{user}_workout_…`` and lived together on one
    "Workouts" device with German names — „Laufen Distanz", „Beinpresse
    Bestgewicht". Sport devices and the gym device replace them, under names
    that no longer carry the sport or the language.

    Left alone they would linger forever as unavailable rows: nothing feeds
    them any more, and Home Assistant keeps a registry entry until someone
    removes it. What they showed is rebuilt from the same workouts — the values
    are a calculation, not a recording, and the statistics are backdated with
    them.
    """
    entities = er.async_get(hass)
    prefixes = tuple(f"{user_id}_workout_" for user_id in user_ids)
    for entry in list(entities.entities.values()):
        if entry.platform != DOMAIN or entry.domain != "sensor":
            continue
        if entry.unique_id.startswith(prefixes):
            entities.async_remove(entry.entity_id)


def _remove_empty_legacy_devices(
    hass: HomeAssistant,
    entry: ConfigEntry,
    user_ids: list[str],
) -> None:
    """Clear out the devices of the previous layout once they are empty.

    Two kinds: the device every exercise used to have, and the single
    "Workouts" device that held every sport at once. Their sensors sit on the
    gym device and on the sport devices now.

    Only devices without a single entity are touched. As long as a sensor still
    hangs there the device stays: removing it would take the entity registry
    entry with it, and the sensor would come back under a new entity ID, its
    history orphaned.
    """
    devices = dr.async_get(hass)
    entities = er.async_get(hass)
    for device in dr.async_entries_for_config_entry(devices, entry.entry_id):
        if not _is_from_the_previous_layout(device, user_ids):
            continue
        if er.async_entries_for_device(
            entities, device.id, include_disabled_entities=True
        ):
            continue
        devices.async_remove_device(device.id)


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
        # Alle Uebungen auf einem Geraet. Die unique_id bleibt, was sie war,
        # damit bestehende Entitaeten ihre ID und ihre Historie behalten – nur
        # ihr Platz in der Geraeteliste aendert sich.
        self._attr_device_info = gym_device_info(coordinator, user_id)

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
        # Uebung und Wert stehen zusammen im Namen: das Geraet ist jetzt das
        # ganze Kraftraum-Geraet und sagt allein nicht mehr, worum es geht.
        label = METRIC_LABELS.get(self._metric_id, self._metric_id)
        exercise = self._exercise_name()
        return f"{exercise} {label}" if exercise else label

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
    def device_class(self) -> str | None:
        return DEVICE_CLASSES.get(self._metric_id)

    @property
    def state_class(self) -> str | None:
        """Nur Zahlen bekommen eine Zustandsklasse.

        Ohne sie fuehrt Home Assistant fuer den Sensor keine Langzeitstatistik –
        und dann haette auch die nachgetragene Vergangenheit nichts, woran sie
        haengen koennte. Satzart und Bestleistung sind Text und Ja/Nein; fuer
        die waere ein Mittelwert sinnlos.
        """
        number = (self._value() or {}).get("value")
        if isinstance(number, bool) or not isinstance(number, (int, float)):
            return None
        return "measurement"

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


# Beschriftungen und Einheiten stehen bei den Metriken, nicht hier: der
# Nachtrag der Vergangenheit braucht dieselbe Tabelle.
METRIC_LABELS = EXERCISE_METRIC_LABELS
UNIT_SYMBOLS = EXERCISE_UNIT_SYMBOLS

# Nur dort, wo die Klasse wirklich passt. Eine falsche macht mehr Schaden als
# keine: Home Assistant rechnet dann Einheiten um, die nichts miteinander zu
# tun haben. Das Satzvolumen ist kein Gewicht, sondern Wiederholungen × Kilo.
DEVICE_CLASSES = {
    "WRK_SET_WEIGHT": SensorDeviceClass.WEIGHT,
    "WRK_DURATION": SensorDeviceClass.DURATION,
    "WRK_ENERGY": SensorDeviceClass.ENERGY,
}


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
        #
        # „Workouts" ist kein Bereich mehr, seit jede Sportart ihr eigenes
        # Geraet hat. Was hier trotzdem unter dieser Kategorie ankommt, ist
        # eine Gesamtzahl ueber alle Sportarten — die gehoert zur Person, nicht
        # zu einer von ihnen.
        self._attr_device_info = (
            user_device_info(coordinator, user_id)
            if category in {"workouts", "workout"}
            else category_device_info(coordinator, user_id, category)
        )

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
        # Bewusst eine neue Kennung: die alten Sensoren hiessen
        # `{user}_workout_…` und trugen Sportart und Sprache in ihrer
        # Entitaets-ID („peter_workouts_laufen_distanz"). Sie werden entfernt,
        # diese hier entstehen sauber neu.
        self._attr_unique_id = f"{user_id}_wk_{descriptor_key}"
        self._attr_device_info = workout_device_info(
            coordinator, user_id, self._descriptor() or {}
        )

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
