from __future__ import annotations

import asyncio
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import logging
from pathlib import Path
import io
import secrets
import time
from urllib.parse import quote

from fastapi import Body, Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse, Response
import qrcode
from qrcode.image.pure import PyPNGImage

from app.garmin import sync_garmin_workouts
from app.hevy import sync_hevy_workouts
from app.models import (
    AppSessionCreateIn,
    HealthBatchIn,
    HealthMetricIn,
    ImportedWorkoutBatchIn,
    WorkoutLinkOverrideIn,
    WorkoutReconcileIn,
)
from app.store import (
    app_interface_data_summary,
    app_session_data_summary,
    bridge_setting_exists,
    create_app_session,
    delete_app_interface,
    delete_imported_workout,
    delete_missing_imported_workouts,
    delete_service_data,
    delete_workout_link_override,
    get_bridge_settings,
    hevy_summary,
    imported_workout_summary,
    init_db,
    list_app_sessions,
    list_latest,
    list_unified_workouts,
    list_workout_link_overrides,
    normalize_gympit_import_sources,
    normalized_client_app,
    revoke_all_app_sessions,
    revoke_app_session,
    save_bridge_settings,
    save_workout_link_override,
    service_data_summary,
    update_active_app_session_expirations,
    upsert_imported_workout,
    upsert_metric,
    valid_app_session,
)

app = FastAPI(
    title="Healthpit Bridge",
    version="1.1.0",
    docs_url=None,
    redoc_url=None,
)

logger = logging.getLogger("healthpit.bridge")
BRAND_ICON_PATH = Path(__file__).resolve().parent / "brand" / "icon.png"
_hevy_task: asyncio.Task | None = None
_garmin_task: asyncio.Task | None = None


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    errors = [
        {
            "field": ".".join(
                str(part) for part in error.get("loc", []) if part != "body"
            ),
            "message": error.get("msg", ""),
            "type": error.get("type", ""),
        }
        for error in exc.errors()
    ]
    logger.warning("Validation failed for %s: %s", request.url.path, errors)
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "detail": "Payload could not be processed.",
            "errors": errors,
        },
    )


def normalize_totp_secret(secret: str) -> str:
    return "".join(secret.upper().split()).rstrip("=")


def generate_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def secret_bytes(secret: str) -> bytes:
    normalized = normalize_totp_secret(secret)
    padding = "=" * ((8 - len(normalized) % 8) % 8)
    return base64.b32decode(normalized + padding, casefold=True)


