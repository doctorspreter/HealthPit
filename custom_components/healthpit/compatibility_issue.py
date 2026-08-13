"""Übergangscode – HEALTHPIT-COMPAT-2026-08.

The visible half of the compatibility layer: a repair notice in Home
Assistant when a device still runs the old app. Separate from
``compatibility.py`` so that module stays free of Home Assistant imports and
can be tested on its own.

To remove: see PROMPT-KOMPATIBILITAET-ENTFERNEN.md.
"""

from __future__ import annotations

import logging

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import issue_registry as ir

from .compatibility import (
    MARKER,
    RECOMMENDED_APP_MODEL_VERSION,
    issue_id,
)
from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)


@callback
def async_update_app_issue(
    hass: HomeAssistant, device_id: str, model_version: int
) -> None:
    """Raise or clear the "please update the app" notice for one device.

    Deliberately not an error: the data is accepted either way. The notice
    disappears by itself with the first push from an updated app, so nobody
    has to dismiss anything by hand.
    """
    identifier = issue_id(device_id)
    if model_version >= RECOMMENDED_APP_MODEL_VERSION:
        ir.async_delete_issue(hass, DOMAIN, identifier)
        return

    _LOGGER.debug(
        "%s: device %s still sends data model %s", MARKER, device_id, model_version
    )
    ir.async_create_issue(
        hass,
        DOMAIN,
        identifier,
        is_fixable=False,
        severity=ir.IssueSeverity.WARNING,
        translation_key="outdated_app",
        translation_placeholders={
            "device_id": device_id or "?",
            "model_version": str(model_version),
            "recommended": str(RECOMMENDED_APP_MODEL_VERSION),
        },
    )
