"""Config flow for the Healthpit Bridge integration (Settings ▸ Devices & Services)."""

from __future__ import annotations

import logging
from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .api import (
    BridgeAuthError,
    BridgeConnectionError,
    BridgeRoleError,
    HealthpitBridgeClient,
    normalize_bridge_connection,
)
from .const import (
    CONF_HOST,
    CONF_OTP_CODE,
    CONF_PORT,
    CONF_SESSION_EXPIRES_DAYS,
    CONF_SESSION_TOKEN,
    CONF_TOKEN,
    CONF_USE_SSL,
    CONF_USERNAME,
    CONF_VERIFY_SSL,
    DEFAULT_PORT,
    DEFAULT_SESSION_EXPIRES_DAYS,
    DEFAULT_USERNAME,
    DOMAIN,
)


_LOGGER = logging.getLogger(__name__)


def discovery_config(discovery_info: Any) -> dict[str, Any]:
    """Return the payload of a Supervisor discovery message.

    Home Assistant hands the step a HassioServiceInfo dataclass whose payload
    sits in ``.config``; it is not a mapping. Older cores passed the dict
    straight through, so both shapes are accepted.
    """
    config = getattr(discovery_info, "config", None)
    if isinstance(config, dict):
        return config
    if isinstance(discovery_info, dict):
        return discovery_info
    return {}


def resolved_port(raw: Any, use_ssl: bool) -> int:
    """Empty means 8088, or 443 when the bridge sits behind HTTPS.

    An external address usually carries no port at all, so the field has to
    accept being left blank.
    """
    text = str(raw if raw is not None else "").strip()
    if not text:
        return 443 if use_ssl else DEFAULT_PORT
    try:
        port = int(text)
    except ValueError:
        return 443 if use_ssl else DEFAULT_PORT
    return port if 1 <= port <= 65535 else DEFAULT_PORT


def _schema(defaults: dict[str, Any] | None = None) -> vol.Schema:
    defaults = defaults or {}
    port_default = defaults.get(CONF_PORT, "")
    return vol.Schema(
        {
            vol.Required(CONF_HOST, default=defaults.get(CONF_HOST, "")): str,
            vol.Optional(CONF_PORT, default=str(port_default or "")): str,
            vol.Required(
                CONF_USERNAME, default=defaults.get(CONF_USERNAME, DEFAULT_USERNAME)
            ): str,
            vol.Required(CONF_TOKEN, default=defaults.get(CONF_TOKEN, "")): str,
            vol.Optional(CONF_OTP_CODE, default=""): str,
            vol.Optional(
                CONF_SESSION_EXPIRES_DAYS,
                default=defaults.get(CONF_SESSION_EXPIRES_DAYS, DEFAULT_SESSION_EXPIRES_DAYS),
            ): int,
            vol.Optional(CONF_USE_SSL, default=defaults.get(CONF_USE_SSL, False)): bool,
            vol.Optional(
                CONF_VERIFY_SSL, default=defaults.get(CONF_VERIFY_SSL, True)
            ): bool,
        }
    )


