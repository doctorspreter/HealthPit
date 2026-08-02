"""Expose the bridge's 2FA enrolment code as a Home Assistant image entity."""

from __future__ import annotations

from datetime import datetime, timezone
import logging

from homeassistant.components.image import ImageEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .api import BridgeAuthError, BridgeConnectionError
from .const import CONF_USERNAME, DOMAIN
from .coordinator import HealthpitCoordinator

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up the 2FA QR image."""
    coordinator: HealthpitCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([HealthpitOtpQrImage(hass, coordinator, entry)])


class HealthpitOtpQrImage(CoordinatorEntity[HealthpitCoordinator], ImageEntity):
    """The TOTP enrolment code, scannable straight from a dashboard card."""

    _attr_has_entity_name = True
    _attr_name = "2FA code"
    _attr_icon = "mdi:qrcode"
    _attr_content_type = "image/png"
    _attr_entity_registry_enabled_default = True

    def __init__(
        self,
        hass: HomeAssistant,
        coordinator: HealthpitCoordinator,
        entry: ConfigEntry,
    ) -> None:
        CoordinatorEntity.__init__(self, coordinator)
        ImageEntity.__init__(self, hass)
        self._attr_unique_id = f"{entry.entry_id}_otp_qr"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.entry_id)},
            name=str(entry.data.get(CONF_USERNAME) or entry.title or "Fitness").strip()
            or "Fitness",
            manufacturer="Healthpit",
            model="Fitness user (slave)",
        )
        self._cached: bytes | None = None
        self._available = True

    @property
    def available(self) -> bool:
        return super().available and self._available

    async def async_image(self) -> bytes | None:
        """Fetch the current code. The bridge answers 404 while 2FA is disabled."""
        try:
            image = await self.coordinator.client.async_otp_qr_png()
        except (BridgeAuthError, BridgeConnectionError) as err:
            _LOGGER.debug("Could not load the 2FA code: %s", err)
            self._available = False
            return self._cached

        self._available = True
        if image is None:
            # Two-factor authentication is switched off; there is nothing to scan.
            self._cached = None
            return None
        if image != self._cached:
            self._cached = image
            self._attr_image_last_updated = datetime.now(timezone.utc)
        return image