def current_otp(secret: str, step: int, digits: int = 6) -> str:
    counter = step.to_bytes(8, "big")
    digest = hmac.new(secret_bytes(secret), counter, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    number = int.from_bytes(digest[offset : offset + 4], "big") & 0x7FFFFFFF
    return str(number % (10**digits)).zfill(digits)


def valid_otp(secret: str, value: str) -> bool:
    if not value:
        return False
    cleaned = "".join(ch for ch in value if ch.isdigit())
    if len(cleaned) != 6:
        return False
    try:
        now_step = int(time.time() // 30)
        return any(
            hmac.compare_digest(current_otp(secret, now_step + offset), cleaned)
            for offset in (-2, -1, 0, 1, 2)
        )
    except Exception:
        return False


def utc_text(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def bearer_token(authorization: str) -> str:
    prefix = "Bearer "
    if not authorization.startswith(prefix):
        return ""
    return authorization[len(prefix) :].strip()


def app_session_token_hash(token: str) -> str:
    return hashlib.sha256(
        f"healthpit-app-session:{token}".encode("utf-8")
    ).hexdigest()


def app_session_token_hash_candidates(token: str) -> list[str]:
    typo_prefix = "healt" + "pit-app-session"
    legacy_prefix = "health" + "app-app-session"
    return [
        app_session_token_hash(token),
        hashlib.sha256(f"{typo_prefix}:{token}".encode("utf-8")).hexdigest(),
        hashlib.sha256(f"{legacy_prefix}:{token}".encode("utf-8")).hexdigest(),
    ]


def valid_bearer_app_session(
    token: str,
    username: str,
    allowed_scopes: set[str],
) -> dict | None:
    for token_hash in app_session_token_hash_candidates(token):
        session = valid_app_session(
            token_hash,
            username,
            allowed_scopes=allowed_scopes,
        )
        if session:
            return session
    return None


def require_api_credentials(username: str, token: str, otp_code: str) -> None:
    current = get_bridge_settings()
    if not hmac.compare_digest(username, current["bridge_username"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bridge username",
        )
    if not hmac.compare_digest(token, current["bridge_api_token"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bridge token",
        )
    if current["bridge_otp_shared_secret"] and not valid_otp(
        current["bridge_otp_shared_secret"],
        otp_code,
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bridge OTP",
        )


def require_token(
    authorization: str = Header(default=""),
    x_healthpit_user: str = Header(default=""),
    x_healthpit_otp: str = Header(default=""),
) -> None:
    current = get_bridge_settings()
    if x_healthpit_user != current["bridge_username"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bridge username",
        )

    token = bearer_token(authorization)
    if token and valid_bearer_app_session(
        token,
        x_healthpit_user,
        allowed_scopes={"home_assistant"},
    ):
        return

    require_api_credentials(x_healthpit_user, token, x_healthpit_otp)


def require_workout_upload_token(
    authorization: str = Header(default=""),
    x_healthpit_user: str = Header(default=""),
    x_healthpit_otp: str = Header(default=""),
) -> dict | None:
    current = get_bridge_settings()
    if x_healthpit_user != current["bridge_username"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bridge username",
        )

    token = bearer_token(authorization)
    session = (
        valid_bearer_app_session(
            token,
            x_healthpit_user,
            allowed_scopes={"workout_import", "home_assistant"},
        )
        if token
        else None
    )
    if session:
        return session

    require_api_credentials(x_healthpit_user, token, x_healthpit_otp)
    return None


def metric(
    metric_id: str,
    title: str,
    value: float,
    unit: str = "",
    aggregation: str = "latest",
    icon: str | None = None,
    device_class: str | None = None,
    state_class: str | None = "measurement",
) -> HealthMetricIn:
    return HealthMetricIn(
        id=metric_id,
        category="workouts",
        title=title,
        value=value,
        unit=unit,
        measured_at=datetime.now(timezone.utc),
        aggregation=aggregation,
        icon=icon,
        device_class=device_class,
        state_class=state_class,
    )


def publish_imported_workout_metrics(
    device_id: str,
    batch: ImportedWorkoutBatchIn,
) -> None:
    summary = imported_workout_summary(device_id)
    metrics = [
        metric(
            "imported_workout_count",
            "Importierte Workouts",
            float(summary["workout_count"] or 0),
            aggregation="sum",
            icon="mdi:calendar-import",
            state_class="total",
        ),
        metric(
            "imported_workout_distance_total",
            "Importierte Workout-Distanz",
            float(summary["distance_km"] or 0),
            unit="km",
            aggregation="sum",
            icon="mdi:map-marker-distance",
            state_class="total",
        ),
    ]
    if batch.workouts:
        latest = max(batch.workouts, key=lambda item: item.start)
        duration_hours = max((latest.end - latest.start).total_seconds(), 0) / 3600
        metrics.append(
            metric(
                "latest_imported_workout_duration",
                "Letztes importiertes Workout Dauer",
                duration_hours,
                unit="h",
                aggregation="latest",
                icon="mdi:timer-outline",
                device_class="duration",
            )
        )
        if latest.average_heart_rate is not None:
            metrics.append(
                metric(
                    "latest_imported_workout_avg_heart_rate",
                    "Letztes importiertes Workout Puls",
                    float(latest.average_heart_rate),
                    unit="bpm",
                    aggregation="average",
                    icon="mdi:heart-pulse",
                )
            )
    for item in metrics:
        upsert_metric(device_id, item)


def normalized_bool_text(value: object, default: str = "false") -> str:
    text = str(value if value is not None else default).strip().lower()
    return "true" if text in {"1", "ja", "yes", "on", "true"} else "false"


def safe_int(value: object, default: int) -> int:
    try:
        return int(str(value or default))
    except ValueError:
        return default


def app_session_expires_days(current: dict[str, str]) -> int:
    return max(1, min(safe_int(current.get("app_session_expires_days"), 1825), 3650))


def merged_bridge_settings(
    data: dict[str, object],
    current: dict[str, str],
) -> tuple[dict[str, str], str]:
    section = str(data.get("section") or "").strip()
    if section not in {"security", "hevy", "garmin"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="section must be security, hevy or garmin",
        )

    merged = dict(current)

    def text(key: str) -> str:
        return str(data.get(key, "")).strip()

    if section == "security":
        if text("bridge_username"):
            merged["bridge_username"] = text("bridge_username")
        if text("bridge_api_token"):
            merged["bridge_api_token"] = text("bridge_api_token")
        if text("bridge_otp_shared_secret"):
            merged["bridge_otp_shared_secret"] = normalize_totp_secret(
                text("bridge_otp_shared_secret")
            )
        if text("app_session_expires_days"):
            merged["app_session_expires_days"] = str(
                max(
                    1,
                    min(safe_int(text("app_session_expires_days"), 1825), 3650),
                )
            )

    if section == "hevy":
        if "hevy_api_key" in data:
            merged["hevy_api_key"] = text("hevy_api_key")
        if text("hevy_max_pages"):
            merged["hevy_max_pages"] = text("hevy_max_pages")
        if text("hevy_sync_interval_minutes"):
            merged["hevy_sync_interval_minutes"] = text(
                "hevy_sync_interval_minutes"
            )
        if "hevy_sync_enabled" in data:
            merged["hevy_sync_enabled"] = normalized_bool_text(
                data.get("hevy_sync_enabled"),
                merged["hevy_sync_enabled"],
            )

    if section == "garmin":
        if "garmin_email" in data:
            merged["garmin_email"] = text("garmin_email")
        if "garmin_password" in data:
            merged["garmin_password"] = str(data.get("garmin_password", ""))
        if text("garmin_activity_limit"):
            merged["garmin_activity_limit"] = text("garmin_activity_limit")
        if "garmin_sync_enabled" in data:
            merged["garmin_sync_enabled"] = normalized_bool_text(
                data.get("garmin_sync_enabled"),
                merged["garmin_sync_enabled"],
            )

    if merged["hevy_sync_enabled"] not in {"true", "false"}:
        merged["hevy_sync_enabled"] = normalized_bool_text(
            merged["hevy_sync_enabled"],
            "false",
        )
    if not merged["hevy_max_pages"].isdigit():
        merged["hevy_max_pages"] = "10"
    if not merged["hevy_sync_interval_minutes"].isdigit():
        merged["hevy_sync_interval_minutes"] = "60"
    if merged["garmin_sync_enabled"] not in {"true", "false"}:
        merged["garmin_sync_enabled"] = normalized_bool_text(
            merged["garmin_sync_enabled"],
            "false",
        )
    if not merged["garmin_activity_limit"].isdigit():
        merged["garmin_activity_limit"] = "200"
    return merged, section


def security_credentials_changed(
    current: dict[str, str],
    merged: dict[str, str],
    section: str,
) -> bool:
    if section != "security":
        return False
    return any(
        current.get(key, "") != merged.get(key, "")
        for key in (
            "bridge_username",
            "bridge_api_token",
            "bridge_otp_shared_secret",
        )
    )


def session_lifetime_changed(
    current: dict[str, str],
    merged: dict[str, str],
    section: str,
) -> bool:
    return section == "security" and app_session_expires_days(
        current
    ) != app_session_expires_days(merged)


def apply_session_security_changes(
    current: dict[str, str],
    merged: dict[str, str],
    section: str,
) -> None:
    if security_credentials_changed(current, merged, section):
        revoke_all_app_sessions()
    elif session_lifetime_changed(current, merged, section):
        expires_at = utc_text(
            datetime.now(timezone.utc)
            + timedelta(days=app_session_expires_days(merged))
        )
        update_active_app_session_expirations(expires_at)


def configured_node_role(current: dict[str, str]) -> str:
    """Return the role this node runs in. Anything unknown falls back to master."""
    role = str(current.get("node_role") or "master").strip().lower()
    return role if role in {"master", "slave"} else "master"


def require_master_role(current: dict[str, str]) -> None:
    if configured_node_role(current) == "master":
        return
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail=(
            "This Healthpit node runs as a slave and cannot accept sessions. "
            "Connect to the configured master instead."
        ),
    )


def otp_provisioning_uri(current: dict[str, str]) -> str:
    secret = current.get("bridge_otp_shared_secret", "")
    if not secret:
        return ""
    label = quote(f"Healthpit Bridge:{current['bridge_username']}", safe="")
    issuer = quote("Healthpit Bridge", safe="")
    return f"otpauth://totp/{label}?secret={secret}&issuer={issuer}&digits=6&period=30"


def bridge_status_payload(current: dict[str, str]) -> dict:
    sessions = list_app_sessions()
    active_sessions = [row for row in sessions if row.get("active")]
    session_items = []
    for row in sessions:
        session_items.append(
            {
                "session_id": row.get("session_id", ""),
                "device_name": row.get("device_name", ""),
                "scope": row.get("scope", ""),
                "client_app": normalized_client_app(row),
                "raw_client_app": row.get("client_app", ""),
                "node_role": row.get("node_role", "slave"),
                "created_at": row.get("created_at", ""),
                "last_used_at": row.get("last_used_at", ""),
                "expires_at": row.get("expires_at", ""),
                "active": bool(row.get("active")),
                "data": app_session_data_summary(row),
            }
        )
    role = configured_node_role(current)
    return {
        "name": "Healthpit Bridge",
        "version": app.version,
        "node_role": role,
        "username": current["bridge_username"],
        "api_token_configured": bool(current["bridge_api_token"]),
        "otp_enabled": bool(current["bridge_otp_shared_secret"]),
        "app_session_expires_days": app_session_expires_days(current),
        "app_sessions": {
            "active": len(active_sessions),
            "total": len(sessions),
            "items": session_items,
        },
        "topology": {
            "role": role,
            "master": {
                "name": "Healthpit Bridge" if role == "master" else "Remote Healthpit master",
                "node_role": "master",
                "username": (
                    current["bridge_username"]
                    if role == "master"
                    else current.get("master_username") or current["bridge_username"]
                ),
                "url": "" if role == "master" else current.get("master_url", ""),
            },
            "accepts_slaves": role == "master",
            "active_slaves": len(active_sessions) if role == "master" else 0,
        },
        "interfaces": {
            "healthpit": app_interface_data_summary("healthpit"),
            "gympit": app_interface_data_summary("gympit"),
            "hevy": service_data_summary("hevy"),
            "garmin": service_data_summary("garmin"),
        },
        "hevy": {
            "enabled": bool(current["hevy_api_key"])
            and current["hevy_sync_enabled"] == "true",
            "api_key_configured": bool(current["hevy_api_key"]),
            "sync_enabled": current["hevy_sync_enabled"] == "true",
            "max_pages": safe_int(current["hevy_max_pages"], 10),
            "sync_interval_minutes": safe_int(
                current["hevy_sync_interval_minutes"],
                60,
            ),
            "last_attempt_at": current["hevy_last_attempt_at"],
            "last_success_at": current["hevy_last_success_at"],
            "last_error": current["hevy_last_error"],
            "last_imported_workouts": safe_int(
                current["hevy_last_imported_workouts"],
                0,
            ),
        },
        "garmin": {
            "enabled": bool(current["garmin_email"])
            and current["garmin_sync_enabled"] == "true",
            "email": current["garmin_email"],
            "email_configured": bool(current["garmin_email"]),
            "password_configured": bool(current["garmin_password"]),
            "sync_enabled": current["garmin_sync_enabled"] == "true",
            "activity_limit": safe_int(current["garmin_activity_limit"], 200),
            "last_attempt_at": current["garmin_last_attempt_at"],
            "last_success_at": current["garmin_last_success_at"],
            "last_error": current["garmin_last_error"],
            "last_imported_workouts": safe_int(
                current["garmin_last_imported_workouts"],
                0,
            ),
        },
    }


async def hevy_background_sync() -> None:
    while True:
        current = get_bridge_settings()
        interval = safe_int(current.get("hevy_sync_interval_minutes"), 60)
        enabled = current.get("hevy_sync_enabled") == "true"
        if enabled and current.get("hevy_api_key"):
            try:
                await asyncio.to_thread(sync_hevy_workouts)
            except Exception as error:
                logger.warning("Hevy background sync failed: %s", error)
        await asyncio.sleep(max(15, interval) * 60)


async def garmin_background_sync() -> None:
    while True:
        current = get_bridge_settings()
        if (
            current.get("garmin_sync_enabled") == "true"
            and current.get("garmin_email")
            and current.get("garmin_password")
        ):
            try:
                await asyncio.to_thread(sync_garmin_workouts)
            except Exception as error:
                logger.warning("Garmin background sync failed: %s", error)
        await asyncio.sleep(6 * 60 * 60)


@app.on_event("startup")
async def startup() -> None:
    global _hevy_task, _garmin_task
    init_db()
    if not bridge_setting_exists("app_session_expires_days"):
        current = get_bridge_settings()
        expires_days = app_session_expires_days(current)
        save_bridge_settings(
            {"app_session_expires_days": str(expires_days)}
        )
        update_active_app_session_expirations(
            utc_text(datetime.now(timezone.utc) + timedelta(days=expires_days))
        )
    _hevy_task = asyncio.create_task(hevy_background_sync())
    _garmin_task = asyncio.create_task(garmin_background_sync())


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "version": app.version,
        "node_role": configured_node_role(get_bridge_settings()),
        "brand_icon": "/brand/icon.png",
    }


@app.get("/brand/icon.png", include_in_schema=False)
def brand_icon() -> FileResponse:
    return FileResponse(BRAND_ICON_PATH, media_type="image/png")


@app.get("/v1/auth/otp-qr.png", dependencies=[Depends(require_token)])
def otp_qr_png() -> Response:
    """Render the TOTP enrolment code so Home Assistant can show it as an image."""
    uri = otp_provisioning_uri(get_bridge_settings())
    if not uri:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Two-factor authentication is disabled, so there is no code to scan.",
        )
    buffer = io.BytesIO()
    qrcode.make(uri, image_factory=PyPNGImage, box_size=8, border=3).save(buffer)
    return Response(
        content=buffer.getvalue(),
        media_type="image/png",
        headers={"Cache-Control": "no-store"},
    )


@app.post("/v1/auth/session")
def create_auth_session(payload: AppSessionCreateIn) -> dict:
    username = payload.username.strip()
    device_name = " ".join(payload.device_name.split()) or "App"
    require_api_credentials(username, payload.api_token.strip(), payload.otp_code)
    require_master_role(get_bridge_settings())
    if payload.node_role != "slave":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Master-to-master connections are not allowed. "
                "The Healthpit Bridge is already the master for this user."
            ),
        )

    current = get_bridge_settings()
    expires_days = payload.expires_days or app_session_expires_days(current)
    session_token = f"hbs_{secrets.token_urlsafe(48)}"
    session_id = secrets.token_urlsafe(18)
    expires_at = utc_text(
        datetime.now(timezone.utc) + timedelta(days=expires_days)
    )
    create_app_session(
        session_id=session_id,
        token_hash=app_session_token_hash(session_token),
        username=username,
        device_name=device_name,
        scope=payload.scope,
        client_app=payload.client_app,
        node_role=payload.node_role,
        expires_at=expires_at,
    )
    return {
        "session_token": session_token,
        "token_type": "bearer",
        "expires_at": expires_at,
        "device_name": device_name,
        "username": username,
        "scope": payload.scope,
        "client_app": payload.client_app,
        "node_role": payload.node_role,
        "server_role": "master",
    }


