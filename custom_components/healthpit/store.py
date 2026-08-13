"""Persistent storage, kept separate per Home Assistant user.

Several people can have the app on their phone and push into the same Home
Assistant. Each of them owns their own long-lived access token, so the token
decides which bucket a push lands in — the client never gets to say who it is.
"""

from __future__ import annotations

import logging
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import (
    MAX_METRICS_PER_USER,
    MAX_WORKOUTS_PER_USER,
    SAVE_DELAY_SECONDS,
    STORAGE_KEY,
    STORAGE_VERSION,
)
from .metrics import transfer_summary, upgrade_storage
from .workout_merge import unify_workouts

_LOGGER = logging.getLogger(__name__)


async def _async_migrate(
    old_major_version: int, old_minor_version: int, old_data: dict[str, Any]
) -> dict[str, Any]:
    """Carry stored values over to the metric-id model.

    Nothing is deleted and no key changes: the old sensor id stays the storage
    key, so Home Assistant keeps the entity and its recorded history. The
    canonical id is added next to it.
    """
    if old_major_version >= 2:
        return old_data
    summary = transfer_summary(old_data)
    migrated = upgrade_storage(old_data)
    _LOGGER.info(
        "HealthPit storage upgraded to the metric registry: "
        "%s values (%s without a known metric id), %s workouts",
        summary["metrics"],
        summary["unresolved"],
        summary["workouts"],
    )
    return migrated


def _empty_user(name: str) -> dict[str, Any]:
    return {"name": name, "metrics": {}, "workouts": {}, "links": []}


