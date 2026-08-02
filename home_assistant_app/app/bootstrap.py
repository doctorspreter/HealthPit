"""Bootstrap Home Assistant app options and persistent credentials."""

from __future__ import annotations

import base64
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import secrets
import shlex
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# Running this file by path puts its own directory on sys.path, not the package
# root, so "app.store" would not resolve. Keep the import working either way.
_PACKAGE_ROOT = str(Path(__file__).resolve().parent.parent)
if _PACKAGE_ROOT not in sys.path:
    sys.path.insert(0, _PACKAGE_ROOT)


DATA_PATH = Path(os.environ.get("HEALTHPIT_DATA_PATH", "/data"))
OPTIONS_PATH = Path(os.environ.get("OPTIONS_PATH", str(DATA_PATH / "options.json")))
GENERATED_SECRETS_PATH = Path(
    os.environ.get("GENERATED_SECRETS_PATH", str(DATA_PATH / "generated_secrets.json"))
)
RUNTIME_ENV_PATH = Path(os.environ.get("RUNTIME_ENV_PATH", str(DATA_PATH / "runtime.env")))
SUPERVISOR_URL = os.environ.get("SUPERVISOR_URL", "http://supervisor").rstrip("/")
DISCOVERY_SERVICE = "healthpit_bridge"

DEFAULT_OPTIONS: dict[str, object] = {
    "node_role": "master",
    "master_url": "",
    "master_username": "",
    "master_api_token": "",
    "master_otp_code": "",
    "bridge_username": "healthpit",
    "credential_mode": "automatic",
    "bridge_api_token": "",
    "otp_mode": "disabled",
    "bridge_otp_shared_secret": "",
    "app_session_expires_days": 1825,
    "hevy_api_key": "",
    "hevy_sync_enabled": False,
    "hevy_max_pages": 10,
    "hevy_sync_interval_minutes": 60,
    "garmin_email": "",
    "garmin_password": "",
    "garmin_sync_enabled": False,
    "garmin_activity_limit": 200,
    "log_level": "info",
}

# The Configuration tab groups the options so the providers stay separated.
# Internally the flat names above are kept, because the environment, the
# database and the Docker variant all use them.
GROUPED_OPTIONS: dict[str, dict[str, str]] = {
    "garmin": {
        "enabled": "garmin_sync_enabled",
        "email": "garmin_email",
        "password": "garmin_password",
        "activity_limit": "garmin_activity_limit",
    },
    "hevy": {
        "enabled": "hevy_sync_enabled",
        "api_key": "hevy_api_key",
        "max_pages": "hevy_max_pages",
        "interval_minutes": "hevy_sync_interval_minutes",
    },
    "access": {
        "username": "bridge_username",
        "token_mode": "credential_mode",
        "api_token": "bridge_api_token",
        "two_factor_mode": "otp_mode",
        "totp_secret": "bridge_otp_shared_secret",
        "session_days": "app_session_expires_days",
    },
    "topology": {
        "role": "node_role",
        "master_url": "master_url",
        "master_username": "master_username",
        "master_api_token": "master_api_token",
        "master_otp_code": "master_otp_code",
    },
    "system": {
        "log_level": "log_level",
    },
}


def flatten_options(raw: dict[str, object]) -> dict[str, object]:
    """Merge grouped options into the flat internal names.

    Options written by an older, ungrouped release are still honoured, so an
    existing installation keeps working until Home Assistant rewrites the file.
    """
    flat = {key: value for key, value in raw.items() if key not in GROUPED_OPTIONS}
    for group, fields in GROUPED_OPTIONS.items():
        section = raw.get(group)
        if not isinstance(section, dict):
            continue
        for field, internal in fields.items():
            if field in section:
                flat[internal] = section[field]
    return flat


