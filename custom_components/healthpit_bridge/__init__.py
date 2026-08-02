"""The Healthpit Bridge integration."""

from __future__ import annotations

import logging

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .api import HealthpitBridgeClient
from .const import (
    CONF_HOST,
    CONF_OTP_SECRET,
    CONF_PORT,
    CONF_SCAN_INTERVAL,
    CONF_TOKEN,
    CONF_USE_SSL,
    CONF_USERNAME,
    CONF_VERIFY_SSL,
    DEFAULT_SCAN_INTERVAL,
    DOMAIN,
)
from .coordinator import HealthpitCoordinator

_LOGGER = logging.getLogger(__name__)

PLATFORMS: list[Platform] = [Platform.SENSOR, Platform.GEO_LOCATION, Platform.IMAGE]
SERVICE_DELETE_WORKOUT = "delete_workout"
SERVICE_SYNC_HEVY = "sync_hevy"
SERVICE_SYNC_GARMIN = "sync_garmin"
SERVICE_SAVE_WORKOUT_LINK = "save_workout_link"
SERVICE_DELETE_WORKOUT_LINK = "delete_workout_link"
SERVICES = (
    SERVICE_DELETE_WORKOUT,
    SERVICE_SYNC_HEVY,
    SERVICE_SYNC_GARMIN,
    SERVICE_SAVE_WORKOUT_LINK,
    SERVICE_DELETE_WORKOUT_LINK,
)


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up Healthpit Bridge from a config entry."""
    session = async_get_clientsession(hass)
    client = HealthpitBridgeClient(
        session,
        host=entry.data[CONF_HOST],
        port=entry.data[CONF_PORT],
        username=entry.data[CONF_USERNAME],
        token=entry.data[CONF_TOKEN],
        otp_secret=entry.data.get(CONF_OTP_SECRET) or None,
        use_ssl=entry.data.get(CONF_USE_SSL, False),
        verify_ssl=entry.data.get(CONF_VERIFY_SSL, True),
    )
    coordinator = HealthpitCoordinator(
        hass,
        client,
        username=entry.data[CONF_USERNAME],
        scan_interval=entry.data.get(CONF_SCAN_INTERVAL, DEFAULT_SCAN_INTERVAL),
    )
    await coordinator.async_config_entry_first_refresh()

    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = coordinator
    _async_register_services(hass)
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload a config entry."""
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        hass.data[DOMAIN].pop(entry.entry_id, None)
        if not hass.data[DOMAIN]:
            for service in SERVICES:
                hass.services.async_remove(DOMAIN, service)
            hass.data.pop(f"{DOMAIN}_services_registered", None)
    return unloaded


def _async_register_services(hass: HomeAssistant) -> None:
    """Register the bridge services that remain useful without a dashboard."""
    flag = f"{DOMAIN}_services_registered"
    if hass.data.get(flag):
        return

    def coordinator_from_call(call) -> HealthpitCoordinator:
        entry_id = call.data.get("entry_id")
        coordinators: dict[str, HealthpitCoordinator] = hass.data.get(DOMAIN, {})
        coordinator = (
            coordinators.get(entry_id)
            if entry_id
            else next(iter(coordinators.values()), None)
        )
        if coordinator is None:
            raise HomeAssistantError("Healthpit Bridge is not configured")
        return coordinator

    async def async_delete_workout(call) -> None:
        coordinator = coordinator_from_call(call)
        device_id = str(call.data["device_id"]).strip()
        workout_id = str(call.data["workout_id"]).strip()
        if not device_id or not workout_id:
            raise HomeAssistantError("device_id and workout_id are required")
        if device_id.startswith(f"{coordinator.username}-"):
            device_id = device_id[len(coordinator.username) + 1 :]
        deleted = await coordinator.client.async_delete_imported_workout(
            device_id=device_id,
            workout_id=workout_id,
        )
        await coordinator.async_request_refresh()
        if not deleted:
            _LOGGER.info(
                "Workout %s for device %s was not present on the bridge",
                workout_id,
                device_id,
            )

    async def async_sync_hevy(call) -> None:
        coordinator = coordinator_from_call(call)
        await coordinator.client.async_sync_hevy()
        await coordinator.async_request_refresh()

    async def async_sync_garmin(call) -> None:
        coordinator = coordinator_from_call(call)
        await coordinator.client.async_sync_garmin()
        await coordinator.async_request_refresh()

    async def async_save_workout_link(call) -> None:
        coordinator = coordinator_from_call(call)
        primary = str(call.data["primary"]).strip()
        linked = str(call.data["linked"]).strip()
        action = str(call.data["action"]).strip()
        if not primary or not linked or primary == linked:
            raise HomeAssistantError("Two different workout keys are required")
        await coordinator.client.async_save_workout_link(
            primary=primary,
            linked=linked,
            action=action,
        )

    async def async_delete_workout_link(call) -> None:
        coordinator = coordinator_from_call(call)
        primary = str(call.data["primary"]).strip()
        linked = str(call.data["linked"]).strip()
        if not primary or not linked:
            raise HomeAssistantError("primary and linked are required")
        await coordinator.client.async_delete_workout_link(
            primary=primary,
            linked=linked,
        )

    entry_schema = {vol.Optional("entry_id"): str}
    hass.services.async_register(
        DOMAIN,
        SERVICE_DELETE_WORKOUT,
        async_delete_workout,
        schema=vol.Schema(
            {
                vol.Required("device_id"): str,
                vol.Required("workout_id"): str,
                **entry_schema,
            }
        ),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_SYNC_HEVY,
        async_sync_hevy,
        schema=vol.Schema(entry_schema),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_SYNC_GARMIN,
        async_sync_garmin,
        schema=vol.Schema(entry_schema),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_SAVE_WORKOUT_LINK,
        async_save_workout_link,
        schema=vol.Schema(
            {
                **entry_schema,
                vol.Required("primary"): str,
                vol.Required("linked"): str,
                vol.Required("action"): vol.In(["merge", "separate"]),
            }
        ),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_DELETE_WORKOUT_LINK,
        async_delete_workout_link,
        schema=vol.Schema(
            {
                **entry_schema,
                vol.Required("primary"): str,
                vol.Required("linked"): str,
            }
        ),
    )
    hass.data[flag] = True