class HealthPitStore:
    """Holds what every user pushed, and survives restarts."""

    def __init__(self, hass: HomeAssistant) -> None:
        self._hass = hass
        self._store: Store[dict[str, Any]] = Store(
            hass,
            STORAGE_VERSION,
            STORAGE_KEY,
            private=True,
            migrate_func=_async_migrate,
        )
        self._users: dict[str, dict[str, Any]] = {}

    async def async_load(self) -> None:
        """Read the previous contents, tolerating anything unexpected in it."""
        data = await self._store.async_load() or {}
        raw_users = data.get("users")
        self._users = {}
        if isinstance(raw_users, dict):
            for user_id, bucket in raw_users.items():
                if not isinstance(bucket, dict):
                    continue
                self._users[str(user_id)] = {
                    "name": str(bucket.get("name") or ""),
                    "metrics": _dicts(bucket.get("metrics")),
                    "workouts": _dicts(bucket.get("workouts")),
                    "links": _links(bucket.get("links")),
                }
        # A store written by an older version, or restored from a backup, can
        # still arrive without the new fields. Filling them in on load costs
        # nothing and keeps every reader on one shape.
        self._users = upgrade_storage({"users": self._users})["users"]
        _LOGGER.debug(
            "Loaded %s users: %s",
            len(self._users),
            {key: len(value["workouts"]) for key, value in self._users.items()},
        )

    def _schedule_save(self) -> None:
        self._store.async_delay_save(self._as_dict, SAVE_DELAY_SECONDS)

    async def async_save_now(self) -> None:
        """Flush immediately, used when the entry unloads."""
        await self._store.async_save(self._as_dict())

    def _as_dict(self) -> dict[str, Any]:
        return {"users": self._users}

    async def async_remove(self) -> None:
        await self._store.async_remove()

    # ------------------------------------------------------------------
    # Users
    # ------------------------------------------------------------------

    def user_ids(self) -> list[str]:
        return sorted(self._users, key=lambda key: self._users[key].get("name") or key)

    def user_name(self, user_id: str) -> str:
        bucket = self._users.get(user_id) or {}
        return str(bucket.get("name") or "") or user_id

    def has_user(self, user_id: str) -> bool:
        return user_id in self._users

    def forget_user(self, user_id: str) -> bool:
        """Drop everything one user pushed."""
        if self._users.pop(user_id, None) is None:
            return False
        self._schedule_save()
        return True

    def _bucket(self, user_id: str, name: str) -> dict[str, Any]:
        bucket = self._users.get(user_id)
        if bucket is None:
            bucket = _empty_user(name)
            self._users[user_id] = bucket
        elif name and bucket.get("name") != name:
            # The user renamed themselves in Home Assistant; follow along so the
            # device keeps showing the current name.
            bucket["name"] = name
        return bucket

    # ------------------------------------------------------------------
    # Metrics
    # ------------------------------------------------------------------

    def upsert_metrics(
        self,
        user_id: str,
        user_name: str,
        device_id: str,
        metrics: list[dict[str, Any]],
    ) -> int:
        """Store the latest value per metric and return how many were accepted."""
        bucket = self._bucket(user_id, user_name)
        for metric in metrics:
            # Key unchanged on purpose: it decides the entity id.
            key = f"{device_id}|{metric['category']}|{metric['metric_id']}"
            bucket["metrics"][key] = {**metric, "device_id": device_id}
        _trim(bucket["metrics"], MAX_METRICS_PER_USER, key="measured_at")
        self._schedule_save()
        return len(metrics)

    def latest_metrics(self, user_id: str) -> list[dict[str, Any]]:
        bucket = self._users.get(user_id) or {}
        return list((bucket.get("metrics") or {}).values())

    # ------------------------------------------------------------------
    # Workouts
    # ------------------------------------------------------------------

    def upsert_workouts(
        self,
        user_id: str,
        user_name: str,
        device_id: str,
        workouts: list[dict[str, Any]],
    ) -> dict[str, int]:
        """Store workouts, replacing near-identical re-uploads of the same session."""
        bucket = self._bucket(user_id, user_name)
        stored = bucket["workouts"]
        created = 0
        updated = 0
        now = dt_util.utcnow().isoformat()
        for workout in workouts:
            key = f"{device_id}|{workout['workout_id']}"
            if key in stored:
                updated += 1
            else:
                created += 1
            # An app that regenerates workout IDs would otherwise leave a copy
            # behind on every sync. Apple Health IDs are stable, so only the
            # other sources need this.
            if workout["source"] != "apple_health":
                for stale in _same_session_keys(stored, device_id, workout, key):
                    stored.pop(stale, None)
            stored[key] = {**workout, "updated_at": now}
        _trim(stored, MAX_WORKOUTS_PER_USER, key="start_time")
        self._schedule_save()
        return {"created": created, "updated": updated}

    def delete_workout(
        self,
        user_id: str,
        device_id: str,
        workout_id: str,
        source: str | None = None,
    ) -> bool:
        bucket = self._users.get(user_id)
        if bucket is None:
            return False
        key = f"{device_id}|{workout_id}"
        stored = bucket["workouts"].get(key)
        if stored is None:
            return False
        if source and stored.get("source") != source:
            return False
        bucket["workouts"].pop(key, None)
        self._schedule_save()
        return True

    def reconcile(
        self,
        user_id: str,
        device_id: str,
        source: str,
        workout_ids: list[str],
    ) -> int:
        """Delete workouts of one source that the app no longer knows about."""
        bucket = self._users.get(user_id)
        if bucket is None:
            return 0
        keep = set(workout_ids)
        stale = [
            key
            for key, stored in bucket["workouts"].items()
            if key.startswith(f"{device_id}|")
            and stored.get("source") == source
            and str(stored.get("workout_id")) not in keep
        ]
        for key in stale:
            bucket["workouts"].pop(key, None)
        if stale:
            self._schedule_save()
        return len(stale)

    def unified_workouts(
        self,
        user_id: str,
        *,
        source: str | None = None,
        device_id: str | None = None,
        include_apple_health: bool = True,
    ) -> list[dict[str, Any]]:
        """Return merged workouts for one user, one entry per session.

        The filters matter for the app's download step: it asks per source and
        excludes Apple Health, because those workouts already live on the phone.
        Ignoring the filters would hand it every workout four times over.
        """
        bucket = self._users.get(user_id)
        if bucket is None:
            return []

        workouts = list(bucket["workouts"].values())
        if source:
            workouts = [item for item in workouts if item.get("source") == source]
        elif not include_apple_health:
            workouts = [
                item for item in workouts if item.get("source") != "apple_health"
            ]
        if device_id:
            workouts = [
                item for item in workouts if str(item.get("device_id")) == device_id
            ]
        return unify_workouts(workouts, bucket["links"])

    def workout(self, user_id: str, workout_id: str) -> dict[str, Any] | None:
        """Find one merged workout by the ID the entities show."""
        if not workout_id:
            return None
        return next(
            (
                item
                for item in self.unified_workouts(user_id)
                if str(item.get("workout_id")) == workout_id
            ),
            None,
        )

    # ------------------------------------------------------------------
    # Manual links between workouts
    # ------------------------------------------------------------------

    def links(self, user_id: str) -> list[dict[str, str]]:
        """Every decision this user made about proposed duplicates."""
        bucket = self._users.get(user_id)
        return list(bucket["links"]) if bucket else []

    def save_link(self, user_id: str, primary: str, linked: str, action: str) -> None:
        bucket = self._bucket(user_id, "")
        bucket["links"] = [
            row
            for row in bucket["links"]
            if {row["primary"], row["linked"]} != {primary, linked}
        ]
        bucket["links"].append({"primary": primary, "linked": linked, "action": action})
        self._schedule_save()

    def delete_link(self, user_id: str, primary: str, linked: str) -> bool:
        bucket = self._users.get(user_id)
        if bucket is None:
            return False
        before = len(bucket["links"])
        bucket["links"] = [
            row
            for row in bucket["links"]
            if {row["primary"], row["linked"]} != {primary, linked}
        ]
        if len(bucket["links"]) == before:
            return False
        self._schedule_save()
        return True

    # ------------------------------------------------------------------

    def summary(self, user_id: str) -> dict[str, Any]:
        """A small status payload the app can show after connecting."""
        bucket = self._users.get(user_id) or _empty_user("")
        sources: dict[str, int] = {}
        for workout in bucket["workouts"].values():
            source = str(workout.get("source") or "unknown")
            sources[source] = sources.get(source, 0) + 1
        devices = sorted(
            {str(item.get("device_id") or "") for item in bucket["metrics"].values()}
            | {key.split("|", 1)[0] for key in bucket["workouts"]}
        )
        return {
            "metric_count": len(bucket["metrics"]),
            "workout_count": len(bucket["workouts"]),
            "workouts_by_source": sources,
            "devices": [device for device in devices if device],
            "links": len(bucket["links"]),
        }