@app.get("/v1/health/latest", dependencies=[Depends(require_token)])
def latest() -> dict:
    return {"metrics": list_latest()}


@app.get("/v1/fitness/hevy", dependencies=[Depends(require_token)])
def hevy_fitness() -> dict:
    current = get_bridge_settings()
    return {
        "enabled": bool(current["hevy_api_key"])
        and current["hevy_sync_enabled"] == "true",
        "last_attempt_at": current["hevy_last_attempt_at"],
        "last_success_at": current["hevy_last_success_at"],
        "last_error": current["hevy_last_error"],
        "last_imported_workouts": int(
            current["hevy_last_imported_workouts"] or "0"
        ),
        **hevy_summary(),
    }


@app.post("/v1/fitness/hevy/sync", dependencies=[Depends(require_token)])
async def sync_hevy_from_api() -> dict:
    summary = await asyncio.to_thread(sync_hevy_workouts)
    return {"synced": True, **summary}


@app.post("/v1/fitness/garmin/sync", dependencies=[Depends(require_token)])
async def sync_garmin_from_api() -> dict:
    summary = await asyncio.to_thread(sync_garmin_workouts)
    return {"synced": True, **summary}


@app.get("/v1/bridge/status", dependencies=[Depends(require_token)])
def bridge_status() -> dict:
    return bridge_status_payload(get_bridge_settings())


