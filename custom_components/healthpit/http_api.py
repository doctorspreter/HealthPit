"""The push API.

``requires_auth`` means Home Assistant's own authentication guards these routes.
That does more than keep strangers out: it also tells us *who* pushed, because
Home Assistant attaches the token's owner to the request. Each user's data is
therefore separated by something the client cannot claim for itself.
"""

from __future__ import annotations

import logging
from typing import Any

from aiohttp import web

from homeassistant.components.http import HomeAssistantView
from homeassistant.core import HomeAssistant

from .const import API_BASE, DOMAIN
from .coordinator import HealthPitCoordinator
from .duplicates import find_candidates
from .route import as_geojson, as_gpx, as_svg, route_points
from .payload import (
    PayloadError,
    normalize_health_batch,
    normalize_link,
    normalize_reconcile,
    normalize_workout_batch,
    normalize_workout_source,
)

_LOGGER = logging.getLogger(__name__)

try:  # Home Assistant 2024.6+ exposes a typed key for this.
    from homeassistant.components.http import KEY_HASS
except ImportError:  # pragma: no cover - older cores
    KEY_HASS = "hass"


def _hass(request: web.Request) -> HomeAssistant:
    return request.app[KEY_HASS]


def _coordinator(request: web.Request) -> HealthPitCoordinator:
    coordinator = _hass(request).data.get(DOMAIN)
    if not isinstance(coordinator, HealthPitCoordinator):
        raise web.HTTPServiceUnavailable(reason="Healthpit is not set up")
    return coordinator


def _user(request: web.Request) -> tuple[str, str]:
    """Return (user_id, display name) of the token's owner."""
    user = request.get("hass_user")
    if user is None:
        # Should not happen on an authenticated view, but refusing beats
        # silently mixing several people's data into one bucket.
        raise web.HTTPUnauthorized(reason="Request carries no Home Assistant user")
    return user.id, str(getattr(user, "name", "") or "")


async def _json_body(request: web.Request) -> Any:
    try:
        return await request.json()
    except ValueError as err:
        raise web.HTTPBadRequest(reason="Body is not valid JSON") from err


def _positive_int(raw: Any, *, default: int) -> int:
    try:
        value = int(str(raw))
    except (TypeError, ValueError):
        return default
    return value if value > 0 else default


def _bad_request(err: PayloadError) -> web.Response:
    # Both keys on purpose: "detail" is what the app has always read, "error" is
    # the plainer name. Sending only one of them left the app showing a bare 400.
    _LOGGER.warning("Rejected a Healthpit push: %s", err)
    return web.json_response({"error": str(err), "detail": str(err)}, status=400)


class HealthPitHealthBatchView(HomeAssistantView):
    """Accept a batch of health metrics."""

    url = f"{API_BASE}/health/batch"
    name = f"api:{DOMAIN}:health_batch"
    requires_auth = True

    async def post(self, request: web.Request) -> web.Response:
        coordinator = _coordinator(request)
        user_id, user_name = _user(request)
        try:
            device_id, metrics, problems = normalize_health_batch(
                await _json_body(request)
            )
        except PayloadError as err:
            return _bad_request(err)

        if problems:
            _LOGGER.warning(
                "Skipped %s unusable metric(s) from %s: %s",
                len(problems),
                device_id,
                "; ".join(problems[:5]),
            )
        accepted = coordinator.store.upsert_metrics(
            user_id, user_name, device_id, metrics
        )
        coordinator.async_handle_push()
        return web.json_response({"accepted": accepted, "skipped": problems})


class HealthPitWorkoutImportView(HomeAssistantView):
    """Accept and list imported workouts."""

    url = f"{API_BASE}/workouts/imports"
    name = f"api:{DOMAIN}:workout_imports"
    requires_auth = True

    async def post(self, request: web.Request) -> web.Response:
        coordinator = _coordinator(request)
        user_id, user_name = _user(request)
        try:
            device_id, workouts = normalize_workout_batch(await _json_body(request))
        except PayloadError as err:
            return _bad_request(err)

        result = coordinator.store.upsert_workouts(
            user_id, user_name, device_id, workouts
        )
        coordinator.async_handle_push()
        return web.json_response({"accepted": len(workouts), **result})

    async def get(self, request: web.Request) -> web.Response:
        coordinator = _coordinator(request)
        user_id, _ = _user(request)
        query = request.query
        workouts = coordinator.store.unified_workouts(
            user_id,
            source=(query.get("source") or "").strip() or None,
            device_id=(query.get("device_id") or "").strip() or None,
            include_apple_health=query.get("include_apple_health", "true") != "false",
        )
        offset = _positive_int(query.get("offset"), default=0)
        limit = _positive_int(query.get("limit"), default=0)
        if offset:
            workouts = workouts[offset:]
        if limit:
            workouts = workouts[:limit]
        return web.json_response({"workouts": workouts})


class HealthPitWorkoutReconcileView(HomeAssistantView):
    """Drop workouts of one source that the app no longer has."""

    url = f"{API_BASE}/workouts/imports/reconcile"
    name = f"api:{DOMAIN}:workout_reconcile"
    requires_auth = True

    async def post(self, request: web.Request) -> web.Response:
        coordinator = _coordinator(request)
        user_id, _ = _user(request)
        try:
            device_id, source, workout_ids = normalize_reconcile(
                await _json_body(request)
            )
        except PayloadError as err:
            return _bad_request(err)

        deleted = coordinator.store.reconcile(user_id, device_id, source, workout_ids)
        if deleted:
            coordinator.async_handle_push()
        return web.json_response({"deleted": deleted, "kept": len(workout_ids)})