class HealthpitBridgeConfigFlow(ConfigFlow, domain=DOMAIN):
    """Handle the user-initiated setup."""

    VERSION = 1

    def __init__(self) -> None:
        self._discovery_defaults: dict[str, Any] = {}
        self._discovery_session_token = ""
        self._discovery_error = ""

    async def async_step_hassio(self, discovery_info: Any) -> ConfigFlowResult:
        """Handle discovery from the Healthpit Home Assistant app."""
        config = discovery_config(discovery_info)
        self._discovery_defaults = {
            CONF_HOST: str(config.get(CONF_HOST) or "").strip(),
            CONF_PORT: int(config.get(CONF_PORT) or DEFAULT_PORT),
            CONF_USERNAME: str(config.get(CONF_USERNAME) or DEFAULT_USERNAME).strip(),
            CONF_USE_SSL: bool(config.get(CONF_USE_SSL, False)),
            CONF_VERIFY_SSL: bool(config.get(CONF_VERIFY_SSL, True)),
        }
        if not self._discovery_defaults[CONF_HOST]:
            return self.async_abort(reason="invalid_discovery_info")
        # The app hands over a scoped, revocable session token. Neither the API
        # token nor the TOTP secret ever leaves it.
        self._discovery_session_token = str(
            config.get(CONF_SESSION_TOKEN) or ""
        ).strip()
        unique = (
            f"{self._discovery_defaults[CONF_HOST]}:"
            f"{self._discovery_defaults[CONF_PORT]}:"
            f"{self._discovery_defaults[CONF_USERNAME]}"
        )
        await self.async_set_unique_id(unique)
        self._abort_if_unique_id_configured()
        self.context["title_placeholders"] = {
            "host": self._discovery_defaults[CONF_HOST]
        }
        if self._discovery_session_token:
            return await self.async_step_hassio_confirm()
        return await self.async_step_user()

    async def async_step_hassio_confirm(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Confirm the app the Supervisor advertised; no credentials needed."""
        if user_input is None:
            return self.async_show_form(
                step_id="hassio_confirm",
                description_placeholders={
                    "host": self._discovery_defaults[CONF_HOST],
                    "username": self._discovery_defaults[CONF_USERNAME],
                },
            )

        defaults = self._discovery_defaults
        client = HealthpitBridgeClient(
            async_get_clientsession(self.hass),
            host=defaults[CONF_HOST],
            port=defaults[CONF_PORT],
            username=defaults[CONF_USERNAME],
            token=self._discovery_session_token,
            use_ssl=defaults.get(CONF_USE_SSL, False),
            verify_ssl=defaults.get(CONF_VERIFY_SSL, True),
        )
        try:
            health = await client.async_health()
            if health.get("node_role") != "master":
                raise BridgeRoleError("Remote endpoint is not a Healthpit master")
            await client.async_latest_metrics()
        except BridgeRoleError:
            return self.async_abort(reason="role_conflict")
        except BridgeAuthError as err:
            _LOGGER.warning("Discovered bridge rejected its own session: %s", err)
            self._discovery_error = "invalid_auth"
        except BridgeConnectionError as err:
            _LOGGER.warning("Discovered bridge at %s is unreachable: %s", defaults[CONF_HOST], err)
            self._discovery_error = "cannot_connect"
        except Exception:  # noqa: BLE001
            _LOGGER.exception("Unexpected error while confirming the discovered bridge")
            self._discovery_error = "unknown"

        if self._discovery_error:
            # Fall back to manual entry, but say why rather than silently
            # dropping the user into an empty form.
            return await self.async_step_user()

        return self.async_create_entry(
            title=f"Healthpit Bridge ({defaults[CONF_HOST]})",
            data={
                CONF_HOST: defaults[CONF_HOST],
                CONF_PORT: defaults[CONF_PORT],
                CONF_USERNAME: defaults[CONF_USERNAME],
                CONF_TOKEN: self._discovery_session_token,
                CONF_USE_SSL: defaults.get(CONF_USE_SSL, False),
                CONF_VERIFY_SSL: defaults.get(CONF_VERIFY_SSL, True),
            },
        )

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        if user_input is None and self._discovery_error:
            errors["base"] = self._discovery_error
            self._discovery_error = ""

        if user_input is not None:
            session = async_get_clientsession(self.hass)
            host, port, use_ssl, _base_url = normalize_bridge_connection(
                user_input[CONF_HOST],
                resolved_port(
                    user_input.get(CONF_PORT), user_input.get(CONF_USE_SSL, False)
                ),
                user_input.get(CONF_USE_SSL, False),
            )
            normalized_input = {
                **user_input,
                CONF_HOST: host,
                CONF_PORT: port,
                CONF_USE_SSL: use_ssl,
            }
            client = HealthpitBridgeClient(
                session,
                host=normalized_input[CONF_HOST],
                port=normalized_input[CONF_PORT],
                username=normalized_input[CONF_USERNAME],
                token=normalized_input[CONF_TOKEN],
                use_ssl=normalized_input.get(CONF_USE_SSL, False),
                verify_ssl=normalized_input.get(CONF_VERIFY_SSL, True),
            )
            try:
                health = await client.async_health()
                if health.get("node_role") != "master":
                    raise BridgeRoleError("Remote endpoint is not a Healthpit master")
                session_data = await client.async_create_session(
                    api_token=normalized_input[CONF_TOKEN],
                    otp_code=str(normalized_input.get(CONF_OTP_CODE) or "").strip(),
                    expires_days=int(
                        normalized_input.get(CONF_SESSION_EXPIRES_DAYS)
                        or DEFAULT_SESSION_EXPIRES_DAYS
                    ),
                )
                session_token = str(session_data.get("session_token") or "").strip()
                if not session_token:
                    errors["base"] = "invalid_auth"
                    return self.async_show_form(
                        step_id="user",
                        data_schema=_schema(normalized_input),
                        errors=errors,
                    )
                client.update_auth(token=session_token, otp_secret="")
                await client.async_latest_metrics()
            except BridgeAuthError:
                errors["base"] = "invalid_auth"
            except BridgeRoleError:
                errors["base"] = "role_conflict"
            except BridgeConnectionError:
                errors["base"] = "cannot_connect"
            except Exception:  # noqa: BLE001
                errors["base"] = "unknown"
            else:
                unique = (
                    f"{normalized_input[CONF_HOST]}:"
                    f"{normalized_input[CONF_PORT]}:"
                    f"{normalized_input[CONF_USERNAME]}"
                )
                await self.async_set_unique_id(unique)
                self._abort_if_unique_id_configured()
                return self.async_create_entry(
                    title=f"Healthpit Bridge ({normalized_input[CONF_HOST]})",
                    data={
                        CONF_HOST: normalized_input[CONF_HOST],
                        CONF_PORT: normalized_input[CONF_PORT],
                        CONF_USERNAME: normalized_input[CONF_USERNAME],
                        CONF_TOKEN: session_token,
                        CONF_USE_SSL: normalized_input.get(CONF_USE_SSL, False),
                        CONF_VERIFY_SSL: normalized_input.get(CONF_VERIFY_SSL, True),
                    },
                )

        return self.async_show_form(
            step_id="user",
            data_schema=_schema(user_input or self._discovery_defaults),
            errors=errors,
        )