@app.post("/v1/bridge/settings", dependencies=[Depends(require_token)])
async def update_bridge_settings_api(
    data: dict[str, object] = Body(default_factory=dict),
) -> dict:
    current = get_bridge_settings()
    merged, section = merged_bridge_settings(data, current)
    save_bridge_settings(merged)
    apply_session_security_changes(current, merged, section)
    if (
        section == "hevy"
        and merged["hevy_sync_enabled"] == "true"
        and merged["hevy_api_key"]
    ):
        asyncio.create_task(asyncio.to_thread(sync_hevy_workouts))
    if (
        section == "garmin"
        and merged["garmin_sync_enabled"] == "true"
        and merged["garmin_email"]
        and merged["garmin_password"]
    ):
        asyncio.create_task(asyncio.to_thread(sync_garmin_workouts))
    return {
        "saved": True,
        "bridge": bridge_status_payload(get_bridge_settings()),
    }


@app.post("/v1/bridge/otp/generate", dependencies=[Depends(require_token)])
def generate_bridge_otp_api() -> dict:
    current = get_bridge_settings()
    current["bridge_otp_shared_secret"] = generate_totp_secret()
    save_bridge_settings(current)
    revoke_all_app_sessions()
    return {
        "generated": True,
        "otp_secret": current["bridge_otp_shared_secret"],
        "bridge": bridge_status_payload(get_bridge_settings()),
    }