class HealthPitWorkoutItemView(HomeAssistantView):
    """Delete a single workout."""

    url = f"{API_BASE}/workouts/imports/{{workout_id}}"
    name = f"api:{DOMAIN}:workout_item"
    requires_auth = True

    async def delete(self, request: web.Request, workout_id: str) -> web.Response:
        coordinator = _coordinator(request)
        user_id, _ = _user(request)
        device_id = request.query.get("device_id", "").strip()
        if not device_id:
            return web.json_response({"error": "device_id is required"}, status=400)
        source = request.query.get("source", "").strip()
        deleted = coordinator.store.delete_workout(
            user_id,
            device_id,
            workout_id,
            normalize_workout_source(source) if source else None,
        )
        if deleted:
            coordinator.async_handle_push()
        return web.json_response({"deleted": deleted})


class HealthPitRouteView(HomeAssistantView):
    """Serve one stored track as GPX or GeoJSON.

    A track is only useful as a whole. GPX goes into any other tool, GeoJSON into
    a map card — both beat a few thousand separate entities.
    """

    url = f"{API_BASE}/workouts/{{workout_id}}/route.{{fmt}}"
    name = f"api:{DOMAIN}:workout_route"
    requires_auth = True

    async def get(
        self,
        request: web.Request,
        workout_id: str,
        fmt: str,
    ) -> web.Response:
        coordinator = _coordinator(request)
        user_id, _ = _user(request)
        workout = coordinator.store.workout(user_id, workout_id)
        if workout is None:
            raise web.HTTPNotFound(reason="No such workout")
        if not route_points(workout):
            raise web.HTTPNotFound(reason="This workout has no track")

        name = f"{workout.get('sport') or 'route'}-{str(workout.get('start_time') or '')[:10]}"
        if fmt == "gpx":
            return web.Response(
                body=as_gpx(workout),
                content_type="application/gpx+xml",
                headers={"Content-Disposition": f'attachment; filename="{name}.gpx"'},
            )
        if fmt == "geojson":
            return web.json_response(
                as_geojson(workout),
                content_type="application/geo+json",
            )
        if fmt == "svg":
            return web.Response(body=as_svg(workout), content_type="image/svg+xml")
        raise web.HTTPNotFound(reason="Unknown format; use gpx, geojson or svg")


class HealthPitDuplicatesView(HomeAssistantView):
    """Workouts that look like one session recorded twice, and past decisions."""

    url = f"{API_BASE}/duplicates"
    name = f"api:{DOMAIN}:duplicates"
    requires_auth = True

    async def get(self, request: web.Request) -> web.Response:
        coordinator = _coordinator(request)
        user_id, _ = _user(request)
        store = coordinator.store
        limit = _positive_int(request.query.get("limit"), default=200)
        links = store.links(user_id)
        return web.json_response(
            {
                "candidates": find_candidates(
                    store.unified_workouts(user_id), links, limit=limit
                ),
                "decisions": links,
            }
        )


class HealthPitDuplicateDecisionView(HomeAssistantView):
    """Record or withdraw a decision about a proposed duplicate."""

    url = f"{API_BASE}/duplicates/decision"
    name = f"api:{DOMAIN}:duplicate_decision"
    requires_auth = True

    async def post(self, request: web.Request) -> web.Response:
        coordinator = _coordinator(request)
        user_id, _ = _user(request)
        try:
            primary, linked, action = normalize_link(
                await _json_body(request), require_action=True
            )
        except PayloadError as err:
            return _bad_request(err)

        coordinator.store.save_link(user_id, primary, linked, action)
        # The decision changes how the workouts fold together, so the entities
        # have to be rebuilt right away rather than at the next push.
        coordinator.async_handle_push()
        return web.json_response({"primary": primary, "linked": linked, "action": action})

    async def delete(self, request: web.Request) -> web.Response:
        coordinator = _coordinator(request)
        user_id, _ = _user(request)
        try:
            primary, linked, _action = normalize_link(
                await _json_body(request), require_action=False
            )
        except PayloadError as err:
            return _bad_request(err)

        removed = coordinator.store.delete_link(user_id, primary, linked)
        if removed:
            coordinator.async_handle_push()
        return web.json_response({"removed": removed})


class HealthPitStatusView(HomeAssistantView):
    """What the app shows after connecting, and what a curl test needs."""

    url = f"{API_BASE}/status"
    name = f"api:{DOMAIN}:status"
    requires_auth = True

    async def get(self, request: web.Request) -> web.Response:
        coordinator = _coordinator(request)
        user_id, user_name = _user(request)
        return web.json_response(
            {
                "status": "ok",
                "user": user_name,
                "user_id": user_id,
                **coordinator.store.summary(user_id),
            }
        )


VIEWS = (
    HealthPitHealthBatchView,
    HealthPitWorkoutImportView,
    # Registered before the {workout_id} route so "reconcile" is not swallowed
    # as a workout ID.
    HealthPitWorkoutReconcileView,
    HealthPitWorkoutItemView,
    HealthPitRouteView,
    HealthPitDuplicateDecisionView,
    HealthPitDuplicatesView,
    HealthPitStatusView,
)


def async_register_views(hass: HomeAssistant) -> None:
    """Register the push API once."""
    flag = f"{DOMAIN}_views_registered"
    if hass.data.get(flag):
        return
    for view in VIEWS:
        hass.http.register_view(view())
    hass.data[flag] = True
    _LOGGER.debug("Registered the Healthpit push API at %s", API_BASE)