def _same_session_keys(
    stored: dict[str, dict[str, Any]],
    device_id: str,
    workout: dict[str, Any],
    own_key: str,
) -> list[str]:
    """Find stored workouts that are the same session under a different ID."""
    start = _seconds(workout.get("start_time"))
    duration = float(workout.get("duration_seconds") or 0)
    sport = str(workout.get("sport") or "").strip().lower()
    title = str(workout.get("title") or "").strip().lower()
    out: list[str] = []
    for key, item in stored.items():
        if key == own_key or not key.startswith(f"{device_id}|"):
            continue
        if item.get("source") != workout["source"]:
            continue
        if str(item.get("sport") or "").strip().lower() != sport:
            continue
        if str(item.get("title") or "").strip().lower() != title:
            continue
        item_start = _seconds(item.get("start_time"))
        if start is None or item_start is None:
            continue
        if abs(item_start - start) > 120:
            continue
        if abs(float(item.get("duration_seconds") or 0) - duration) > 300:
            continue
        out.append(key)
    return out


def _trim(items: dict[str, dict[str, Any]], limit: int, *, key: str) -> None:
    """Drop the oldest entries once the store grows past the limit."""
    if len(items) <= limit:
        return
    ordered = sorted(items.items(), key=lambda pair: str(pair[1].get(key) or ""))
    for stale_key, _ in ordered[: len(items) - limit]:
        items.pop(stale_key, None)
    _LOGGER.warning("Healthpit store exceeded %s entries; dropped the oldest", limit)


def _dicts(value: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(value, dict):
        return {}
    return {str(key): item for key, item in value.items() if isinstance(item, dict)}


def _links(value: Any) -> list[dict[str, str]]:
    if not isinstance(value, list):
        return []
    return [
        {
            "primary": str(row.get("primary") or ""),
            "linked": str(row.get("linked") or ""),
            "action": str(row.get("action") or "merge"),
        }
        for row in value
        if isinstance(row, dict) and row.get("primary") and row.get("linked")
    ]


def _seconds(value: Any) -> float | None:
    parsed = dt_util.parse_datetime(str(value)) if value else None
    return parsed.timestamp() if parsed else None