@app.post("/v1/bridge/otp/disable", dependencies=[Depends(require_token)])
def disable_bridge_otp_api() -> dict:
    current = get_bridge_settings()
    current["bridge_otp_shared_secret"] = ""
    save_bridge_settings(current)
    revoke_all_app_sessions()
    return {
        "disabled": True,
        "bridge": bridge_status_payload(get_bridge_settings()),
    }


@app.post(
    "/v1/bridge/sessions/revoke-all",
    dependencies=[Depends(require_token)],
)
def revoke_all_bridge_sessions_api() -> dict:
    return {
        "deleted": revoke_all_app_sessions(),
        "bridge": bridge_status_payload(get_bridge_settings()),
    }


@app.post(
    "/v1/bridge/sessions/{session_id}/revoke",
    dependencies=[Depends(require_token)],
)
def revoke_bridge_session_api(session_id: str) -> dict:
    return {
        "deleted": revoke_app_session(session_id.strip()),
        "bridge": bridge_status_payload(get_bridge_settings()),
    }


@app.delete(
    "/v1/bridge/interfaces/{client_app}",
    dependencies=[Depends(require_token)],
)
def delete_bridge_interface_api(client_app: str, delete_data: bool = False) -> dict:
    key = client_app.strip().lower()
    if key in {"healthpit", "gympit"}:
        result = delete_app_interface(key, delete_data=delete_data)
    elif key == "hevy":
        save_bridge_settings({"hevy_api_key": "", "hevy_sync_enabled": "false"})
        result = {
            "deleted_sessions": 0,
            "deleted_data": delete_service_data("hevy") if delete_data else {},
        }
    elif key == "garmin":
        save_bridge_settings(
            {
                "garmin_email": "",
                "garmin_password": "",
                "garmin_sync_enabled": "false",
            }
        )
        result = {
            "deleted_sessions": 0,
            "deleted_data": delete_service_data("garmin") if delete_data else {},
        }
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unknown interface",
        )
    return {
        "deleted": True,
        **result,
        "bridge": bridge_status_payload(get_bridge_settings()),
    }


