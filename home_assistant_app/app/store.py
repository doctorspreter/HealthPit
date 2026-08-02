from __future__ import annotations

import json
import hashlib
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from app.config import settings
from app.models import HealthMetricIn, ImportedWorkoutIn, normalize_workout_source


def migrate_legacy_database_path() -> None:
    current_path = Path(settings.database_path)
    legacy_paths = [
        current_path.with_name("healt" + "pit_bridge.sqlite3"),
        current_path.with_name("health" + "_bridge.sqlite3"),
    ]
    for legacy_path in legacy_paths:
        if not current_path.exists() and legacy_path.exists():
            current_path.parent.mkdir(parents=True, exist_ok=True)
            legacy_path.rename(current_path)
            break


def connect() -> sqlite3.Connection:
    migrate_legacy_database_path()
    Path(settings.database_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(settings.database_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 5000")
    return conn


def _ensure_columns(conn: sqlite3.Connection, table: str, columns: dict[str, str]) -> None:
    existing = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    for name, definition in columns.items():
        if name not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")


def init_db() -> None:
    with connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS bridge_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS hevy_workouts (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT,
                updated_at TEXT,
                created_at TEXT,
                imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS hevy_exercise_sets (
                workout_id TEXT NOT NULL,
                exercise_index INTEGER NOT NULL,
                set_index INTEGER NOT NULL,
                exercise_template_id TEXT,
                exercise_title TEXT NOT NULL,
                set_type TEXT,
                weight_kg REAL,
                reps REAL,
                distance_meters REAL,
                duration_seconds REAL,
                rpe REAL,
                workout_start_time TEXT NOT NULL,
                workout_title TEXT NOT NULL,
                PRIMARY KEY (workout_id, exercise_index, set_index)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS latest_metrics (
                device_id TEXT NOT NULL,
                metric_id TEXT NOT NULL,
                category TEXT NOT NULL,
                title TEXT NOT NULL,
                value REAL NOT NULL,
                unit TEXT NOT NULL,
                measured_at TEXT NOT NULL,
                aggregation TEXT NOT NULL,
                icon TEXT,
                device_class TEXT,
                state_class TEXT,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (device_id, metric_id)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS imported_workouts (
                device_id TEXT NOT NULL,
                workout_id TEXT NOT NULL,
                source TEXT NOT NULL,
                sport TEXT NOT NULL,
                title TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                duration_seconds REAL NOT NULL,
                distance_km REAL,
                energy_kcal REAL,
                average_heart_rate REAL,
                max_heart_rate REAL,
                notes TEXT NOT NULL,
                weather_json TEXT,
                injury_json TEXT,
                route_json TEXT NOT NULL,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (device_id, workout_id)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS imported_workout_exercises (
                device_id TEXT NOT NULL,
                workout_id TEXT NOT NULL,
                exercise_id TEXT NOT NULL,
                exercise_index INTEGER NOT NULL,
                catalog_id TEXT,
                name TEXT NOT NULL,
                category TEXT,
                start_time TEXT,
                end_time TEXT,
                duration_seconds REAL,
                notes TEXT NOT NULL,
                device_settings_json TEXT NOT NULL DEFAULT '{}',
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (device_id, workout_id, exercise_id)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS imported_workout_sets (
                device_id TEXT NOT NULL,
                workout_id TEXT NOT NULL,
                exercise_id TEXT NOT NULL,
                set_id TEXT NOT NULL,
                set_index INTEGER NOT NULL,
                set_type TEXT NOT NULL,
                reps REAL,
                weight_kg REAL,
                rpe REAL,
                volume_kg REAL,
                is_personal_record INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (device_id, workout_id, exercise_id, set_id)
            )
            """
        )
        _ensure_columns(conn, "imported_workout_exercises", {
            "start_time": "TEXT",
            "end_time": "TEXT",
            "duration_seconds": "REAL",
        })
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS workout_link_overrides (
                primary_key TEXT NOT NULL,
                linked_key TEXT NOT NULL,
                action TEXT NOT NULL CHECK(action IN ('merge', 'separate')),
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (primary_key, linked_key)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS app_sessions (
                session_id TEXT PRIMARY KEY,
                token_hash TEXT NOT NULL UNIQUE,
                username TEXT NOT NULL,
                device_name TEXT NOT NULL,
                scope TEXT NOT NULL DEFAULT 'workout_import',
                client_app TEXT NOT NULL DEFAULT '',
                node_role TEXT NOT NULL DEFAULT 'slave' CHECK(node_role IN ('master', 'slave')),
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                expires_at TEXT NOT NULL,
                last_used_at TEXT,
                revoked_at TEXT
            )
            """
        )
        _ensure_column(conn, "imported_workouts", "weather_json", "TEXT")
        _ensure_column(conn, "imported_workouts", "injury_json", "TEXT")
        _ensure_column(conn, "imported_workouts", "route_points", "INTEGER NOT NULL DEFAULT 0")
        _ensure_column(conn, "app_sessions", "scope", "TEXT NOT NULL DEFAULT 'workout_import'")
        _ensure_column(conn, "app_sessions", "client_app", "TEXT NOT NULL DEFAULT ''")
        _ensure_column(conn, "app_sessions", "node_role", "TEXT NOT NULL DEFAULT 'slave'")
        conn.execute(
            """
            UPDATE app_sessions
            SET node_role = 'slave'
            WHERE node_role IS NULL OR node_role NOT IN ('master', 'slave')
            """
        )
        conn.execute(
            """
            UPDATE app_sessions
            SET revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP)
            WHERE node_role = 'master'
            """
        )
        conn.execute(
            """
            UPDATE imported_workouts
            SET route_points = json_array_length(route_json)
            WHERE route_points = 0
              AND route_json != '[]'
              AND json_valid(route_json)
            """
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_imported_workouts_start ON imported_workouts(start_time DESC)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_imported_workouts_source_start ON imported_workouts(source, start_time DESC)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_imported_workouts_device_source_start ON imported_workouts(device_id, source, start_time DESC)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_imported_workouts_updated ON imported_workouts(updated_at)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_hevy_workouts_start ON hevy_workouts(start_time DESC)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_app_sessions_username_role ON app_sessions(username, node_role)")
        _delete_exact_duplicate_imported_workouts(conn)
        _delete_orphan_import_details(conn)


def _ensure_column(conn: sqlite3.Connection, table: str, column: str, definition: str) -> None:
    columns = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})")}
    if column not in columns:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def default_bridge_settings() -> dict[str, str]:
    return {
        "bridge_username": settings.bridge_username,
        "bridge_api_token": settings.bridge_api_token,
        "bridge_otp_shared_secret": settings.bridge_otp_shared_secret,
        "app_session_expires_days": "1825",
        "hevy_api_key": settings.hevy_api_key,
        "hevy_sync_enabled": "true" if settings.hevy_sync_enabled else "false",
        "hevy_max_pages": str(settings.hevy_max_pages),
        "hevy_sync_interval_minutes": str(settings.hevy_sync_interval_minutes),
        "hevy_last_attempt_at": "",
        "hevy_last_success_at": "",
        "hevy_last_error": "",
        "hevy_last_imported_workouts": "0",
        "garmin_email": settings.garmin_email,
        "garmin_password": settings.garmin_password,
        "garmin_sync_enabled": "true" if settings.garmin_sync_enabled else "false",
        "garmin_activity_limit": str(settings.garmin_activity_limit),
        "garmin_last_attempt_at": "",
        "garmin_last_success_at": "",
        "garmin_last_error": "",
        "garmin_last_imported_workouts": "0",
    }


def get_bridge_settings() -> dict[str, str]:
    values = default_bridge_settings()
    with connect() as conn:
        rows = conn.execute("SELECT key, value FROM bridge_settings").fetchall()
    values.update({row["key"]: row["value"] for row in rows})
    return values


def save_bridge_settings(values: dict[str, str]) -> None:
    allowed = set(default_bridge_settings())
    with connect() as conn:
        for key, value in values.items():
            if key not in allowed:
                continue
            conn.execute(
                """
                INSERT INTO bridge_settings (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (key, value),
            )


def bridge_setting_exists(key: str) -> bool:
    with connect() as conn:
        row = conn.execute("SELECT 1 FROM bridge_settings WHERE key = ?", (key,)).fetchone()
    return row is not None


def save_hevy_sync_status(
    *,
    attempted_at: str,
    success_at: str = "",
    error: str = "",
    imported_workouts: int = 0,
) -> None:
    values = {
        "hevy_last_attempt_at": attempted_at,
        "hevy_last_error": error[:500],
        "hevy_last_imported_workouts": str(imported_workouts),
    }
    if success_at:
        values["hevy_last_success_at"] = success_at
    save_bridge_settings(values)


def save_garmin_sync_status(
    *,
    attempted_at: str,
    success_at: str = "",
    error: str = "",
    imported_workouts: int = 0,
) -> None:
    values = {
        "garmin_last_attempt_at": attempted_at,
        "garmin_last_error": error[:500],
        "garmin_last_imported_workouts": str(imported_workouts),
    }
    if success_at:
        values["garmin_last_success_at"] = success_at
    save_bridge_settings(values)


def save_workout_link_override(primary: str, linked: str, action: str) -> None:
    first, second = sorted((primary, linked))
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO workout_link_overrides (primary_key, linked_key, action, updated_at)
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(primary_key, linked_key) DO UPDATE SET
                action = excluded.action,
                updated_at = CURRENT_TIMESTAMP
            """,
            (first, second, action),
        )


def delete_workout_link_override(primary: str, linked: str) -> bool:
    first, second = sorted((primary, linked))
    with connect() as conn:
        cursor = conn.execute(
            "DELETE FROM workout_link_overrides WHERE primary_key = ? AND linked_key = ?",
            (first, second),
        )
        return cursor.rowcount > 0


def list_workout_link_overrides() -> list[dict]:
    with connect() as conn:
        rows = conn.execute(
            "SELECT primary_key, linked_key, action, updated_at FROM workout_link_overrides"
        ).fetchall()
    return [dict(row) for row in rows]


def utc_now_text() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def create_app_session(
    *,
    session_id: str,
    token_hash: str,
    username: str,
    device_name: str,
    scope: str,
    client_app: str,
    node_role: str,
    expires_at: str,
) -> None:
    if node_role != "slave":
        raise ValueError("Only client sessions can connect to the Healthpit master")
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO app_sessions (
                session_id, token_hash, username, device_name, scope, client_app,
                node_role, expires_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                session_id,
                token_hash,
                username,
                device_name,
                scope,
                client_app,
                node_role,
                expires_at,
            ),
        )


def valid_app_session(
    token_hash: str,
    username: str,
    allowed_scopes: set[str] | None = None,
) -> dict | None:
    now = utc_now_text()
    with connect() as conn:
        row = conn.execute(
            """
            SELECT session_id, token_hash, username, device_name, scope, client_app,
                   node_role, created_at, expires_at, last_used_at, revoked_at
            FROM app_sessions
            WHERE token_hash = ? AND username = ? AND revoked_at IS NULL
            """,
            (token_hash, username),
        ).fetchone()
        if not row or str(row["expires_at"]) <= now:
            return None
        if str(row["node_role"]) != "slave":
            return None
        if allowed_scopes is not None and str(row["scope"]) not in allowed_scopes:
            return None
        conn.execute(
            "UPDATE app_sessions SET last_used_at = CURRENT_TIMESTAMP WHERE session_id = ?",
            (row["session_id"],),
        )
    return dict(row)


def list_app_sessions() -> list[dict]:
    now = utc_now_text()
    with connect() as conn:
        rows = conn.execute(
            """
            SELECT session_id, username, device_name, scope, client_app, node_role,
                   created_at, expires_at, last_used_at, revoked_at,
                   CASE
                     WHEN node_role = 'slave'
                      AND revoked_at IS NULL
                      AND expires_at > ? THEN 1
                     ELSE 0
                   END AS active
            FROM app_sessions
            ORDER BY active DESC, COALESCE(last_used_at, created_at) DESC
            """,
            (now,),
        ).fetchall()
    return [dict(row) for row in rows]


def normalized_client_app(session: dict) -> str:
    client_app = str(session.get("client_app") or "").strip().lower()
    scope = str(session.get("scope") or "").strip().lower()
    if client_app:
        return client_app
    if scope == "workout_import":
        return "gympit"
    if scope == "home_assistant":
        return "home_assistant"
    return ""


def revoke_app_session(session_id: str) -> bool:
    with connect() as conn:
        cursor = conn.execute(
            """
            UPDATE app_sessions
            SET revoked_at = CURRENT_TIMESTAMP
            WHERE session_id = ? AND revoked_at IS NULL
            """,
            (session_id,),
        )
        return cursor.rowcount > 0


def app_session_data_summary(session: dict) -> dict[str, float | int | str]:
    username = str(session.get("username") or "").strip()
    client_app = normalized_client_app(session)
    device_ids = _session_device_ids(session)
    summary: dict[str, float | int | str] = {
        "metrics": 0,
        "workouts": 0,
        "sets": 0,
        "volume_kg": 0,
        "duration_seconds": 0,
        "distance_km": 0,
        "latest_at": "",
    }
    if not username or not client_app:
        return summary

    with connect() as conn:
        if device_ids:
            metric_row = conn.execute(
                f"""
                SELECT COUNT(*) AS count, MAX(measured_at) AS latest_at
                FROM latest_metrics
                WHERE device_id IN ({','.join('?' for _ in device_ids)})
                """,
                tuple(device_ids),
            ).fetchone()
            summary["metrics"] = int(metric_row["count"] or 0)
            summary["latest_at"] = str(metric_row["latest_at"] or "")

        workout_where = ""
        params: tuple[object, ...] = ()
        if client_app == "healthpit" and device_ids:
            workout_where = (
                f"source IN ('apple_health', 'healthpit') "
                f"AND device_id IN ({','.join('?' for _ in device_ids)})"
            )
            params = tuple(device_ids)
        elif client_app == "gympit":
            if device_ids:
                workout_where = (
                    f"((source = 'gympit' AND device_id LIKE ?) "
                    f"OR device_id IN ({','.join('?' for _ in device_ids)}))"
                )
                params = (f"{username}-%", *device_ids)
            else:
                workout_where = "source = 'gympit' AND device_id LIKE ?"
                params = (f"{username}-%",)

        if workout_where:
            workout_row = conn.execute(
                f"""
                SELECT COUNT(*) AS count,
                       COALESCE(SUM(duration_seconds), 0) AS duration_seconds,
                       COALESCE(SUM(distance_km), 0) AS distance_km,
                       MAX(start_time) AS latest_at
                FROM imported_workouts
                WHERE {workout_where}
                """,
                params,
            ).fetchone()
            summary["workouts"] = int(workout_row["count"] or 0)
            summary["duration_seconds"] = float(workout_row["duration_seconds"] or 0)
            summary["distance_km"] = float(workout_row["distance_km"] or 0)
            summary["latest_at"] = max(str(summary["latest_at"] or ""), str(workout_row["latest_at"] or ""))
            if client_app == "gympit":
                if device_ids:
                    set_where = (
                        f"((w.source = 'gympit' AND w.device_id LIKE ?) "
                        f"OR w.device_id IN ({','.join('?' for _ in device_ids)}))"
                    )
                    set_params = (f"{username}-%", *device_ids)
                else:
                    set_where = "w.source = 'gympit' AND w.device_id LIKE ?"
                    set_params = (f"{username}-%",)
                set_row = conn.execute(
                    f"""
                    SELECT COUNT(s.set_id) AS sets,
                           COALESCE(SUM(s.volume_kg), 0) AS volume_kg
                    FROM imported_workout_sets s
                    JOIN imported_workouts w
                      ON w.device_id = s.device_id
                     AND w.workout_id = s.workout_id
                    WHERE {set_where}
                    """,
                    set_params,
                ).fetchone()
                summary["sets"] = int(set_row["sets"] or 0)
                summary["volume_kg"] = float(set_row["volume_kg"] or 0)

    return summary


def app_interface_data_summary(client_app: str) -> dict[str, float | int | str]:
    key = str(client_app or "").strip().lower()
    sessions = [row for row in list_app_sessions() if normalized_client_app(row) == key]
    active_sessions = [row for row in sessions if row.get("active")]
    data = interface_stored_data_summary(key)
    return {
        "sessions": len(sessions),
        "active_sessions": len(active_sessions),
        **data,
    }


def interface_stored_data_summary(client_app: str) -> dict[str, float | int | str]:
    key = str(client_app or "").strip().lower()
    username = get_bridge_settings()["bridge_username"]
    summary: dict[str, float | int | str] = {
        "metrics": 0,
        "workouts": 0,
        "sets": 0,
        "volume_kg": 0,
        "duration_seconds": 0,
        "distance_km": 0,
        "latest_at": "",
    }
    with connect() as conn:
        if key == "healthpit":
            metric_row = conn.execute(
                """
                SELECT COUNT(*) AS count, MAX(measured_at) AS latest_at
                FROM latest_metrics
                WHERE device_id LIKE ?
                  AND lower(device_id) NOT LIKE '%gympit%'
                  AND lower(device_id) NOT LIKE '%garmin%'
                """,
                (f"{username}-%",),
            ).fetchone()
            workout_row = conn.execute(
                """
                SELECT COUNT(*) AS count,
                       COALESCE(SUM(duration_seconds), 0) AS duration_seconds,
                       COALESCE(SUM(distance_km), 0) AS distance_km,
                       MAX(start_time) AS latest_at
                FROM imported_workouts
                WHERE source IN ('apple_health', 'healthpit')
                  AND device_id LIKE ?
                """,
                (f"{username}-%",),
            ).fetchone()
        elif key == "gympit":
            metric_row = conn.execute(
                """
                SELECT COUNT(*) AS count, MAX(measured_at) AS latest_at
                FROM latest_metrics
                WHERE lower(device_id) LIKE '%gympit%'
                """,
            ).fetchone()
            workout_row = conn.execute(
                """
                SELECT COUNT(*) AS count,
                       COALESCE(SUM(duration_seconds), 0) AS duration_seconds,
                       COALESCE(SUM(distance_km), 0) AS distance_km,
                       MAX(start_time) AS latest_at
                FROM imported_workouts
                WHERE source = 'gympit'
                   OR lower(device_id) LIKE '%gympit%'
                """,
            ).fetchone()
        else:
            return summary

        summary["metrics"] = int(metric_row["count"] or 0)
        summary["workouts"] = int(workout_row["count"] or 0)
        summary["duration_seconds"] = float(workout_row["duration_seconds"] or 0)
        summary["distance_km"] = float(workout_row["distance_km"] or 0)
        summary["latest_at"] = max(str(metric_row["latest_at"] or ""), str(workout_row["latest_at"] or ""))
        if key == "gympit":
            set_row = conn.execute(
                """
                SELECT COUNT(s.set_id) AS sets,
                       COALESCE(SUM(s.volume_kg), 0) AS volume_kg
                FROM imported_workout_sets s
                JOIN imported_workouts w
                  ON w.device_id = s.device_id
                 AND w.workout_id = s.workout_id
                WHERE w.source = 'gympit'
                   OR lower(w.device_id) LIKE '%gympit%'
                """
            ).fetchone()
            summary["sets"] = int(set_row["sets"] or 0)
            summary["volume_kg"] = float(set_row["volume_kg"] or 0)
    return summary


def service_data_summary(service: str) -> dict[str, float | int | str]:
    key = str(service or "").strip().lower()
    with connect() as conn:
        if key == "hevy":
            row = conn.execute(
                """
                SELECT COUNT(DISTINCT h.id) AS workouts,
                       COUNT(s.workout_id) AS sets,
                       MAX(h.start_time) AS latest_at
                FROM hevy_workouts h
                LEFT JOIN hevy_exercise_sets s ON s.workout_id = h.id
                """
            ).fetchone()
            return {
                "workouts": int(row["workouts"] or 0),
                "sets": int(row["sets"] or 0),
                "metrics": 0,
                "duration_seconds": 0,
                "distance_km": 0,
                "latest_at": str(row["latest_at"] or ""),
            }
        if key == "garmin":
            row = conn.execute(
                """
                SELECT COUNT(*) AS workouts,
                       COALESCE(SUM(duration_seconds), 0) AS duration_seconds,
                       COALESCE(SUM(distance_km), 0) AS distance_km,
                       MAX(start_time) AS latest_at
                FROM imported_workouts
                WHERE source = 'garmin'
                """
            ).fetchone()
            return {
                "workouts": int(row["workouts"] or 0),
                "sets": 0,
                "metrics": 0,
                "duration_seconds": float(row["duration_seconds"] or 0),
                "distance_km": float(row["distance_km"] or 0),
                "latest_at": str(row["latest_at"] or ""),
            }
    return {"workouts": 0, "sets": 0, "metrics": 0, "duration_seconds": 0, "distance_km": 0, "latest_at": ""}


def delete_app_interface(client_app: str, delete_data: bool = False) -> dict[str, object]:
    key = str(client_app or "").strip().lower()
    sessions = [row for row in list_app_sessions() if normalized_client_app(row) == key]
    deleted_data = {"metrics": 0, "workouts": 0}
    if delete_data:
        deleted_data = delete_interface_stored_data(key)
    deleted_sessions = 0
    with connect() as conn:
        for session in sessions:
            cursor = conn.execute("DELETE FROM app_sessions WHERE session_id = ?", (session["session_id"],))
            deleted_sessions += cursor.rowcount
    return {
        "deleted_sessions": deleted_sessions,
        "deleted_data": deleted_data,
    }


def delete_interface_stored_data(client_app: str) -> dict[str, int]:
    key = str(client_app or "").strip().lower()
    username = get_bridge_settings()["bridge_username"]
    deleted = {"metrics": 0, "workouts": 0}
    with connect() as conn:
        if key == "healthpit":
            metrics = conn.execute(
                """
                DELETE FROM latest_metrics
                WHERE device_id LIKE ?
                  AND lower(device_id) NOT LIKE '%gympit%'
                  AND lower(device_id) NOT LIKE '%garmin%'
                """,
                (f"{username}-%",),
            )
            workouts = conn.execute(
                """
                DELETE FROM imported_workouts
                WHERE source IN ('apple_health', 'healthpit')
                  AND device_id LIKE ?
                """,
                (f"{username}-%",),
            )
        elif key == "gympit":
            metrics = conn.execute(
                """
                DELETE FROM latest_metrics
                WHERE lower(device_id) LIKE '%gympit%'
                """,
            )
            workouts = conn.execute(
                """
                DELETE FROM imported_workouts
                WHERE source = 'gympit'
                   OR lower(device_id) LIKE '%gympit%'
                """,
            )
        else:
            return deleted
        deleted["metrics"] = metrics.rowcount
        deleted["workouts"] = workouts.rowcount
        if deleted["workouts"]:
            _delete_orphan_import_details(conn)
    return deleted


def delete_service_data(service: str) -> dict[str, int]:
    key = str(service or "").strip().lower()
    deleted = {"workouts": 0, "sets": 0}
    with connect() as conn:
        if key == "hevy":
            sets = conn.execute("DELETE FROM hevy_exercise_sets")
            workouts = conn.execute("DELETE FROM hevy_workouts")
            deleted["sets"] = sets.rowcount
            deleted["workouts"] = workouts.rowcount
        elif key == "garmin":
            workouts = conn.execute("DELETE FROM imported_workouts WHERE source = 'garmin'")
            deleted["workouts"] = workouts.rowcount
            if deleted["workouts"]:
                _delete_orphan_import_details(conn)
    return deleted


def _session_device_ids(session: dict) -> list[str]:
    username = str(session.get("username") or "").strip()
    if not username:
        return []
    names = {str(session.get("device_name") or "").strip()}
    client_app = normalized_client_app(session)
    if client_app == "healthpit":
        names.update({"iPhone", "Healthpit", "Healthpit (iPhone)"})
    elif client_app == "gympit":
        names.update({"Gympit", "Gympit (iPhone)", "Fitness", "FitnessApp"})
    clean = {name for name in names if name}
    return sorted({f"{username}-{name}" for name in clean})


def revoke_all_app_sessions() -> int:
    with connect() as conn:
        cursor = conn.execute(
            """
            UPDATE app_sessions
            SET revoked_at = CURRENT_TIMESTAMP
            WHERE revoked_at IS NULL
            """
        )
        return cursor.rowcount


def update_active_app_session_expirations(expires_at: str) -> int:
    now = utc_now_text()
    with connect() as conn:
        cursor = conn.execute(
            """
            UPDATE app_sessions
            SET expires_at = ?
            WHERE revoked_at IS NULL AND expires_at > ?
            """,
            (expires_at, now),
        )
        return cursor.rowcount


def upsert_metric(device_id: str, metric: HealthMetricIn) -> None:
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO latest_metrics (
                device_id, metric_id, category, title, value, unit, measured_at,
                aggregation, icon, device_class, state_class, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(device_id, metric_id) DO UPDATE SET
                category = excluded.category,
                title = excluded.title,
                value = excluded.value,
                unit = excluded.unit,
                measured_at = excluded.measured_at,
                aggregation = excluded.aggregation,
                icon = excluded.icon,
                device_class = excluded.device_class,
                state_class = excluded.state_class,
                updated_at = CURRENT_TIMESTAMP
            """,
            (
                device_id,
                metric.id,
                metric.category,
                metric.title,
                metric.value,
                metric.unit,
                metric.measured_at.isoformat(),
                metric.aggregation,
                metric.icon,
                metric.device_class,
                metric.state_class,
            ),
        )


def list_latest() -> list[dict]:
    with connect() as conn:
        rows = conn.execute(
            """
            SELECT * FROM latest_metrics
            ORDER BY category, title
            """
        ).fetchall()
    return [dict(row) for row in rows]


def upsert_imported_workout(device_id: str, workout: ImportedWorkoutIn) -> dict[str, object]:
    route_json = json.dumps(
        [point.model_dump(mode="json") for point in workout.route],
        separators=(",", ":"),
    )
    weather_json = workout.weather.model_dump_json() if workout.weather else None
    injury_json = workout.injury.model_dump_json() if workout.injury else None
    explicit_duration = float(workout.duration_minutes or 0) * 60
    duration_seconds = max((workout.end - workout.start).total_seconds(), explicit_duration, 0)
    start_time = workout.start.isoformat()
    end_time = workout.end.isoformat()
    with connect() as conn:
        existing = conn.execute(
            """
            SELECT 1 FROM imported_workouts
            WHERE device_id = ? AND workout_id = ?
            """,
            (device_id, workout.id),
        ).fetchone()
        if workout.source != "apple_health":
            conn.execute(
                """
                DELETE FROM imported_workouts
                WHERE device_id = ?
                  AND workout_id != ?
                  AND source = ?
                  AND lower(trim(sport)) = lower(trim(?))
                  AND lower(trim(title)) = lower(trim(?))
                  AND (
                    (start_time = ? OR datetime(start_time) = datetime(?))
                    OR abs(strftime('%s', start_time) - strftime('%s', ?)) <= 120
                  )
                  AND (
                    (end_time = ? OR datetime(end_time) = datetime(?))
                    OR abs(COALESCE(duration_seconds, 0) - ?) <= 300
                  )
                """,
                (
                    device_id,
                    workout.id,
                    workout.source,
                    workout.sport,
                    workout.title,
                    start_time,
                    start_time,
                    start_time,
                    end_time,
                    end_time,
                    duration_seconds,
                ),
            )
            _delete_orphan_import_details(conn)
        conn.execute(
            """
            INSERT INTO imported_workouts (
                device_id, workout_id, source, sport, title, start_time, end_time,
                duration_seconds, distance_km, energy_kcal, average_heart_rate,
                max_heart_rate, notes, weather_json, injury_json, route_json, route_points, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(device_id, workout_id) DO UPDATE SET
                source = excluded.source,
                sport = excluded.sport,
                title = excluded.title,
                start_time = excluded.start_time,
                end_time = excluded.end_time,
                duration_seconds = excluded.duration_seconds,
                distance_km = excluded.distance_km,
                energy_kcal = excluded.energy_kcal,
                average_heart_rate = excluded.average_heart_rate,
                max_heart_rate = excluded.max_heart_rate,
                notes = excluded.notes,
                weather_json = excluded.weather_json,
                injury_json = excluded.injury_json,
                route_json = excluded.route_json,
                route_points = excluded.route_points,
                updated_at = CURRENT_TIMESTAMP
            """,
            (
                device_id,
                workout.id,
                workout.source,
                workout.sport,
                workout.title,
                start_time,
                end_time,
                duration_seconds,
                workout.distance_km,
                workout.energy_kcal,
                workout.average_heart_rate,
                workout.max_heart_rate,
                workout.notes,
                weather_json,
                injury_json,
                route_json,
                len(workout.route),
            ),
        )
        conn.execute(
            """
            DELETE FROM imported_workout_sets
            WHERE device_id = ? AND workout_id = ?
            """,
            (device_id, workout.id),
        )
        conn.execute(
            """
            DELETE FROM imported_workout_exercises
            WHERE device_id = ? AND workout_id = ?
            """,
            (device_id, workout.id),
        )
        exercise_count = 0
        set_count = 0
        volume_kg = 0.0
        max_weight_kg: float | None = None
        best_set_volume_kg: float | None = None
        personal_records = 0
        for exercise_index, exercise in enumerate(workout.exercises):
            exercise_id = (
                str(exercise.id or "").strip()
                or str(exercise.catalog_id or "").strip()
                or f"exercise-{exercise_index + 1}"
            )
            exercise_start = exercise.start.isoformat() if exercise.start else None
            exercise_end = exercise.end.isoformat() if exercise.end else None
            exercise_duration = exercise.duration_seconds
            if exercise_duration is None and exercise.start and exercise.end:
                exercise_duration = max((exercise.end - exercise.start).total_seconds(), 0)
            exercise_count += 1
            conn.execute(
                """
                INSERT INTO imported_workout_exercises (
                    device_id, workout_id, exercise_id, exercise_index, catalog_id,
                    name, category, start_time, end_time, duration_seconds,
                    notes, device_settings_json, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(device_id, workout_id, exercise_id) DO UPDATE SET
                    exercise_index = excluded.exercise_index,
                    catalog_id = excluded.catalog_id,
                    name = excluded.name,
                    category = excluded.category,
                    start_time = excluded.start_time,
                    end_time = excluded.end_time,
                    duration_seconds = excluded.duration_seconds,
                    notes = excluded.notes,
                    device_settings_json = excluded.device_settings_json,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (
                    device_id,
                    workout.id,
                    exercise_id,
                    exercise_index,
                    exercise.catalog_id,
                    exercise.name,
                    exercise.category,
                    exercise_start,
                    exercise_end,
                    exercise_duration,
                    exercise.notes,
                    json.dumps(exercise.device_settings or {}, separators=(",", ":")),
                ),
            )
            for set_index, workout_set in enumerate(exercise.sets):
                set_id = str(workout_set.id or "").strip() or f"set-{workout_set.index or set_index + 1}"
                reps = workout_set.reps
                weight_kg = workout_set.weight_kg
                calculated_volume = None
                if reps is not None and weight_kg is not None:
                    calculated_volume = float(reps) * float(weight_kg)
                set_volume = workout_set.volume_kg if workout_set.volume_kg is not None else calculated_volume
                if set_volume is not None:
                    volume_kg += float(set_volume)
                    best_set_volume_kg = max(best_set_volume_kg or 0, float(set_volume))
                if weight_kg is not None:
                    max_weight_kg = max(max_weight_kg or 0, float(weight_kg))
                if workout_set.is_personal_record:
                    personal_records += 1
                set_count += 1
                conn.execute(
                    """
                    INSERT INTO imported_workout_sets (
                        device_id, workout_id, exercise_id, set_id, set_index, set_type,
                        reps, weight_kg, rpe, volume_kg, is_personal_record, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(device_id, workout_id, exercise_id, set_id) DO UPDATE SET
                        set_index = excluded.set_index,
                        set_type = excluded.set_type,
                        reps = excluded.reps,
                        weight_kg = excluded.weight_kg,
                        rpe = excluded.rpe,
                        volume_kg = excluded.volume_kg,
                        is_personal_record = excluded.is_personal_record,
                        updated_at = CURRENT_TIMESTAMP
                    """,
                    (
                        device_id,
                        workout.id,
                        exercise_id,
                        workout_set.id or set_id,
                        workout_set.index or set_index + 1,
                        workout_set.type,
                        reps,
                        weight_kg,
                        workout_set.rpe,
                        set_volume,
                        1 if workout_set.is_personal_record else 0,
                    ),
                )
        return {
            "id": workout.id,
            "status": "updated" if existing else "created",
            "source": workout.source,
            "exercise_count": exercise_count,
            "set_count": set_count,
            "volume_kg": volume_kg,
            "max_weight_kg": max_weight_kg,
            "best_set_volume_kg": best_set_volume_kg,
            "personal_records": personal_records,
        }


def delete_imported_workout(device_id: str, workout_id: str, source: str | None = None) -> bool:
    source = str(normalize_workout_source(source) or "").strip()
    with connect() as conn:
        if source:
            cursor = conn.execute(
                """
                DELETE FROM imported_workouts
                WHERE device_id = ? AND workout_id = ? AND source = ?
                """,
                (device_id, workout_id, source),
            )
            deleted = cursor.rowcount > 0
            if deleted:
                _delete_orphan_import_details(conn)
            return deleted
        cursor = conn.execute(
            """
            DELETE FROM imported_workouts
            WHERE device_id = ? AND workout_id = ?
            """,
            (device_id, workout_id),
        )
        deleted = cursor.rowcount > 0
        if deleted:
            _delete_orphan_import_details(conn)
        return deleted


def delete_missing_imported_workouts(device_id: str, source: str, keep_ids: list[str]) -> int:
    source = str(normalize_workout_source(source) or "").strip()
    keep = {str(item) for item in keep_ids if str(item)}
    with connect() as conn:
        if not keep:
            cursor = conn.execute(
                """
                DELETE FROM imported_workouts
                WHERE device_id = ? AND source = ?
                """,
                (device_id, source),
            )
            _delete_orphan_import_details(conn)
            return cursor.rowcount

        rows = conn.execute(
            """
            SELECT workout_id
            FROM imported_workouts
            WHERE device_id = ? AND source = ?
            """,
            (device_id, source),
        ).fetchall()
        stale = [row["workout_id"] for row in rows if row["workout_id"] not in keep]
        if not stale:
            return 0
        conn.executemany(
            """
            DELETE FROM imported_workouts
            WHERE device_id = ? AND source = ? AND workout_id = ?
            """,
            [(device_id, source, workout_id) for workout_id in stale],
        )
        _delete_orphan_import_details(conn)
        return len(stale)


def _delete_orphan_import_details(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        DELETE FROM imported_workout_sets
        WHERE NOT EXISTS (
            SELECT 1
            FROM imported_workouts w
            WHERE w.device_id = imported_workout_sets.device_id
              AND w.workout_id = imported_workout_sets.workout_id
        )
        """
    )
    conn.execute(
        """
        DELETE FROM imported_workout_exercises
        WHERE NOT EXISTS (
            SELECT 1
            FROM imported_workouts w
            WHERE w.device_id = imported_workout_exercises.device_id
              AND w.workout_id = imported_workout_exercises.workout_id
        )
        """
    )


def _delete_exact_duplicate_imported_workouts(conn: sqlite3.Connection) -> int:
    rows = conn.execute("SELECT rowid AS _rowid, * FROM imported_workouts ORDER BY rowid").fetchall()
    if len(rows) < 2:
        return 0

    exercise_rows = conn.execute(
        "SELECT * FROM imported_workout_exercises ORDER BY device_id, workout_id, exercise_index, exercise_id"
    ).fetchall()
    set_rows = conn.execute(
        "SELECT * FROM imported_workout_sets ORDER BY device_id, workout_id, exercise_id, set_index, set_id"
    ).fetchall()
    exercises: dict[tuple[str, str], list[tuple]] = {}
    sets: dict[tuple[str, str], list[tuple]] = {}
    for row in exercise_rows:
        key = (str(row["device_id"]), str(row["workout_id"]))
        exercises.setdefault(key, []).append((
            row["exercise_index"], row["catalog_id"], row["name"], row["category"],
            row["start_time"], row["end_time"], row["duration_seconds"], row["notes"],
            row["device_settings_json"],
        ))
    for row in set_rows:
        key = (str(row["device_id"]), str(row["workout_id"]))
        sets.setdefault(key, []).append((
            row["set_index"], row["set_type"], row["reps"], row["weight_kg"], row["rpe"],
            row["volume_kg"], row["is_personal_record"],
        ))

    seen: dict[tuple, int] = {}
    duplicate_rowids: list[int] = []
    for row in rows:
        key = (str(row["device_id"]), str(row["workout_id"]))
        route_json = str(row["route_json"] or "[]")
        fingerprint = (
            row["device_id"], row["source"], row["sport"], row["title"],
            row["start_time"], row["end_time"], row["duration_seconds"], row["distance_km"],
            row["energy_kcal"], row["average_heart_rate"], row["max_heart_rate"], row["notes"],
            row["weather_json"], row["injury_json"], hashlib.sha256(route_json.encode()).digest(),
            tuple(exercises.get(key, [])), tuple(sets.get(key, [])),
        )
        if fingerprint in seen:
            duplicate_rowids.append(int(row["_rowid"]))
        else:
            seen[fingerprint] = int(row["_rowid"])

    if duplicate_rowids:
        conn.executemany("DELETE FROM imported_workouts WHERE rowid = ?", [(rowid,) for rowid in duplicate_rowids])
    return len(duplicate_rowids)


def normalize_gympit_import_sources(device_ids: list[str] | None = None) -> int:
    clean_device_ids = [str(item).strip() for item in (device_ids or []) if str(item).strip()]
    with connect() as conn:
        total = 0
        if clean_device_ids:
            cursor = conn.execute(
                f"""
                UPDATE imported_workouts
                SET source = 'gympit',
                    updated_at = CURRENT_TIMESTAMP
                WHERE source IN ('manual', 'gpx', 'tcx')
                  AND device_id IN ({','.join('?' for _ in clean_device_ids)})
                """,
                tuple(clean_device_ids),
            )
            total += cursor.rowcount
        cursor = conn.execute(
            """
            UPDATE imported_workouts
            SET source = 'gympit',
                updated_at = CURRENT_TIMESTAMP
            WHERE source IN ('manual', 'gpx', 'tcx')
              AND lower(device_id) LIKE '%gympit%'
            """
        )
        return total + cursor.rowcount


def list_imported_workouts(
    limit: int = 100,
    offset: int = 0,
    device_prefix: str | None = None,
    include_route: bool = False,
    route_max_points: int | None = None,
    source: str | None = None,
    excluded_source: str | None = None,
    updated_after: str | None = None,
) -> list[dict]:
    with connect() as conn:
        clauses: list[str] = []
        params_list: list[object] = []
        if device_prefix:
            clauses.append("device_id LIKE ?")
            params_list.append(f"{device_prefix}%")
        if source:
            source = str(normalize_workout_source(source) or "").strip()
            clauses.append("source = ?")
            params_list.append(source)
        if excluded_source:
            excluded_source = str(normalize_workout_source(excluded_source) or "").strip()
            clauses.append("source != ?")
            params_list.append(excluded_source)
        if updated_after:
            clauses.append("datetime(updated_at) > datetime(?)")
            params_list.append(updated_after)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        params = (*params_list, limit, offset)
        route_json_select = "route_json" if include_route else "NULL AS route_json"
        rows = conn.execute(
            f"""
            SELECT
                device_id,
                workout_id,
                source,
                sport,
                title,
                start_time,
                end_time,
                duration_seconds,
                distance_km,
                energy_kcal,
                average_heart_rate,
                max_heart_rate,
                notes,
                weather_json,
                injury_json,
                {route_json_select},
                updated_at,
                route_points
            FROM imported_workouts
            {where}
            ORDER BY start_time DESC
            LIMIT ?
            OFFSET ?
            """,
            params,
        ).fetchall()
    out = []
    for row in rows:
        item = dict(row)
        item["weather"] = json.loads(item.pop("weather_json") or "null")
        item["injury"] = json.loads(item.pop("injury_json") or "null")
        if include_route:
            try:
                route = json.loads(item.pop("route_json") or "[]")
                item["route_points"] = len(route)
                item["route"] = _sample_route(route, route_max_points)
            except Exception:
                item["route_points"] = 0
                item["route"] = []
        else:
            item.pop("route_json", None)
        out.append(item)
    return _attach_imported_workout_details(_dedupe_imported_workouts(out))


def _attach_imported_workout_details(items: list[dict]) -> list[dict]:
    if not items:
        return items
    pairs = [
        (str(item.get("device_id") or ""), str(item.get("workout_id") or item.get("id") or ""))
        for item in items
    ]
    pairs = [pair for pair in pairs if pair[0] and pair[1]]
    exercises_by_workout: dict[tuple[str, str], list[dict]] = {}
    sets_by_workout: dict[tuple[str, str], list[dict]] = {}
    with connect() as conn:
        for chunk_start in range(0, len(pairs), 200):
            chunk = pairs[chunk_start:chunk_start + 200]
            placeholders = ",".join("(?, ?)" for _ in chunk)
            params = [value for pair in chunk for value in pair]
            exercise_rows = conn.execute(
                f"""
                SELECT * FROM imported_workout_exercises
                WHERE (device_id, workout_id) IN ({placeholders})
                ORDER BY device_id, workout_id, exercise_index ASC, name ASC
                """,
                params,
            ).fetchall()
            set_rows = conn.execute(
                f"""
                SELECT * FROM imported_workout_sets
                WHERE (device_id, workout_id) IN ({placeholders})
                ORDER BY device_id, workout_id, exercise_id ASC, set_index ASC
                """,
                params,
            ).fetchall()
            for row in exercise_rows:
                exercise = dict(row)
                key = (str(exercise.get("device_id") or ""), str(exercise.get("workout_id") or ""))
                exercises_by_workout.setdefault(key, []).append(exercise)
            for row in set_rows:
                workout_set = dict(row)
                key = (str(workout_set.get("device_id") or ""), str(workout_set.get("workout_id") or ""))
                sets_by_workout.setdefault(key, []).append(workout_set)

    for item in items:
        device_id = str(item.get("device_id") or "")
        workout_id = str(item.get("workout_id") or item.get("id") or "")
        exercise_rows = exercises_by_workout.get((device_id, workout_id), [])
        set_rows = sets_by_workout.get((device_id, workout_id), [])
        sets_by_exercise: dict[str, list[dict]] = {}
        for row in set_rows:
            workout_set = dict(row)
            workout_set["is_personal_record"] = bool(workout_set.get("is_personal_record"))
            sets_by_exercise.setdefault(str(workout_set.get("exercise_id") or ""), []).append(workout_set)
        exercises = []
        total_volume = 0.0
        max_weight_kg: float | None = None
        best_set_volume_kg: float | None = None
        personal_records = 0
        for row in exercise_rows:
            exercise = dict(row)
            try:
                exercise["device_settings"] = json.loads(exercise.pop("device_settings_json") or "{}")
            except Exception:
                exercise["device_settings"] = {}
            exercise_sets = sets_by_exercise.get(str(exercise.get("exercise_id") or ""), [])
            exercise_volume = sum(float(workout_set.get("volume_kg") or 0) for workout_set in exercise_sets)
            exercise_weights = [
                float(workout_set.get("weight_kg"))
                for workout_set in exercise_sets
                if workout_set.get("weight_kg") is not None
            ]
            exercise["sets"] = exercise_sets
            exercise["set_count"] = len(exercise_sets)
            exercise["volume_kg"] = exercise_volume
            exercise["best_weight_kg"] = max(exercise_weights) if exercise_weights else None
            exercise["personal_records"] = sum(1 for workout_set in exercise_sets if workout_set.get("is_personal_record"))
            total_volume += exercise_volume
            if exercise["best_weight_kg"] is not None:
                max_weight_kg = max(max_weight_kg or 0, float(exercise["best_weight_kg"]))
            for workout_set in exercise_sets:
                if workout_set.get("volume_kg") is not None:
                    best_set_volume_kg = max(best_set_volume_kg or 0, float(workout_set["volume_kg"]))
                if workout_set.get("is_personal_record"):
                    personal_records += 1
            exercises.append(exercise)
        item["exercises"] = exercises
        item["exercise_count"] = len(exercises)
        item["set_count"] = sum(len(exercise.get("sets") or []) for exercise in exercises)
        item["volume_kg"] = total_volume
        item["max_weight_kg"] = max_weight_kg
        item["best_set_volume_kg"] = best_set_volume_kg
        item["personal_records"] = personal_records
    return items


def _dedupe_imported_workouts(items: list[dict]) -> list[dict]:
    by_key: dict[str, dict] = {}
    order: list[str] = []
    for item in items:
        key = _semantic_import_key(item)
        if key in by_key:
            by_key[key] = _better_imported_workout(by_key[key], item)
        else:
            by_key[key] = item
            order.append(key)
    return [by_key[key] for key in order]


def _semantic_import_key(item: dict) -> str:
    source = item.get("source") or ""
    return "|".join(
        [
            str(item.get("device_id") or ""),
            source,
            _normalized_import_text(item.get("sport")),
            _normalized_import_text(item.get("title")),
            _minute_import_key(item.get("start_time")),
            _minute_import_key(item.get("end_time")),
        ]
    )


def _normalized_import_text(value: object) -> str:
    return " ".join(str(value or "").strip().lower().split())


def _minute_import_key(value: object) -> str:
    parsed = _parse_dt(str(value) if value is not None else None)
    if parsed:
        return parsed.strftime("%Y-%m-%dT%H:%M")
    return str(value or "")[:16]


def _better_imported_workout(left: dict, right: dict) -> dict:
    left_score = _imported_quality_score(left)
    right_score = _imported_quality_score(right)
    if left_score == right_score:
        return right if str(right.get("updated_at") or "") >= str(left.get("updated_at") or "") else left
    return right if right_score > left_score else left


def _imported_quality_score(item: dict) -> float:
    score = float(item.get("duration_seconds") or 0)
    score += float(item.get("distance_km") or 0) * 100
    score += float(item.get("route_points") or len(item.get("route") or []))
    if item.get("average_heart_rate"):
        score += 500
    if item.get("max_heart_rate"):
        score += 250
    if str(item.get("notes") or "").strip():
        score += 50
    if item.get("weather"):
        score += 25
    if item.get("injury"):
        score += 25
    return score


def _sample_route(route: list[dict], max_points: int | None) -> list[dict]:
    if not max_points or max_points <= 0 or len(route) <= max_points:
        return route
    if max_points <= 2:
        return route[:max_points]
    step = max(1, len(route) // max(1, max_points - 2))
    sampled = [route[0], *route[1:-1:step], route[-1]]
    return sampled[:max_points]


def imported_workout_summary(device_id: str | None = None) -> dict:
    workouts = list_unified_workouts(
        limit=10000,
        device_prefix=device_id if device_id else None,
        include_route=False,
        include_apple_health=True,
    )
    return {
        "workout_count": len(workouts),
        "duration_seconds": sum(float(item.get("duration_seconds") or 0) for item in workouts),
        "distance_km": sum(float(item.get("distance_km") or 0) for item in workouts),
        "latest_start": max((item.get("start_time") or "" for item in workouts), default=None),
    }


def upsert_hevy_workout(workout: dict) -> None:
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO hevy_workouts (id, title, start_time, end_time, updated_at, created_at, imported_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                start_time = excluded.start_time,
                end_time = excluded.end_time,
                updated_at = excluded.updated_at,
                created_at = excluded.created_at,
                imported_at = CURRENT_TIMESTAMP
            """,
            (
                workout.get("id", ""),
                workout.get("title") or "Workout",
                workout.get("start_time") or workout.get("created_at") or "",
                workout.get("end_time"),
                workout.get("updated_at"),
                workout.get("created_at"),
            ),
        )
        conn.execute("DELETE FROM hevy_exercise_sets WHERE workout_id = ?", (workout.get("id", ""),))
        for exercise_index, exercise in enumerate(workout.get("exercises") or []):
            title = exercise.get("title") or "Uebung"
            template_id = exercise.get("exercise_template_id")
            for set_index, item in enumerate(exercise.get("sets") or []):
                conn.execute(
                    """
                    INSERT INTO hevy_exercise_sets (
                        workout_id, exercise_index, set_index, exercise_template_id, exercise_title,
                        set_type, weight_kg, reps, distance_meters, duration_seconds, rpe,
                        workout_start_time, workout_title
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        workout.get("id", ""),
                        exercise_index,
                        set_index,
                        template_id,
                        title,
                        item.get("type"),
                        item.get("weight_kg"),
                        item.get("reps"),
                        item.get("distance_meters"),
                        item.get("duration_seconds"),
                        item.get("rpe"),
                        workout.get("start_time") or workout.get("created_at") or "",
                        workout.get("title") or "Workout",
                    ),
                )


def hevy_summary() -> dict:
    with connect() as conn:
        totals = conn.execute(
            """
            SELECT
                COUNT(DISTINCT workout_id) AS workout_count,
                COUNT(*) AS set_count,
                COALESCE(SUM(COALESCE(weight_kg, 0) * COALESCE(reps, 0)), 0) AS volume_kg
            FROM hevy_exercise_sets
            """
        ).fetchone()
        last_sync = conn.execute("SELECT MAX(imported_at) AS last_sync FROM hevy_workouts").fetchone()
        exercise_rows = conn.execute(
            """
            SELECT
                COALESCE(exercise_template_id, lower(replace(exercise_title, ' ', '_'))) AS exercise_id,
                exercise_title AS title,
                COUNT(*) AS set_count,
                COUNT(DISTINCT workout_id) AS workout_count,
                MAX(weight_kg) AS best_weight_kg,
                (
                    SELECT MAX(latest.weight_kg)
                    FROM hevy_exercise_sets latest
                    WHERE COALESCE(latest.exercise_template_id, lower(replace(latest.exercise_title, ' ', '_'))) =
                          COALESCE(hevy_exercise_sets.exercise_template_id, lower(replace(hevy_exercise_sets.exercise_title, ' ', '_')))
                      AND latest.workout_start_time = (
                          SELECT MAX(last_seen.workout_start_time)
                          FROM hevy_exercise_sets last_seen
                          WHERE COALESCE(last_seen.exercise_template_id, lower(replace(last_seen.exercise_title, ' ', '_'))) =
                                COALESCE(hevy_exercise_sets.exercise_template_id, lower(replace(hevy_exercise_sets.exercise_title, ' ', '_')))
                      )
                ) AS last_weight_kg,
                COALESCE(SUM(COALESCE(weight_kg, 0) * COALESCE(reps, 0)), 0) AS total_volume_kg,
                MAX(workout_start_time) AS last_workout_at
            FROM hevy_exercise_sets
            GROUP BY exercise_id, exercise_title
            ORDER BY last_workout_at DESC, set_count DESC
            LIMIT 50
            """
        ).fetchall()
        recent_rows = conn.execute(
            """
            SELECT
                workout_id AS id,
                workout_title AS title,
                workout_start_time AS start_time,
                COUNT(*) AS set_count,
                COUNT(DISTINCT exercise_title) AS exercise_count,
                COALESCE(SUM(COALESCE(weight_kg, 0) * COALESCE(reps, 0)), 0) AS volume_kg
            FROM hevy_exercise_sets
            GROUP BY workout_id, workout_title, workout_start_time
            ORDER BY workout_start_time DESC
            LIMIT 20
            """
        ).fetchall()
        recent = []
        for workout_row in recent_rows:
            exercise_detail_rows = conn.execute(
                """
                SELECT
                    COALESCE(exercise_template_id, lower(replace(exercise_title, ' ', '_'))) AS exercise_id,
                    exercise_title AS title,
                    COUNT(*) AS set_count,
                    MAX(weight_kg) AS best_weight_kg,
                    (
                        SELECT MAX(last_set.weight_kg)
                        FROM hevy_exercise_sets last_set
                        WHERE last_set.workout_id = hevy_exercise_sets.workout_id
                          AND COALESCE(last_set.exercise_template_id, lower(replace(last_set.exercise_title, ' ', '_'))) =
                              COALESCE(hevy_exercise_sets.exercise_template_id, lower(replace(hevy_exercise_sets.exercise_title, ' ', '_')))
                    ) AS last_weight_kg,
                    COALESCE(SUM(COALESCE(weight_kg, 0) * COALESCE(reps, 0)), 0) AS volume_kg
                FROM hevy_exercise_sets
                WHERE workout_id = ?
                GROUP BY exercise_id, exercise_title, exercise_index
                ORDER BY exercise_index ASC
                """,
                (workout_row["id"],),
            ).fetchall()
            workout = dict(workout_row)
            workout["exercises"] = []
            for exercise_row in exercise_detail_rows:
                set_rows = conn.execute(
                    """
                    SELECT
                        set_index,
                        set_type,
                        weight_kg,
                        reps,
                        rpe,
                        distance_meters,
                        duration_seconds
                    FROM hevy_exercise_sets
                    WHERE workout_id = ?
                      AND COALESCE(exercise_template_id, lower(replace(exercise_title, ' ', '_'))) = ?
                    ORDER BY set_index ASC
                    """,
                    (workout_row["id"], exercise_row["exercise_id"]),
                ).fetchall()
                exercise = dict(exercise_row)
                exercise["id"] = exercise.get("exercise_id")
                exercise["name"] = exercise.get("title") or "Übung"
                exercise["category"] = "strength"
                exercise["source"] = "hevy"
                exercise["sets"] = [dict(set_row) for set_row in set_rows]
                workout["exercises"].append(exercise)
            recent.append(workout)

        exercises = []
        for row in exercise_rows:
            trend_rows = conn.execute(
                """
                SELECT
                    substr(workout_start_time, 1, 10) AS day,
                    MAX(weight_kg) AS weight_kg,
                    COUNT(*) AS sets,
                    COALESCE(SUM(COALESCE(weight_kg, 0) * COALESCE(reps, 0)), 0) AS volume_kg
                FROM hevy_exercise_sets
                WHERE COALESCE(exercise_template_id, lower(replace(exercise_title, ' ', '_'))) = ?
                GROUP BY day
                ORDER BY day ASC
                LIMIT 120
                """,
                (row["exercise_id"],),
            ).fetchall()
            item = dict(row)
            item["trend"] = [dict(trend) for trend in trend_rows]
            exercises.append(item)

    return {
        "last_sync": last_sync["last_sync"] if last_sync else None,
        "total_workouts": totals["workout_count"] if totals else 0,
        "total_sets": totals["set_count"] if totals else 0,
        "total_volume_kg": totals["volume_kg"] if totals else 0,
        "recent_workouts": recent,
        "exercises": exercises,
    }


def list_unified_workouts(
    limit: int = 100,
    offset: int = 0,
    device_prefix: str | None = None,
    include_route: bool = False,
    route_max_points: int | None = None,
    source: str | None = None,
    excluded_source: str | None = None,
    updated_after: str | None = None,
    include_apple_health: bool = True,
) -> list[dict]:
    """Return workouts already linked across Apple Health/local imports and Hevy.

    The app and Home Assistant must not re-link workouts independently. Once
    Hevy and Apple/local data are close enough, the API returns one workout with
    all sources attached.
    """
    imported = list_imported_workouts(
        limit=max(limit + offset, 10000),
        offset=0,
        device_prefix=device_prefix,
        include_route=include_route,
        route_max_points=route_max_points,
        source=source,
        excluded_source=excluded_source,
        updated_after=updated_after,
    )
    if not include_apple_health:
        imported = [item for item in imported if item.get("source") != "apple_health"]

    hevy_items = [] if source else hevy_summary().get("recent_workouts", [])
    overrides = list_workout_link_overrides()
    forced_merges = {_pair_key(row["primary_key"], row["linked_key"]) for row in overrides if row["action"] == "merge"}
    forced_separates = {_pair_key(row["primary_key"], row["linked_key"]) for row in overrides if row["action"] == "separate"}
    used_imported: set[str] = set()
    out: list[dict] = []

    for hevy in hevy_items:
        hevy_start = _parse_dt(hevy.get("start_time"))
        if not hevy_start:
            continue
        hevy_key = _source_key("hevy", hevy.get("id"))
        candidates = [
            item for item in imported
            if _imported_key(item) not in used_imported
            and _pair_key(hevy_key, _workout_source_key(item)) not in forced_separates
            and (_is_close_to_hevy(item, hevy_start) or _pair_key(hevy_key, _workout_source_key(item)) in forced_merges)
        ]
        apple = _closest_import(candidates, hevy_start, source="apple_health")
        local = _closest_import(
            [item for item in candidates if _imported_key(item) != _imported_key(apple)],
            hevy_start,
            excluded_source="apple_health",
        )
        linked = [item for item in (apple, local) if item]
        for item in linked:
            used_imported.add(_imported_key(item))
        out.append(_merge_workout(hevy=hevy, imported=linked))

    remaining_imported = [item for item in imported if _imported_key(item) not in used_imported]
    for group in _group_imported_workouts(remaining_imported, forced_merges, forced_separates):
        for item in group:
            used_imported.add(_imported_key(item))
        out.append(_merge_workout(imported=group))

    out = _apply_forced_import_merges(out, forced_merges)
    out = _dedupe_unified_workouts(out, forced_separates)

    out.sort(key=lambda item: item.get("start_time") or "", reverse=True)
    return out[offset:offset + limit]


def _group_imported_workouts(
    items: list[dict],
    forced_merges: set[tuple[str, str]],
    forced_separates: set[tuple[str, str]],
) -> list[list[dict]]:
    if not items:
        return []

    remaining = {_imported_key(item): item for item in items}
    buckets: dict[tuple[str, int], list[str]] = {}
    cross_device_buckets: dict[int, list[str]] = {}
    for key, item in remaining.items():
        bucket = _import_time_bucket(item)
        if bucket is not None:
            buckets.setdefault((str(item.get("device_id") or ""), bucket), []).append(key)
            if item.get("source") in {"apple_health", "gympit"}:
                cross_device_buckets.setdefault(bucket, []).append(key)

    groups: list[list[dict]] = []
    for key in [_imported_key(item) for item in items]:
        item = remaining.pop(key, None)
        if not item:
            continue
        group = [item]
        candidate_keys = _candidate_import_keys(item, remaining, buckets, cross_device_buckets, forced_merges)
        for other_key in candidate_keys:
            other = remaining.get(other_key)
            if not other:
                continue
            pair = _pair_key(_workout_source_key(item), _workout_source_key(other))
            if pair in forced_separates:
                continue
            if pair in forced_merges or _is_same_imported_workout(item, other):
                group.append(remaining.pop(other_key))
        groups.append(group)
    return groups


def _candidate_import_keys(
    item: dict,
    remaining: dict[str, dict],
    buckets: dict[tuple[str, int], list[str]],
    cross_device_buckets: dict[int, list[str]],
    forced_merges: set[tuple[str, str]],
) -> list[str]:
    keys: set[str] = set()
    bucket = _import_time_bucket(item)
    if bucket is not None:
        device_id = str(item.get("device_id") or "")
        for offset in (-1, 0, 1):
            keys.update(buckets.get((device_id, bucket + offset), []))
            if item.get("source") in {"apple_health", "gympit"}:
                keys.update(
                    key for key in cross_device_buckets.get(bucket + offset, [])
                    if _is_apple_health_gympit_pair(item, remaining.get(key, {}))
                )
    if forced_merges:
        item_key = _workout_source_key(item)
        keys.update(
            key for key, other in remaining.items()
            if _pair_key(item_key, _workout_source_key(other)) in forced_merges
        )
    keys.discard(_imported_key(item))
    return [key for key in keys if key in remaining]


def _is_apple_health_gympit_pair(left: dict, right: dict) -> bool:
    return {left.get("source"), right.get("source")} == {"apple_health", "gympit"}


def _is_same_imported_workout(left: dict, right: dict) -> bool:
    if left.get("source") == right.get("source"):
        return False

    left_start = _import_timestamp(left.get("start_time"))
    right_start = _import_timestamp(right.get("start_time"))
    if left_start is None or right_start is None:
        return False
    if abs(left_start - right_start) > 20 * 60:
        return False

    left_duration = float(left.get("duration_seconds") or 0)
    right_duration = float(right.get("duration_seconds") or 0)
    if left_duration and right_duration:
        allowed_duration_diff = max(15 * 60, max(left_duration, right_duration) * 0.35)
        if abs(left_duration - right_duration) > allowed_duration_diff:
            return False

    left_distance = left.get("distance_km")
    right_distance = right.get("distance_km")
    if left_distance is not None and right_distance is not None:
        left_distance = float(left_distance)
        right_distance = float(right_distance)
        allowed_distance_diff = max(0.75, max(left_distance, right_distance) * 0.3)
        if abs(left_distance - right_distance) > allowed_distance_diff:
            return False

    return True


def _import_time_bucket(item: dict) -> int | None:
    timestamp = _import_timestamp(item.get("start_time"))
    if timestamp is None:
        return None
    return int(timestamp // (20 * 60))


def _import_timestamp(value: object) -> float | None:
    parsed = _parse_dt(str(value) if value is not None else None)
    return parsed.timestamp() if parsed else None


def _merge_workout(*, hevy: dict | None = None, imported: list[dict] | None = None) -> dict:
    imported = imported or []
    primary = _best_imported_workout(imported)
    detail_owner = next((item for item in imported if item.get("exercises")), None) or (
        hevy if hevy and hevy.get("exercises") else primary
    )
    route_owner = max(imported, key=lambda item: int(item.get("route_points") or len(item.get("route") or [])), default=None)
    sources = []
    if primary:
        sources.extend(item.get("source") for item in imported if item.get("source"))
    if hevy:
        sources.append("hevy")
    source_order = ["apple_health", "gympit", "garmin", "manual", "gpx", "tcx", "hevy"]
    sources = sorted(set(sources), key=lambda value: source_order.index(value) if value in source_order else 99)

    start = hevy.get("start_time") if hevy else primary.get("start_time")
    end = primary.get("end_time") if primary else start
    workout_id = _unified_id(hevy, imported)
    title = "Krafttraining" if hevy else primary.get("title") or primary.get("sport") or "Workout"
    sport = "Krafttraining" if hevy else primary.get("sport") or primary.get("title") or "Workout"

    merged = {
        "device_id": primary.get("device_id") if primary else "",
        "workout_id": workout_id,
        "id": workout_id,
        "source": "merged" if len(sources) > 1 else (sources[0] if sources else "bridge"),
        "sources": sources,
        "source_ids": {
            item.get("source"): item.get("workout_id")
            for item in imported
            if item.get("source") and item.get("workout_id")
        },
        "sport": sport,
        "title": title,
        "start_time": start,
        "start": start,
        "end_time": end,
        "end": end,
        "duration_seconds": _first_present(imported, "duration_seconds") or 0,
        "distance_km": _first_present(imported, "distance_km"),
        "energy_kcal": _first_present(imported, "energy_kcal"),
        "average_heart_rate": _first_present(imported, "average_heart_rate"),
        "max_heart_rate": _first_present(imported, "max_heart_rate"),
        "notes": "\n\n".join(item.get("notes") or "" for item in imported if item.get("notes")),
        "weather": _first_present(imported, "weather"),
        "injury": _first_present(imported, "injury"),
        "exercises": detail_owner.get("exercises", []) if detail_owner else [],
        "exercise_count": detail_owner.get("exercise_count", 0) if detail_owner else 0,
        "set_count": detail_owner.get("set_count", 0) if detail_owner else 0,
        "volume_kg": detail_owner.get("volume_kg", 0) if detail_owner else 0,
        "max_weight_kg": detail_owner.get("max_weight_kg") if detail_owner else None,
        "best_set_volume_kg": detail_owner.get("best_set_volume_kg") if detail_owner else None,
        "personal_records": detail_owner.get("personal_records", 0) if detail_owner else 0,
        "route_points": route_owner.get("route_points", 0) if route_owner else 0,
        "route_points_total": (
            (route_owner.get("route_points_total") or route_owner.get("route_points", 0))
            if route_owner else 0
        ),
        "route": route_owner.get("route", []) if route_owner and "route" in route_owner else [],
        "updated_at": max((item.get("updated_at") or "" for item in imported), default=""),
        "stats": [],
    }
    if hevy:
        merged["hevy"] = hevy
        if not merged["exercises"] and hevy.get("exercises"):
            merged["exercises"] = hevy.get("exercises", [])
            merged["exercise_count"] = hevy.get("exercise_count", 0)
            merged["set_count"] = hevy.get("set_count", 0)
            merged["volume_kg"] = hevy.get("volume_kg", 0)
        merged["source_ids"]["hevy"] = hevy.get("id")
        merged["stats"].extend([
            {"label": "Übungen", "value": hevy.get("exercise_count"), "systemImage": "dumbbell"},
            {"label": "Sätze", "value": hevy.get("set_count"), "systemImage": "list.number"},
            {"label": "Volumen", "value": f"{round(float(hevy.get('volume_kg') or 0))} kg", "systemImage": "scalemass"},
        ])
    elif detail_owner and int(detail_owner.get("set_count") or 0) > 0:
        merged["stats"].extend([
            {"label": "Übungen", "value": detail_owner.get("exercise_count"), "systemImage": "dumbbell"},
            {"label": "Sätze", "value": detail_owner.get("set_count"), "systemImage": "list.number"},
            {"label": "Volumen", "value": f"{round(float(detail_owner.get('volume_kg') or 0))} kg", "systemImage": "scalemass"},
        ])
    merged["stats"].extend(_base_workout_stats(primary))
    merged["stats"] = _dedupe_stats(merged["stats"])
    return merged


def _apply_forced_import_merges(workouts: list[dict], forced_merges: set[tuple[str, str]]) -> list[dict]:
    if not forced_merges:
        return workouts
    out: list[dict] = []
    consumed: set[int] = set()
    for index, workout in enumerate(workouts):
        if index in consumed:
            continue
        group = [workout]
        keys = _merged_source_keys(workout)
        changed = True
        while changed:
            changed = False
            for other_index, other in enumerate(workouts):
                if other_index == index or other_index in consumed:
                    continue
                other_keys = _merged_source_keys(other)
                if any(_pair_key(left, right) in forced_merges for left in keys for right in other_keys):
                    group.append(other)
                    keys.update(other_keys)
                    consumed.add(other_index)
                    changed = True
        if len(group) == 1:
            out.append(workout)
        else:
            out.append(_merge_already_merged(group))
    return out


def _merge_already_merged(items: list[dict]) -> dict:
    imported = []
    hevy = None
    for item in items:
        if item.get("hevy") and not hevy:
            hevy = item["hevy"]
        source_ids = item.get("source_ids") or {}
        if source_ids:
            for source, workout_id in source_ids.items():
                if source == "hevy":
                    continue
                imported.append(_import_from_merged_item(item, source, workout_id))
        elif item.get("source") and item.get("source") != "hevy":
            imported.append(_import_from_merged_item(item, item.get("source"), item.get("workout_id")))
    return _merge_workout(hevy=hevy, imported=imported)


def _import_from_merged_item(item: dict, source: object, workout_id: object) -> dict:
    return {
        "device_id": item.get("device_id", ""),
        "workout_id": workout_id,
        "source": source,
        "sport": item.get("sport"),
        "title": item.get("title"),
        "start_time": item.get("start_time"),
        "end_time": item.get("end_time"),
        "duration_seconds": item.get("duration_seconds"),
        "distance_km": item.get("distance_km"),
        "energy_kcal": item.get("energy_kcal"),
        "average_heart_rate": item.get("average_heart_rate"),
        "max_heart_rate": item.get("max_heart_rate"),
        "notes": item.get("notes", ""),
        "weather": item.get("weather"),
        "injury": item.get("injury"),
        "exercises": item.get("exercises", []),
        "exercise_count": item.get("exercise_count", 0),
        "set_count": item.get("set_count", 0),
        "volume_kg": item.get("volume_kg", 0),
        "max_weight_kg": item.get("max_weight_kg"),
        "best_set_volume_kg": item.get("best_set_volume_kg"),
        "personal_records": item.get("personal_records", 0),
        "route_points": item.get("route_points", 0),
        "route_points_total": item.get("route_points_total", item.get("route_points", 0)),
        "route": item.get("route", []),
        "updated_at": item.get("updated_at", ""),
    }


def _dedupe_unified_workouts(
    workouts: list[dict],
    forced_separates: set[tuple[str, str]],
) -> list[dict]:
    out: list[dict] = []
    consumed: set[int] = set()
    for index, workout in enumerate(workouts):
        if index in consumed:
            continue
        group = [workout]
        keys = _merged_source_keys(workout)
        changed = True
        while changed:
            changed = False
            for other_index, other in enumerate(workouts):
                if other_index == index or other_index in consumed:
                    continue
                other_keys = _merged_source_keys(other)
                if _has_forced_separate(keys, other_keys, forced_separates):
                    continue
                if keys.intersection(other_keys):
                    group.append(other)
                    keys.update(other_keys)
                    consumed.add(other_index)
                    changed = True
        out.append(group[0] if len(group) == 1 else _merge_already_merged(group))
    return out


def _has_forced_separate(
    left_keys: set[str],
    right_keys: set[str],
    forced_separates: set[tuple[str, str]],
) -> bool:
    return any(_pair_key(left, right) in forced_separates for left in left_keys for right in right_keys)


def _merged_source_keys(workout: dict) -> set[str]:
    keys = set()
    for source, workout_id in (workout.get("source_ids") or {}).items():
        if source and workout_id:
            keys.add(_source_key(source, workout_id))
    if workout.get("source") and workout.get("workout_id"):
        keys.add(_source_key(workout["source"], workout["workout_id"]))
    return keys


def _base_workout_stats(item: dict | None) -> list[dict]:
    if not item:
        return []
    stats = []
    if item.get("duration_seconds"):
        stats.append({"label": "Dauer", "value": _format_duration(item["duration_seconds"]), "systemImage": "clock"})
    if item.get("distance_km"):
        stats.append({"label": "Distanz", "value": f"{float(item['distance_km']):.2f} km", "systemImage": "map"})
    if item.get("energy_kcal"):
        stats.append({"label": "Kalorien", "value": f"{round(float(item['energy_kcal']))} kcal", "systemImage": "flame"})
    if item.get("average_heart_rate"):
        stats.append({"label": "Ø Puls", "value": f"{round(float(item['average_heart_rate']))} bpm", "systemImage": "heart"})
    if item.get("max_heart_rate"):
        stats.append({"label": "Max Puls", "value": f"{round(float(item['max_heart_rate']))} bpm", "systemImage": "heart.fill"})
    return stats


def _dedupe_stats(stats: list[dict]) -> list[dict]:
    out = []
    seen = set()
    for stat in stats:
        label = str(stat.get("label") or "").strip().lower()
        value = stat.get("value")
        if not label or value in (None, "") or label in seen:
            continue
        seen.add(label)
        out.append(stat)
    return out


def _best_imported_workout(items: list[dict]) -> dict | None:
    if not items:
        return None
    priority = {"apple_health": 0, "gympit": 1, "garmin": 2, "manual": 3, "gpx": 4, "tcx": 5}
    return sorted(
        items,
        key=lambda item: (
            priority.get(item.get("source"), 9),
            -int(item.get("route_points") or len(item.get("route") or [])),
        ),
    )[0]


def _closest_import(
    items: list[dict],
    target: datetime,
    *,
    source: str | None = None,
    excluded_source: str | None = None,
) -> dict | None:
    filtered = []
    for item in items:
        if source and item.get("source") != source:
            continue
        if excluded_source and item.get("source") == excluded_source:
            continue
        start = _parse_dt(item.get("start_time") or item.get("start"))
        if start:
            filtered.append((abs((start - target).total_seconds()), item))
    return min(filtered, default=(None, None), key=lambda pair: pair[0])[1]


def _is_close_to_hevy(item: dict, hevy_start: datetime) -> bool:
    start = _parse_dt(item.get("start_time") or item.get("start"))
    if not start:
        return False
    distance = abs((start - hevy_start).total_seconds())
    same_day = start.date() == hevy_start.date()
    sport = f"{item.get('sport') or ''} {item.get('title') or ''}".lower()
    is_strength = "kraft" in sport or "strength" in sport
    return distance <= 90 * 60 or (same_day and is_strength)


def _unified_id(hevy: dict | None, imported: list[dict]) -> str:
    parts = []
    if hevy and hevy.get("id"):
        parts.append(f"hevy-{hevy['id']}")
    parts.extend(f"{item.get('source')}-{item.get('workout_id')}" for item in imported if item.get("workout_id"))
    return "merged-" + "-".join(parts) if len(parts) > 1 else (parts[0] if parts else "workout")


def _imported_key(item: dict | None) -> str:
    if not item:
        return ""
    return f"{item.get('device_id')}|{item.get('workout_id')}"


def _workout_source_key(item: dict) -> str:
    return _source_key(item.get("source"), item.get("workout_id"))


def _source_key(source: str | None, workout_id: object) -> str:
    return f"{source}:{workout_id}"


def _pair_key(left: str, right: str) -> tuple[str, str]:
    return tuple(sorted((left, right)))


def _first_present(items: list[dict], key: str):
    for item in items:
        value = item.get(key)
        if value:
            return value
    return None


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def _format_duration(seconds: float) -> str:
    minutes = round(float(seconds or 0) / 60)
    hours, rest = divmod(minutes, 60)
    return f"{hours} Std {rest} Min" if hours else f"{rest} Min"
