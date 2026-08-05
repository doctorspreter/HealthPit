"""Turn a stored track into something usable.

One entity per GPS sample is not a route — it is a few thousand states that say
nothing on their own and draw no line on any map. A track only becomes useful as
a whole: a picture you can look at, a file you can export, a geometry a map card
can consume. This module produces all three from the points in the store, with
no dependency beyond the standard library.
"""

from __future__ import annotations

from math import cos, radians
from typing import Any
from xml.sax.saxutils import escape

# Rendered picture size. Large enough to recognise the shape on a dashboard,
# small enough to keep the payload tiny.
IMAGE_WIDTH = 640
IMAGE_HEIGHT = 400
IMAGE_PADDING = 16


def route_points(workout: dict[str, Any]) -> list[dict[str, Any]]:
    """Return the usable coordinates of one workout."""
    route = workout.get("route")
    if not isinstance(route, list):
        return []
    return [
        point
        for point in route
        if isinstance(point, dict)
        and isinstance(point.get("latitude"), (int, float))
        and isinstance(point.get("longitude"), (int, float))
    ]


def bounds(points: list[dict[str, Any]]) -> dict[str, float] | None:
    """Return the bounding box, which a map card needs to frame the track."""
    if not points:
        return None
    latitudes = [float(point["latitude"]) for point in points]
    longitudes = [float(point["longitude"]) for point in points]
    return {
        "north": max(latitudes),
        "south": min(latitudes),
        "east": max(longitudes),
        "west": min(longitudes),
    }


def _projected(points: list[dict[str, Any]]) -> list[tuple[float, float]]:
    """Project to a flat plane for drawing.

    A degree of longitude covers less ground the further from the equator, so it
    is scaled by the cosine of the latitude. Without that correction a run looks
    stretched sideways.
    """
    latitudes = [float(point["latitude"]) for point in points]
    longitudes = [float(point["longitude"]) for point in points]
    mid_latitude = (max(latitudes) + min(latitudes)) / 2
    scale = cos(radians(mid_latitude)) or 1.0
    return [(longitude * scale, latitude) for longitude, latitude in zip(longitudes, latitudes)]


def as_svg(workout: dict[str, Any]) -> bytes:
    """Draw the track as a self-contained SVG.

    Deliberately without a map background: tiles would mean a network request per
    view and a licence to respect. The bare line is enough to recognise which
    route it was.
    """
    points = route_points(workout)
    if len(points) < 2:
        return _empty_svg()

    flat = _projected(points)
    xs = [item[0] for item in flat]
    ys = [item[1] for item in flat]
    span_x = max(xs) - min(xs)
    span_y = max(ys) - min(ys)
    # A straight line has zero span in one direction; avoid dividing by it.
    scale = min(
        (IMAGE_WIDTH - 2 * IMAGE_PADDING) / span_x if span_x else float("inf"),
        (IMAGE_HEIGHT - 2 * IMAGE_PADDING) / span_y if span_y else float("inf"),
    )
    if scale == float("inf"):
        scale = 1.0

    offset_x = (IMAGE_WIDTH - span_x * scale) / 2
    offset_y = (IMAGE_HEIGHT - span_y * scale) / 2

    def place(point: tuple[float, float]) -> tuple[float, float]:
        x = (point[0] - min(xs)) * scale + offset_x
        # SVG counts y downwards, north belongs up.
        y = IMAGE_HEIGHT - ((point[1] - min(ys)) * scale + offset_y)
        return round(x, 1), round(y, 1)

    placed = [place(point) for point in flat]
    path = " ".join(f"{x},{y}" for x, y in placed)
    start_x, start_y = placed[0]
    end_x, end_y = placed[-1]
    label = escape(str(workout.get("title") or workout.get("sport") or "Route"))

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {IMAGE_WIDTH} {IMAGE_HEIGHT}" width="{IMAGE_WIDTH}" height="{IMAGE_HEIGHT}" role="img" aria-label="{label}">
  <rect width="{IMAGE_WIDTH}" height="{IMAGE_HEIGHT}" fill="none"/>
  <polyline points="{path}" fill="none" stroke="#03a9f4" stroke-width="4"
            stroke-linejoin="round" stroke-linecap="round"/>
  <circle cx="{start_x}" cy="{start_y}" r="7" fill="#4caf50"/>
  <circle cx="{end_x}" cy="{end_y}" r="7" fill="#f44336"/>
</svg>
""".encode("utf-8")


def _empty_svg() -> bytes:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {IMAGE_WIDTH} {IMAGE_HEIGHT}" width="{IMAGE_WIDTH}" height="{IMAGE_HEIGHT}"/>
""".encode("utf-8")


def as_gpx(workout: dict[str, Any]) -> bytes:
    """Serialise the track as GPX 1.1, the format every tool reads."""
    points = route_points(workout)
    name = escape(str(workout.get("title") or workout.get("sport") or "Healthpit"))
    start = escape(str(workout.get("start_time") or ""))

    segments = []
    for point in points:
        parts = [f'<trkpt lat="{float(point["latitude"]):.6f}" lon="{float(point["longitude"]):.6f}">']
        elevation = point.get("elevation")
        if isinstance(elevation, (int, float)):
            parts.append(f"<ele>{float(elevation):.1f}</ele>")
        timestamp = point.get("timestamp")
        if timestamp:
            parts.append(f"<time>{escape(str(timestamp))}</time>")
        parts.append("</trkpt>")
        segments.append("      " + "".join(parts))

    body = "\n".join(segments)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Healthpit" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>{name}</name>
    <time>{start}</time>
  </metadata>
  <trk>
    <name>{name}</name>
    <trkseg>
{body}
    </trkseg>
  </trk>
</gpx>
""".encode("utf-8")


def as_geojson(workout: dict[str, Any]) -> dict[str, Any]:
    """Serialise the track as a GeoJSON feature, which map cards can consume."""
    points = route_points(workout)
    return {
        "type": "Feature",
        "geometry": {
            "type": "LineString",
            # GeoJSON orders coordinates longitude first.
            "coordinates": [
                [round(float(point["longitude"]), 6), round(float(point["latitude"]), 6)]
                for point in points
            ],
        },
        "properties": {
            "workout_id": workout.get("workout_id"),
            "title": workout.get("title"),
            "sport": workout.get("sport"),
            "start": workout.get("start_time"),
            "end": workout.get("end_time"),
            "distance_km": workout.get("distance_km"),
            "duration_seconds": workout.get("duration_seconds"),
            "point_count": len(points),
        },
    }


def latest_with_route(workouts: list[dict[str, Any]]) -> dict[str, Any] | None:
    """The newest workout that actually has a track."""
    dated = [
        workout
        for workout in workouts
        if isinstance(workout, dict) and route_points(workout)
    ]
    if not dated:
        return None
    return max(dated, key=lambda item: str(item.get("start_time") or ""))
