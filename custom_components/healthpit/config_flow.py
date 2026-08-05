"""Config flow for Healthpit.

There is nothing to connect to and no credential to enter: the apps push into
Home Assistant, and Home Assistant's own authentication is the login. Setup is
therefore a single confirmation, and one entry serves every user in the house —
each person is told apart by their own long-lived access token.
"""

from __future__ import annotations

from typing import Any

from homeassistant.config_entries import ConfigFlow, ConfigFlowResult

from .const import API_BASE, DOMAIN


class HealthpitConfigFlow(ConfigFlow, domain=DOMAIN):
    """Handle the user-initiated setup."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        if self._async_current_entries():
            return self.async_abort(reason="single_instance_allowed")

        if user_input is None:
            return self.async_show_form(
                step_id="user",
                description_placeholders={"api_path": API_BASE},
            )

        return self.async_create_entry(title="Healthpit", data={})