@app.get("/v1/workouts/imports", dependencies=[Depends(require_token)])
def imported_workouts(
    device_id: str = "",
    include_apple_health: bool = False,
    source: str = "",
    limit: int = 500,
    offset: int = 0,
    include_route: bool = True,
    route_max_points: int = 0,
    updated_after: str = "",
    x_healthpit_user: str = Header(default=""),
) -> dict:
    prefix = (
        f"{x_healthpit_user}-{device_id}"
        if device_id
        else f"{x_healthpit_user}-"
    )
    return {
        "workouts": list_unified_workouts(
            limit=max(1, min(limit, 10000)),
            offset=max(0, offset),
            device_prefix=prefix,
            include_route=include_route,
            route_max_points=max(0, min(route_max_points, 2000)) or None,
            source=source or None,
            excluded_source=None if include_apple_health else "apple_health",
            updated_after=updated_after or None,
            include_apple_health=include_apple_health,
        )
    }


@app.get("/v1/workouts/links", dependencies=[Depends(require_token)])
def workout_links() -> dict:
    return {"links": list_workout_link_overrides()}


@app.post("/v1/workouts/links", dependencies=[Depends(require_token)])
def save_workout_link(link: WorkoutLinkOverrideIn) -> dict:
    save_workout_link_override(link.primary, link.linked, link.action)
    return {
        "saved": True,
        "primary": link.primary,
        "linked": link.linked,
        "action": link.action,
    }


