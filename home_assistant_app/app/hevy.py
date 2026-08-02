from __future__ import annotations

from datetime import datetime, timezone
import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.models import HealthMetricIn
from app.store import (
    get_bridge_settings,
    hevy_summary,
    save_hevy_sync_status,
    upsert_hevy_workout,
    upsert_metric,
)


HEVY_API_BASE = "https://api.hevyapp.com"


def _get_json(path: str, api_key: str, query: dict[str, object] | None = None) -> dict:
    url = f"{HEVY_API_BASE}{path}"
    if query:
        url = f"{url}?{urlencode(query)}"
    request = Request(url, headers={"api-key": api_key, "Accept": "application/json"})
    with urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def sync_hevy_workouts() -> dict:
    attempted_at = datetime.now(timezone.utc).isoformat()
    current = get_bridge_settings()
    api_key = current["hevy_api_key"].strip()
    if not api_key:
        save_hevy_sync_status(attempted_at=attempted_at, error="Hevy API Key fehlt.")
        raise ValueError("Hevy API Key fehlt.")

    try:
        max_pages = max(1, min(int(current.get("hevy_max_pages") or "10"), 50))
        imported = 0
        for page in range(1, max_pages + 1):
            payload = _get_json("/v1/workouts", api_key, {"page": page, "pageSize": 10})
            workouts = payload.get("workouts") or []
            for workout in workouts:
                upsert_hevy_workout(workout)
                imported += 1
            if page >= int(payload.get("page_count") or page) or not workouts:
                break

        summary = hevy_summary()
        publish_hevy_metrics(summary)
        summary["imported_workouts"] = imported
        save_hevy_sync_status(
            attempted_at=attempted_at,
            success_at=datetime.now(timezone.utc).isoformat(),
            imported_workouts=imported,
        )
        return summary
    except Exception as error:
        save_hevy_sync_status(attempted_at=attempted_at, error=str(error))
        raise


def publish_hevy_metrics(summary: dict) -> None:
    measured_at = datetime.now(timezone.utc)
    device_id = "Hevy"
    metrics = [
        HealthMetricIn(
            id="hevy_workout_count",
            category="workouts",
            title="Hevy Workouts",
            value=float(summary["total_workouts"] or 0),
            unit="",
            measured_at=measured_at,
            aggregation="sum",
            icon="mdi:dumbbell",
            state_class="total",
        ),
        HealthMetricIn(
            id="hevy_set_count",
            category="workouts",
            title="Hevy Saetze",
            value=float(summary["total_sets"] or 0),
            unit="",
            measured_at=measured_at,
            aggregation="sum",
            icon="mdi:counter",
            state_class="total",
        ),
        HealthMetricIn(
            id="hevy_volume_kg",
            category="workouts",
            title="Hevy Trainingsvolumen",
            value=float(summary["total_volume_kg"] or 0),
            unit="kg",
            measured_at=measured_at,
            aggregation="sum",
            icon="mdi:weight-kilogram",
            state_class="total",
        ),
    ]
    for exercise in summary.get("exercises", [])[:20]:
        best = exercise.get("best_weight_kg")
        last = exercise.get("last_weight_kg")
        if best is not None:
            metrics.append(
                HealthMetricIn(
                    id=f"hevy_best_{exercise['exercise_id']}",
                    category="workouts",
                    title=f"Hevy Bestgewicht {exercise['title']}",
                    value=float(best),
                    unit="kg",
                    measured_at=measured_at,
                    aggregation="latest",
                    icon="mdi:weight-lifter",
                    state_class="measurement",
                )
            )
        if last is not None:
            metrics.append(
                HealthMetricIn(
                    id=f"hevy_last_{exercise['exercise_id']}",
                    category="workouts",
                    title=f"Hevy Letztes Gewicht {exercise['title']}",
                    value=float(last),
                    unit="kg",
                    measured_at=measured_at,
                    aggregation="latest",
                    icon="mdi:chart-line",
                    state_class="measurement",
                )
            )
    for metric in metrics:
        upsert_metric(device_id, metric)
