"""Übergangscode – HEALTHPIT-COMPAT-2026-08.

╔══════════════════════════════════════════════════════════════════════════╗
║  Two app versions are in the field: one that sends the old sensor ids     ║
║  only, and one that sends the central metric ids as well. This module     ║
║  makes the integration handle both correctly.                             ║
║                                                                           ║
║  It does not reject anything. Neither direction can damage the database:  ║
║  an old app's payload is translated here (``payload.normalize_metric``    ║
║  derives the canonical id from the legacy sensor id), and an old          ║
║  integration simply ignores the extra fields until it is updated and      ║
║  ``metrics.upgrade_storage`` fills them in. What the user gets is a       ║
║  visible hint, not a blocked sync.                                        ║
║                                                                           ║
║  To remove: see PROMPT-KOMPATIBILITAET-ENTFERNEN.md. Every related spot   ║
║  carries the marker, so `grep -r HEALTHPIT-COMPAT-2026-08` finds them.    ║
╚══════════════════════════════════════════════════════════════════════════╝
"""

from __future__ import annotations

from typing import Any

# HEALTHPIT-COMPAT-2026-08
MARKER = "HEALTHPIT-COMPAT-2026-08"

#: Data model this integration speaks.
#: 1 = sensor ids only (``step_count``), 2 = central metric ids and providers.
MODEL_VERSION = 2

#: What an app should speak. Below this the data is still accepted — it is
#: translated on the way in — but the user is told to update.
RECOMMENDED_APP_MODEL_VERSION = 2

#: Issue id in Home Assistant's repairs list. One per device, so two phones
#: do not overwrite each other's hint.
ISSUE_PREFIX = "outdated_app"

APP_UPDATE_HINT = (
    "The HealthPit app on this device still sends the old data format. "
    "Its values are translated and stored, so nothing is lost — but please "
    "update the app so it can send the metric ids itself."
)

INTEGRATION_UPDATE_HINT = (
    "This HealthPit integration is older than the app that is pushing. "
    "Please update the integration in HACS and restart Home Assistant."
)


def app_model_version(payload: Any, headers: Any = None) -> int:
    """Which model version the app claims to speak.

    An app that does not send the field at all is by definition the old one,
    so the answer is 1 rather than an error.
    """
    value: Any = None
    if isinstance(payload, dict):
        value = payload.get("model_version", payload.get("modelVersion"))
    if value is None and headers is not None:
        try:
            value = headers.get("X-HealthPit-Model-Version")
        except AttributeError:
            value = None
    try:
        return int(value)
    except (TypeError, ValueError):
        return 1


def app_is_current(payload: Any, headers: Any = None) -> bool:
    return app_model_version(payload, headers) >= RECOMMENDED_APP_MODEL_VERSION


def issue_id(device_id: str) -> str:
    return f"{ISSUE_PREFIX}_{device_id or 'unknown'}"


def annotate(metrics: list[dict[str, Any]], version: int) -> list[dict[str, Any]]:
    """Record which app version a value came from.

    Two reasons: the entity catalogue can show why a value has no metric id of
    its own, and after the transition it is one grep to find what is left.
    """
    if not metrics:
        return metrics
    for metric in metrics:
        metric["app_model_version"] = version
        if version < RECOMMENDED_APP_MODEL_VERSION:
            # The canonical id was derived here, not sent by the app.
            metric.setdefault("metric_id_source", "derived")
        else:
            metric.setdefault("metric_id_source", "app")
    return metrics


def status_fields() -> dict[str, Any]:
    """What every status answer carries, so the app can check the other side."""
    return {
        "model_version": MODEL_VERSION,
        "recommended_app_model_version": RECOMMENDED_APP_MODEL_VERSION,
        # Kept for apps built against the first draft of this handshake, which
        # read this name and refused to sync when it was missing.
        "required_app_model_version": RECOMMENDED_APP_MODEL_VERSION,
        "accepts_legacy_app": True,
    }