@app.delete("/v1/workouts/links", dependencies=[Depends(require_token)])
def delete_workout_link(primary: str, linked: str) -> dict:
    return {"deleted": delete_workout_link_override(primary, linked)}


@app.post("/v1/workouts/imports")
def ingest_imported_workouts(
    batch: ImportedWorkoutBatchIn,
    auth_session: dict | None = Depends(require_workout_upload_token),
    x_healthpit_user: str = Header(default=""),
) -> dict:
    device_id = f"{x_healthpit_user}-{batch.device_id}"
    client_app = normalized_client_app(auth_session or {})
    source_override = "gympit" if client_app == "gympit" else ""
    results: list[dict[str, object]] = []
    for workout in batch.workouts:
        if source_override and workout.source != source_override:
            workout = workout.model_copy(update={"source": source_override})
        results.append(upsert_imported_workout(device_id, workout))
    if source_override == "gympit":
        normalize_gympit_import_sources([device_id])
    publish_imported_workout_metrics(device_id, batch)
    return {
        "accepted": len(batch.workouts),
        "created": sum(1 for item in results if item.get("status") == "created"),
        "updated": sum(1 for item in results if item.get("status") == "updated"),
        "source": source_override or None,
        "workouts": results,
    }


@app.delete("/v1/workouts/imports/{workout_id}")
def remove_imported_workout(
    workout_id: str,
    device_id: str,
    source: str = "",
    auth_session: dict | None = Depends(require_workout_upload_token),
    x_healthpit_user: str = Header(default=""),
) -> dict:
    if normalized_client_app(auth_session or {}) == "gympit":
        source = "gympit"
    effective_device_id = f"{x_healthpit_user}-{device_id}"
    deleted = delete_imported_workout(
        effective_device_id,
        workout_id,
        source or None,
    )
    publish_imported_workout_metrics(
        effective_device_id,
        ImportedWorkoutBatchIn(device_id=device_id, workouts=[]),
    )
    return {"deleted": deleted}


@app.post("/v1/workouts/imports/reconcile")
def reconcile_imported_workouts(
    payload: WorkoutReconcileIn,
    auth_session: dict | None = Depends(require_workout_upload_token),
    x_healthpit_user: str = Header(default=""),
) -> dict:
    source = (
        "gympit"
        if normalized_client_app(auth_session or {}) == "gympit"
        else payload.source
    )
    effective_device_id = f"{x_healthpit_user}-{payload.device_id}"
    deleted = delete_missing_imported_workouts(
        effective_device_id,
        source,
        payload.workout_ids,
    )
    publish_imported_workout_metrics(
        effective_device_id,
        ImportedWorkoutBatchIn(device_id=payload.device_id, workouts=[]),
    )
    return {"deleted": deleted, "kept": len(payload.workout_ids)}


@app.post("/v1/health/batch", dependencies=[Depends(require_token)])
def ingest(batch: HealthBatchIn, x_healthpit_user: str = Header(default="")) -> dict:
    device_id = f"{x_healthpit_user}-{batch.device_id}"
    for item in batch.metrics:
        upsert_metric(device_id, item)
    return {"accepted": len(batch.metrics)}
