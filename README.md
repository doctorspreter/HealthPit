# HealthPit

HealthPit is an open-source, local-first health data platform for iPhone and
Home Assistant.

The iPhone app reads Apple Health locally and pushes what you select straight
into Home Assistant. A custom integration stores it and creates native entities.
There is no bridge, no container and no add-on in between.

```text
iPhone (HealthKit)  ──push──▶  Home Assistant  ──▶  sensors, map, statistics
                    long-lived
                    access token
```

## Several people, separate entities

One config entry covers the whole household. Everyone creates their own
long-lived access token in their own Home Assistant profile, and Home Assistant
tells the tokens apart: each person gets their own device with their own
entities, so `sensor.peter_schritte` and `sensor.anna_schritte` never collide.
The app never claims an identity — the token decides.

## Repository layout

| Path | Purpose | Installation |
| --- | --- | --- |
| `custom_components/healthpit` | Home Assistant integration | HACS |
| `ios_app` | HealthPit iPhone app | Xcode |
| `tests` | Tests for the payload and merge logic | pytest |

## Setup

1. Add `https://github.com/doctorspreter/HealthPit` to HACS as a custom
   **Integration** repository, install **HealthPit**, and restart Home
   Assistant. Alternatively copy `custom_components/healthpit` into your
   configuration folder.
2. **Settings > Devices & Services > Add Integration > HealthPit**, then
   confirm. There is nothing to enter.
3. In your Home Assistant profile, scroll to **Long-lived access tokens** and
   create one.
4. In the app under **Settings > Verbindung**, enter your Home Assistant
   address and paste the token.

The local address is preferred and the external one is only used when the local
one does not answer, so the app works at home and away without switching
anything. The external address must be HTTPS.

Verify a setup from the command line:

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" https://ha.example.com/api/healthpit/v1/status
```

## Routes

A track is one thing, so it is one entity. Each user gets:

- **an image entity** that draws the newest track as a line, generated as SVG —
  no image library, no map tiles, no request leaving the machine. Drop it on a
  dashboard with a picture-entity card.
- **a sensor** whose state is the distance of that track, with the workout it
  belongs to, its bounding box and download links in the attributes.

Any stored track can be fetched whole:

```text
GET /api/healthpit/v1/workouts/{workout_id}/route.gpx
GET /api/healthpit/v1/workouts/{workout_id}/route.geojson
GET /api/healthpit/v1/workouts/{workout_id}/route.svg
```

GPX goes into any other tool, GeoJSON into a map card. Both need the same
long-lived access token as everything else.

Incoming tracks are thinned to 500 points, which keeps the shape and keeps the
store quick to load; the original sample count stays visible as
`route_points_total`.

## History

Home Assistant cannot backdate its state history — there is no API for that.
Its long-term statistics *can* be backdated, and for sensors carrying a
`state_class` that is what long-range graphs are drawn from. The
`healthpit.import_history` service walks the stored workouts and writes the
cumulative sport values (count, total duration, total distance) into the
statistics, so those graphs cover the past instead of starting on setup day.
Run it again whenever you have imported older workouts; existing rows are
overwritten rather than duplicated.

Metric history is a different matter: the app sends only the current value per
metric, so past step counts or weights cannot be reconstructed.

## Security

- Home Assistant's own authentication guards the push API. Revoke a token in
  the profile and that phone is locked out immediately.
- The stored data lives in Home Assistant's own storage, marked private.
- Use HTTPS for the external address. Behind Cloudflare or another reverse
  proxy, remember that TLS terminates there and set `use_x_forwarded_for` plus
  `trusted_proxies` in your `http:` configuration.

Do not commit `.env` files, databases, backups, tokens or Xcode user data. See
[SECURITY.md](SECURITY.md) for reporting security issues.

## Development

```bash
python -m pytest tests -q
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
