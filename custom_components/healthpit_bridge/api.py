"""Thin async client for the Healthpit Bridge REST API."""

from __future__ import annotations

from typing import Any
from urllib.parse import urlparse

import aiohttp


class BridgeAuthError(Exception):
    """Raised when the bridge rejects the credentials."""


class BridgeConnectionError(Exception):
    """Raised when the bridge cannot be reached."""


class BridgeRoleError(Exception):
    """Raised when the remote endpoint violates the master/slave topology."""


def normalize_bridge_connection(
    host: str,
    port: int,
    use_ssl: bool = False,
) -> tuple[str, int, bool, str]:
    """Accept host, host:port or full URL and return a clean bridge base."""
    raw_host = str(host or "").strip().rstrip("/")
    scheme = "https" if use_ssl else "http"
    clean_host = raw_host
    clean_port = int(port)

    if raw_host:
        parsed = urlparse(raw_host if "://" in raw_host else f"//{raw_host}")
        if parsed.scheme in ("http", "https"):
            scheme = parsed.scheme
        if parsed.hostname:
            clean_host = parsed.hostname
        try:
            if parsed.port:
                clean_port = int(parsed.port)
        except ValueError:
            pass

    url_host = (
        f"[{clean_host}]"
        if ":" in clean_host and not clean_host.startswith("[")
        else clean_host
    )
    return clean_host, clean_port, scheme == "https", f"{scheme}://{url_host}:{clean_port}"


