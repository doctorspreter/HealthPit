"""The Healthpit integration.

The apps push straight into Home Assistant; nothing is polled and no bridge is
involved. One config entry serves the whole household — every person's data is
kept apart by the long-lived access token they push with.
"""

from __future__ import annotations

import logging

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError

from .const import (
    DOMAIN,
    SERVICE_DELETE_WORKOUT,
    SERVICE_DELETE_WORKOUT_LINK,
    SERVICE_FORGET_USER,
    SERVICE_IMPORT_HISTORY,
    SERVICE_SAVE_WORKOUT_LINK,
)
from .coordinator import HealthpitCoordinator
from .history import async_import_history
from .http_api import async_register_views
from .store import HealthpitStore

_LOGGER = logging.getLogger(__name__)

PLATFORMS: list[Platform] = [Platform.SENSOR, Platform.IMAGE]
SERVICES = (
    SERVICE_DELETE_WORKOUT,
    SERVICE_SAVE_WORKOUT_LINK,
    SERVICE_DELETE_WORKOUT_LINK,
    SERVICE_IMPORT_HISTORY,
    SERVICE_FORGET_USER,
)


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up Healthpit from its config entry."""
    store = HealthpitStore(hass)
    await store.async_load()

    coordinator = HealthpitCoordinator(hass, store)
    # An empty store is a valid state, not a setup failure: the first push
    # fills it. There is nothing to reach out to that could fail here.
    await coordinator.async_refresh()

    hass.data[DOMAIN] = coordinator
    async_register_views(hass)
    _async_register_services(hass)
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload the config entry."""
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        coordinator: HealthpitCoordinator | None = hass.data.pop(DOMAIN, None)
        if coordinator is not None:
            # A delayed save may still be pending; do not lose the last push.
            await coordinator.store.async_save_now()
        for service in SERVICES:
            hass.services.async_remove(DOMAIN, service)
    return unloaded


async def async_remove_entry(hass: HomeAssistant, entry: ConfigEntry) -> None:
    """Drop everything the apps pushed when the entry is deleted."""
    await HealthpitStore(hass).async_remove()


def _async_register_services(hass: HomeAssistant) -> None:
    """Register the services that make sense without a dashboard."""

    def coordinator() -> HealthpitCoordinator:
        current = hass.data.get(DOMAIN)
        if not isinstance(current, HealthpitCoordinator):
            raise HomeAssistantError("Healthpit is not set up")
        return current

    def resolve_user(call: ServiceCall) -> str:
        """Pick the user a call applies to.

        With a single user the argument is unnecessary, so it stays optional.
        With several it becomes required — guessing would touch the wrong
        person's data.
        """
        requested = str(call.data.get("user_id") or "").strip()
        known = coordinator().store.user_ids()
        if requested:
            if requested not in known:
                raise HomeAssistantError(f"Unknown Healthpit user: {requested}")
            return requested
        if len(known) == 1:
            return known[0]
        if not known:
            raise HomeAssistantError("No Healthpit user has pushed any data yet")
        raise HomeAssistantError(
            "Several users are set up; pass user_id to say which one is meant"
        )

    async def async_delete_workout(call: ServiceCall) -> None:
        current = coordinator()
        user_id = resolve_user(call)
        device_id = str(call.data["device_id"]).strip()
        workout_id = str(call.data["workout_id"]).strip()
        if not device_id or not workout_id:
            raise HomeAssistantError("device_id and workout_id are required")
        if current.store.delete_workout(user_id, device_id, workout_id):
            current.async_handle_push()
        else:
            _LOGGER.info("Workout %s was not stored for %s", workout_id, device_id)

    async def async_save_workout_link(call: ServiceCall) -> None:
        current = coordinator()
        user_id = resolve_user(call)
        primary = str(call.data["primary"]).strip()
        linked = str(call.data["linked"]).strip()
        if not primary or not linked or primary == linked:
            raise HomeAssistantError("Two different workout keys are required")
        current.store.save_link(user_id, primary, linked, str(call.data["action"]))
        current.async_handle_push()

    async def async_delete_workout_link(call: ServiceCall) -> None:
        current = coordinator()
        user_id = resolve_user(call)
        primary = str(call.data["primary"]).strip()
        linked = str(call.data["linked"]).strip()
        if not primary or not linked:
            raise HomeAssistantError("primary and linked are required")
        if current.store.delete_link(user_id, primary, linked):
            current.async_handle_push()

    async def async_import_history_service(call: ServiceCall) -> dict:
        current = coordinator()
        requested = str(call.data.get("user_id") or "").strip() or None
        if requested and requested not in current.store.user_ids():
            raise HomeAssistantError(f"Unknown Healthpit user: {requested}")
        return await async_import_history(hass, current, requested)

    async def async_forget_user(call: ServiceCall) -> None:
        current = coordinator()
        user_id = str(call.data["user_id"]).strip()
        if not current.store.forget_user(user_id):
            raise HomeAssistantError(f"Unknown Healthpit user: {user_id}")
        current.async_handle_push()

    user_schema = {vol.Optional("user_id"): str}
    hass.services.async_register(
        DOMAIN,
        SERVICE_DELETE_WORKOUT,
        async_delete_workout,
        schema=vol.Schema(
            {
                vol.Required("device_id"): str,
                vol.Required("workout_id"): str,
                **user_schema,
            }
        ),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_SAVE_WORKOUT_LINK,
        async_save_workout_link,
        schema=vol.Schema(
            {
                vol.Required("primary"): str,
                vol.Required("linked"): str,
                vol.Required("action"): vol.In(["merge", "separate"]),
                **user_schema,
            }
        ),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_DELETE_WORKOUT_LINK,
        async_delete_workout_link,
        schema=vol.Schema(
            {
                vol.Required("primary"): str,
                vol.Required("linked"): str,
                **user_schema,
            }
        ),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_IMPORT_HISTORY,
        async_import_history_service,
        schema=vol.Schema(user_schema),
        supports_response=SupportsResponse.OPTIONAL,
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_FORGET_USER,
        async_forget_user,
        schema=vol.Schema({vol.Required("user_id"): str}),
    )
