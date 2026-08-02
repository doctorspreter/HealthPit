from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.models import ImportedWorkoutIn, WorkoutRoutePointIn
from app.store import (
    get_bridge_settings,
    save_garmin_sync_status,
    upsert_imported_workout,
)


def sync_garmin_workouts() -> dict:
    attempted_at = datetime.now(timezone.utc).isoformat()
    current = get_bridge_settings()
    email = current.get("garmin_email", "").strip()
    password = current.get("garmin_password", "")
    if not email or not password:
        save_garmin_sync_status(attempted_at=attempted_at, error="Garmin Zugangsdaten fehlen.")
        return {"imported_workouts": 0, "error": "Garmin Zugangsdaten fehlen."}

    try:
        from garminconnect import Garmin
    except Exception as error:
        message = f"Garmin Python-Paket fehlt: {error}"
        save_garmin_sync_status(attempted_at=attempted_at, error=message)
        return {"imported_workouts": 0, "error": message}

    try:
        limit = max(1, min(int(current.get("garmin_activity_limit") or "200"), 2000))
    except ValueError:
        limit = 200

    try:
        client = Garmin(email, password)
        client.login()
        activities = client.get_activities(0, limit) or []
        device_id = f"{current['bridge_username']}-garmin"
        imported = 0
        for activity in activities:
            workout = _activity_to_workout(client, activity)
            if not workout:
                continue
            upsert_imported_workout(device_id, workout)
            imported += 1
        save_garmin_sync_status(
            attempted_at=attempted_at,
            success_at=datetime.now(timezone.utc).isoformat(),
            imported_workouts=imported,
        )
        return {"imported_workouts": imported}
    except Exception as error:
        save_garmin_sync_status(attempted_at=attempted_at, error=str(error))
        return {"imported_workouts": 0, "error": str(error)}


def _activity_to_workout(client, activity: dict) -> ImportedWorkoutIn | None:
    activity_id = str(activity.get("activityId") or activity.get("id") or "")
    if not activity_id:
        return None

    start = _parse_dt(activity.get("startTimeGMT") or activity.get("startTimeLocal"))
    if not start:
        return None
    duration = float(activity.get("duration") or activity.get("elapsedDuration") or 0)
    end = start + timedelta(seconds=max(duration, 0))
    sport = _activity_type(activity)
    detail = _activity_detail(client, activity_id)

    return ImportedWorkoutIn(
        id=f"garmin-{activity_id}",
        source="garmin",
        sport=sport,
        title=activity.get("activityName") or sport,
        start=start,
        end=end,
        distance_km=_meters_to_km(activity.get("distance")),
        energy_kcal=_number(activity.get("calories")),
        average_heart_rate=_number(activity.get("averageHR") or activity.get("avgHR")),
        max_heart_rate=_number(activity.get("maxHR")),
        notes="Garmin Connect",
        route=_route_points(detail),
    )


def _activity_detail(client, activity_id: str) -> dict:
    for name in ("get_activity_details", "get_activity_detail"):
        method = getattr(client, name, None)
        if not method:
            continue
        try:
            value = method(activity_id)
            if isinstance(value, dict):
                return value
        except Exception:
            return {}
    return {}


def _route_points(detail: dict) -> list[WorkoutRoutePointIn]:
    rows = detail.get("activityDetailMetrics") or detail.get("activityDetailMetricsDTOs") or []
    out: list[WorkoutRoutePointIn] = []
    for row in rows:
        lat = row.get("directLatitude") or row.get("latitude")
        lon = row.get("directLongitude") or row.get("longitude")
        if lat is None or lon is None:
            continue
        timestamp = _parse_dt(row.get("startTimeGMT") or row.get("clockDuration") or row.get("timestamp"))
        out.append(
            WorkoutRoutePointIn(
                latitude=float(lat),
                longitude=float(lon),
                elevation=_number(row.get("elevation")),
                timestamp=timestamp,
                heart_rate=_number(row.get("heartRate") or row.get("hr")),
            )
        )
    return out


def _activity_type(activity: dict) -> str:
    value = activity.get("activityType") or {}
    if isinstance(value, dict):
        return value.get("typeKey") or value.get("typeName") or "Garmin"
    return str(value or "Garmin")


def _parse_dt(value) -> datetime | None:
    if not value or isinstance(value, (int, float)):
        return None
    try:
        text = str(value).replace("Z", "+00:00")
        parsed = datetime.fromisoformat(text)
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _number(value) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _meters_to_km(value) -> float | None:
    number = _number(value)
    return None if number is None else number / 1000