class HealthpitBridgeClient:
    """Talks to the Healthpit bridge over its token-protected REST API."""

    def __init__(
        self,
        session: aiohttp.ClientSession,
        *,
        host: str,
        port: int,
        username: str,
        token: str,
        otp_secret: str | None = None,
        use_ssl: bool = False,
        verify_ssl: bool = True,
    ) -> None:
        self._session = session
        _, _, _, base = normalize_bridge_connection(
            host,
            port,
            use_ssl,
        )
        self._base = base
        self._username = username
        self._token = token
        self._otp_secret = otp_secret or ""
        self._verify_ssl = verify_ssl

    def update_auth(
        self,
        *,
        username: str | None = None,
        token: str | None = None,
        otp_secret: str | None = None,
    ) -> None:
        """Replace initial credentials with the exchanged session token."""
        if username:
            self._username = username
        if token:
            self._token = token
        if otp_secret is not None:
            self._otp_secret = otp_secret

    def _headers(self) -> dict[str, str]:
        headers = {
            "Authorization": f"Bearer {self._token}",
            "X-Healthpit-User": self._username,
        }
        if self._otp_secret:
            # The bridge accepts a pre-computed 6-digit OTP. When the user
            # stores the shared secret we compute the current code locally.
            headers["X-Healthpit-OTP"] = _current_otp(self._otp_secret)
        return headers

    async def _get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        url = f"{self._base}{path}"
        try:
            async with self._session.get(
                url,
                headers=self._headers(),
                params=params,
                ssl=self._verify_ssl,
                timeout=aiohttp.ClientTimeout(total=20),
            ) as resp:
                if resp.status in (401, 403):
                    raise BridgeAuthError(f"Bridge rejected credentials ({resp.status})")
                resp.raise_for_status()
                return await resp.json()
        except BridgeAuthError:
            raise
        except aiohttp.ClientError as err:
            raise BridgeConnectionError(str(err)) from err

    async def _get_bytes(self, path: str) -> bytes | None:
        """Fetch a binary payload. Returns None when the bridge has nothing to serve."""
        url = f"{self._base}{path}"
        try:
            async with self._session.get(
                url,
                headers=self._headers(),
                ssl=self._verify_ssl,
                timeout=aiohttp.ClientTimeout(total=20),
            ) as resp:
                if resp.status in (401, 403):
                    raise BridgeAuthError(f"Bridge rejected credentials ({resp.status})")
                if resp.status == 404:
                    return None
                resp.raise_for_status()
                return await resp.read()
        except BridgeAuthError:
            raise
        except aiohttp.ClientError as err:
            raise BridgeConnectionError(str(err)) from err

    async def _post(self, path: str, json: dict[str, Any] | None = None) -> Any:
        url = f"{self._base}{path}"
        try:
            async with self._session.post(
                url,
                headers=self._headers(),
                json=json,
                ssl=self._verify_ssl,
                timeout=aiohttp.ClientTimeout(total=180),
            ) as resp:
                if resp.status in (401, 403):
                    raise BridgeAuthError(f"Bridge rejected credentials ({resp.status})")
                resp.raise_for_status()
                return await resp.json()
        except BridgeAuthError:
            raise
        except aiohttp.ClientError as err:
            raise BridgeConnectionError(str(err)) from err

    async def async_create_session(
        self,
        *,
        api_token: str,
        otp_code: str,
        device_name: str = "Home Assistant",
        expires_days: int = 1825,
    ) -> dict[str, Any]:
        """Exchange API credentials plus a current OTP code for a revocable session."""
        url = f"{self._base}/v1/auth/session"
        payload = {
            "username": self._username,
            "api_token": api_token,
            "otp_code": otp_code,
            "device_name": device_name,
            "scope": "home_assistant",
            "client_app": "home_assistant",
            "node_role": "slave",
            "expires_days": expires_days,
        }
        try:
            async with self._session.post(
                url,
                json=payload,
                ssl=self._verify_ssl,
                timeout=aiohttp.ClientTimeout(total=20),
            ) as resp:
                if resp.status in (401, 403):
                    raise BridgeAuthError(f"Bridge rejected credentials ({resp.status})")
                if resp.status == 409:
                    raise BridgeRoleError(
                        "Master-to-master connections are not allowed"
                    )
                resp.raise_for_status()
                data = await resp.json()
                if (
                    data.get("node_role") != "slave"
                    or data.get("server_role") != "master"
                ):
                    raise BridgeRoleError(
                        "Docker must be master and Home Assistant must be slave"
                    )
                return data
        except (BridgeAuthError, BridgeRoleError):
            raise
        except aiohttp.ClientError as err:
            raise BridgeConnectionError(str(err)) from err

    async def _delete(self, path: str, params: dict[str, Any] | None = None) -> Any:
        url = f"{self._base}{path}"
        try:
            async with self._session.delete(
                url,
                headers=self._headers(),
                params=params,
                ssl=self._verify_ssl,
                timeout=aiohttp.ClientTimeout(total=20),
            ) as resp:
                if resp.status in (401, 403):
                    raise BridgeAuthError(f"Bridge rejected credentials ({resp.status})")
                resp.raise_for_status()
                return await resp.json()
        except BridgeAuthError:
            raise
        except aiohttp.ClientError as err:
            raise BridgeConnectionError(str(err)) from err

    async def async_health(self) -> dict[str, Any]:
        """Unauthenticated health check."""
        url = f"{self._base}/health"
        try:
            async with self._session.get(
                url,
                ssl=self._verify_ssl,
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp:
                resp.raise_for_status()
                return await resp.json()
        except aiohttp.ClientError as err:
            raise BridgeConnectionError(str(err)) from err

    async def async_latest_metrics(self) -> list[dict[str, Any]]:
        data = await self._get("/v1/health/latest")
        return data.get("metrics", [])

    async def async_otp_qr_png(self) -> bytes | None:
        """Return the master's TOTP enrolment code, or None when 2FA is off."""
        return await self._get_bytes("/v1/auth/otp-qr.png")

    async def async_bridge_status(self) -> dict[str, Any]:
        return await self._get("/v1/bridge/status")

    async def async_workouts(self) -> list[dict[str, Any]]:
        """Return merged workouts including every stored route point."""
        data = await self._get(
            "/v1/workouts/imports",
            params={
                "include_apple_health": "true",
                "include_route": "true",
                "route_max_points": 0,
                "limit": 1000,
            },
        )
        return data.get("workouts", [])

    async def async_sync_hevy(self) -> dict[str, Any]:
        return await self._post("/v1/fitness/hevy/sync")

    async def async_sync_garmin(self) -> dict[str, Any]:
        return await self._post("/v1/fitness/garmin/sync")

    async def async_save_workout_link(
        self,
        *,
        primary: str,
        linked: str,
        action: str,
    ) -> bool:
        data = await self._post(
            "/v1/workouts/links",
            json={"primary": primary, "linked": linked, "action": action},
        )
        return bool(data.get("saved"))

    async def async_delete_workout_link(
        self,
        *,
        primary: str,
        linked: str,
    ) -> bool:
        data = await self._delete(
            "/v1/workouts/links",
            params={"primary": primary, "linked": linked},
        )
        return bool(data.get("deleted"))

    async def async_delete_imported_workout(
        self,
        *,
        device_id: str,
        workout_id: str,
    ) -> bool:
        data = await self._delete(
            f"/v1/workouts/imports/{workout_id}",
            params={"device_id": device_id},
        )
        return bool(data.get("deleted"))


def _current_otp(secret: str, step: int = 30, digits: int = 6) -> str:
    """RFC 6238 TOTP, matching the bridge's own implementation."""
    import base64
    import hmac
    import struct
    import time
    from hashlib import sha1

    normalized = secret.replace(" ", "").upper()
    padding = "=" * ((8 - len(normalized) % 8) % 8)
    key = base64.b32decode(normalized + padding, casefold=True)
    counter = int(time.time() // step)
    digest = hmac.new(key, struct.pack(">Q", counter), sha1).digest()
    offset = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF) % (10**digits)
    return str(code).zfill(digits)