def read_json(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    return value if isinstance(value, dict) else {}


def write_private_json(path: Path, value: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(f"{path.suffix}.tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.chmod(0o600)
    temporary.replace(path)
    path.chmod(0o600)


def normalize_totp_secret(value: object) -> str:
    return "".join(str(value or "").upper().split()).rstrip("=")


def valid_totp_secret(value: str) -> bool:
    if len(value) < 16:
        return False
    padding = "=" * ((8 - len(value) % 8) % 8)
    try:
        return len(base64.b32decode(value + padding, casefold=True)) >= 10
    except Exception:  # noqa: BLE001
        return False


def generate_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def normalize_master_url(value: object) -> str:
    """Accept "host", "host:port" and full URLs, and return a usable base URL."""
    text = str(value or "").strip().rstrip("/")
    if not text:
        return ""
    if "://" not in text:
        text = f"http://{text}"
    if ":" not in text.split("://", 1)[1]:
        text = f"{text}:8088"
    return text


def normalized_mode(value: object, allowed: set[str], default: str) -> str:
    mode = str(value or default).strip().lower()
    return mode if mode in allowed else default


def int_option(options: dict[str, object], key: str, default: int, low: int, high: int) -> int:
    try:
        value = int(options.get(key, default))
    except (TypeError, ValueError):
        value = default
    return max(low, min(value, high))


def bool_text(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return "true" if str(value).strip().lower() in {"1", "true", "yes", "on"} else "false"


def resolve_options() -> tuple[dict[str, object], dict[str, str]]:
    options = {**DEFAULT_OPTIONS, **flatten_options(read_json(OPTIONS_PATH))}
    generated = {
        key: str(value)
        for key, value in read_json(GENERATED_SECRETS_PATH).items()
        if isinstance(value, str)
    }

    username = str(options.get("bridge_username") or "healthpit").strip()
    if not 1 <= len(username) <= 80:
        raise ValueError("bridge_username must contain between 1 and 80 characters")

    credential_mode = normalized_mode(
        options.get("credential_mode"), {"automatic", "manual"}, "automatic"
    )
    configured_token = str(options.get("bridge_api_token") or "").strip()
    if credential_mode == "automatic":
        api_token = configured_token or generated.get("bridge_api_token", "")
        if len(api_token) < 32:
            api_token = secrets.token_urlsafe(48)
        generated["bridge_api_token"] = api_token
    else:
        api_token = configured_token
        if len(api_token) < 32:
            raise ValueError(
                "bridge_api_token must contain at least 32 characters in manual mode"
            )

    otp_mode = normalized_mode(
        options.get("otp_mode"), {"disabled", "automatic", "manual"}, "disabled"
    )
    configured_otp = normalize_totp_secret(options.get("bridge_otp_shared_secret"))
    if otp_mode == "disabled":
        otp_secret = ""
    elif otp_mode == "automatic":
        otp_secret = configured_otp or generated.get("bridge_otp_shared_secret", "")
        if not valid_totp_secret(otp_secret):
            otp_secret = generate_totp_secret()
        generated["bridge_otp_shared_secret"] = otp_secret
    else:
        otp_secret = configured_otp
        if not valid_totp_secret(otp_secret):
            raise ValueError("bridge_otp_shared_secret is not a valid Base32 TOTP secret")

    write_private_json(GENERATED_SECRETS_PATH, generated)

    node_role = normalized_mode(options.get("node_role"), {"master", "slave"}, "master")
    master_url = normalize_master_url(options.get("master_url"))
    master_username = str(options.get("master_username") or "").strip() or username
    master_api_token = str(options.get("master_api_token") or "").strip()
    master_otp_code = "".join(str(options.get("master_otp_code") or "").split())
    if node_role == "slave":
        if not master_url:
            raise ValueError("master_url is required when node_role is slave")
        if len(master_api_token) < 32:
            raise ValueError(
                "master_api_token must contain at least 32 characters when node_role is slave"
            )

    resolved = {
        **options,
        "node_role": node_role,
        "master_url": master_url,
        "master_username": master_username,
        "master_api_token": master_api_token,
        "master_otp_code": master_otp_code,
        "bridge_username": username,
        "credential_mode": credential_mode,
        "bridge_api_token": api_token,
        "otp_mode": otp_mode,
        "bridge_otp_shared_secret": otp_secret,
        "app_session_expires_days": int_option(
            options, "app_session_expires_days", 1825, 1, 3650
        ),
        "hevy_max_pages": int_option(options, "hevy_max_pages", 10, 1, 100),
        "hevy_sync_interval_minutes": int_option(
            options, "hevy_sync_interval_minutes", 60, 15, 1440
        ),
        "garmin_activity_limit": int_option(
            options, "garmin_activity_limit", 200, 1, 1000
        ),
    }
    environment = {
        "NODE_ROLE": node_role,
        "MASTER_URL": master_url,
        "MASTER_USERNAME": master_username,
        "MASTER_API_TOKEN": master_api_token,
        "MASTER_OTP_CODE": master_otp_code,
        "BRIDGE_USERNAME": username,
        "BRIDGE_API_TOKEN": api_token,
        "BRIDGE_OTP_SHARED_SECRET": otp_secret,
        "HEVY_API_KEY": str(resolved.get("hevy_api_key") or "").strip(),
        "HEVY_SYNC_ENABLED": bool_text(resolved.get("hevy_sync_enabled")),
        "HEVY_MAX_PAGES": str(resolved["hevy_max_pages"]),
        "HEVY_SYNC_INTERVAL_MINUTES": str(resolved["hevy_sync_interval_minutes"]),
        "GARMIN_EMAIL": str(resolved.get("garmin_email") or "").strip(),
        "GARMIN_PASSWORD": str(resolved.get("garmin_password") or ""),
        "GARMIN_SYNC_ENABLED": bool_text(resolved.get("garmin_sync_enabled")),
        "GARMIN_ACTIVITY_LIMIT": str(resolved["garmin_activity_limit"]),
        "DATABASE_PATH": str(DATA_PATH / "db" / "healthpit_bridge.sqlite3"),
        "OPTIONS_PATH": str(OPTIONS_PATH),
        "GENERATED_SECRETS_PATH": str(GENERATED_SECRETS_PATH),
        "LOG_LEVEL": str(resolved.get("log_level") or "info").lower(),
    }
    return resolved, environment


def write_runtime_environment(environment: dict[str, str]) -> None:
    RUNTIME_ENV_PATH.parent.mkdir(parents=True, exist_ok=True)
    content = "".join(
        f"export {key}={shlex.quote(value)}\n" for key, value in environment.items()
    )
    RUNTIME_ENV_PATH.write_text(content, encoding="utf-8")
    RUNTIME_ENV_PATH.chmod(0o600)


def sync_database(resolved: dict[str, object], environment: dict[str, str]) -> None:
    os.environ.update(environment)
    from app.store import (  # pylint: disable=import-outside-toplevel
        get_bridge_settings,
        init_db,
        revoke_all_app_sessions,
        save_bridge_settings,
        update_active_app_session_expirations,
    )

    init_db()
    current = get_bridge_settings()
    values = {
        "node_role": environment["NODE_ROLE"],
        "master_url": environment["MASTER_URL"],
        "master_username": environment["MASTER_USERNAME"],
        "master_api_token": environment["MASTER_API_TOKEN"],
        "bridge_username": environment["BRIDGE_USERNAME"],
        "bridge_api_token": environment["BRIDGE_API_TOKEN"],
        "bridge_otp_shared_secret": environment["BRIDGE_OTP_SHARED_SECRET"],
        "app_session_expires_days": str(resolved["app_session_expires_days"]),
        "hevy_api_key": environment["HEVY_API_KEY"],
        "hevy_sync_enabled": environment["HEVY_SYNC_ENABLED"],
        "hevy_max_pages": environment["HEVY_MAX_PAGES"],
        "hevy_sync_interval_minutes": environment["HEVY_SYNC_INTERVAL_MINUTES"],
        "garmin_email": environment["GARMIN_EMAIL"],
        "garmin_password": environment["GARMIN_PASSWORD"],
        "garmin_sync_enabled": environment["GARMIN_SYNC_ENABLED"],
        "garmin_activity_limit": environment["GARMIN_ACTIVITY_LIMIT"],
    }
    credential_keys = {
        "bridge_username",
        "bridge_api_token",
        "bridge_otp_shared_secret",
    }
    credentials_changed = any(current.get(key, "") != values[key] for key in credential_keys)
    lifetime_changed = current.get("app_session_expires_days", "1825") != values[
        "app_session_expires_days"
    ]
    save_bridge_settings(values)
    if credentials_changed:
        revoke_all_app_sessions()
    elif lifetime_changed:
        expires_at = (
            datetime.now(timezone.utc)
            + timedelta(days=int(values["app_session_expires_days"]))
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
        update_active_app_session_expirations(expires_at)


def supervisor_request(
    method: str, path: str, token: str, payload: dict[str, object] | None = None
) -> dict[str, object]:
    """Call the Supervisor API and return its data object."""
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(
        f"{SUPERVISOR_URL}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urlopen(request, timeout=10) as response:  # noqa: S310
        result = json.loads(response.read().decode("utf-8") or "{}")
    if not isinstance(result, dict):
        return {}
    data = result.get("data", result)
    return data if isinstance(data, dict) else {}


def register_supervisor_discovery(environment: dict[str, str]) -> None:
    """Advertise the app to the separately installed HACS integration."""
    token = os.environ.get("SUPERVISOR_TOKEN", "").strip()
    if not token:
        print("Supervisor discovery skipped outside Home Assistant OS")
        return

    try:
        app_info = supervisor_request("GET", "/addons/self/info", token)
        hostname = str(app_info.get("hostname") or app_info.get("ip_address") or "").strip()
        addon_slug = str(app_info.get("slug") or "").strip()
        if not hostname:
            raise ValueError("Supervisor did not return the app hostname")

        discovery_data = supervisor_request("GET", "/discovery", token)
        discoveries = discovery_data.get("discovery", [])
        if isinstance(discoveries, list):
            for item in discoveries:
                if not isinstance(item, dict):
                    continue
                if item.get("service") != DISCOVERY_SERVICE:
                    continue
                if addon_slug and item.get("addon") != addon_slug:
                    continue
                discovery_id = str(item.get("uuid") or "").strip()
                if discovery_id:
                    supervisor_request("DELETE", f"/discovery/{discovery_id}", token)

        supervisor_request(
            "POST",
            "/discovery",
            token,
            {
                "service": DISCOVERY_SERVICE,
                "config": {
                    "host": hostname,
                    "port": 8088,
                    "username": environment["BRIDGE_USERNAME"],
                    "use_ssl": False,
                    "verify_ssl": True,
                },
            },
        )
        print(f"Supervisor discovery registered for {hostname}:8088")
    except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError) as err:
        # Discovery improves setup but must never prevent the bridge from starting.
        print(f"Supervisor discovery unavailable: {err}")


def main() -> None:
    resolved, environment = resolve_options()
    write_runtime_environment(environment)
    sync_database(resolved, environment)
    register_supervisor_discovery(environment)
    print(
        "Healthpit configuration loaded: "
        f"user={environment['BRIDGE_USERNAME']}, "
        f"credentials={resolved['credential_mode']}, otp={resolved['otp_mode']}"
    )


if __name__ == "__main__":
    main()
