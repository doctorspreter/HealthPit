# Healthpit Home Assistant Bridge

This headless Docker service receives health metrics from the iOS app and
exposes every received value as an individual Home Assistant sensor through the
native Healthpit Bridge integration. It has no web dashboard. Configuration and
control happen in the iPhone app; the container only provides its REST API.
The current Healthpit brand icon is available from `GET /brand/icon.png`; the
health response advertises this path as `brand_icon`.

## Data Flow

1. iPhone reads Apple Health locally through HealthKit.
2. iPhone sends selected values to this bridge over HTTPS.
3. Bridge stores the latest values in SQLite.
4. Home Assistant polls the bridge through the custom integration and shows
   each health value under the matching Fitness user device.
5. Optional: Bridge reads Hevy/Garmin workouts, stores them locally, and exposes
   them through the API to the iPhone app.

## Master and Slave Topology

The bridge is always the single master for its configured user. Healthpit on
iPhone, GymPit, and Home Assistant are slaves. Multiple slave devices can
connect to the same master, but a second master cannot connect.

Every session request includes `node_role`. The bridge accepts only `slave`,
returns `server_role: master`, and rejects a master-to-master request with HTTP
409. Existing sessions are migrated to `slave` when the updated container
starts. Client apps require the issued slave session token for operational
synchronization; the API token and optional OTP are used for the initial
session handshake.

Hevy and Garmin imports run inside the Docker master and are therefore
master-owned services, not independently connected peers.

Apple Health cannot be pulled directly by Docker or Home Assistant. The iPhone
must push the values after the user grants HealthKit permission.

## Start

```bash
docker compose up -d --build
```

Before the first start, copy `.env.example` to `.env` and replace all
required `CHANGE_ME` values. The iPhone app uses the configured
`BRIDGE_USERNAME` and `BRIDGE_API_TOKEN` to connect. Runtime changes are stored in
`./data/db/healthpit_bridge.sqlite3`.

Home Assistant setup:

1. Add `https://github.com/doctorspreter/healthpit` to HACS as a custom
   Integration repository and install **Healthpit Bridge**. Alternatively,
   copy `custom_components/healthpit_bridge` into your Home Assistant config.
2. Restart Home Assistant and add **Healthpit Bridge** in **Settings > Devices &
   Services**.
3. Enter the bridge address, port, bridge username, API token and the current
   6-digit OTP code if OTP is enabled. You can use `192.168.x.x`, `host:8088`
   or `http://host:8088`. If Home Assistant runs in a different Docker
   container, use the Docker host IP or put both containers into the same
   Docker network and use `healthpit-bridge`.
4. The integration creates one sensor entity for every metric received from
   the iPhone. Use those entities in regular Home Assistant dashboards and
   automations.

## Persistent Data

The local `data` folder is mounted into the container as `/data`. Keep this
folder when rebuilding or moving the bridge.

```text
data/
  db/       SQLite database with settings, tokens, latest values, and Hevy data
```

If you previously used the old Docker named volume, copy the existing database
from that volume into `data/db/healthpit_bridge.sqlite3` before removing the old
volume.

## Hevy

The Hevy import is optional. Configure its API key, enabled state, and sync
interval in `.env`. The bridge stores workouts, exercises, sets, weights, reps,
and volume locally in SQLite.

Bridge clients use these endpoints:

```text
POST /v1/auth/session
GET /v1/fitness/hevy
GET /v1/workouts/imports
DELETE /v1/workouts/imports/{workout_id}
POST /v1/workouts/imports/reconcile
```

When the iPhone app syncs Apple Health workouts, it also reconciles the current
Apple Health IDs. Workouts deleted from Apple Health or hidden/deleted in the
Healthpit workout list are removed from the bridge.

The same bridge username, token, and optional OTP protection are used. The Hevy API key stays on the
Docker server and is not stored on the iPhone. According to the
official Hevy API documentation, the public API is currently available only for
Hevy Pro accounts.

Create the required `.env` file and set your own credentials:

```bash
cp .env.example .env
```

For production, put the bridge behind HTTPS using a reverse proxy or a tunnel
of your choice.

## Security

The public bridge endpoint should always use HTTPS. Prefer a setup that exposes
only the bridge service rather than the whole server. Without an additional
authentication layer in front the endpoint is still public, so the app-level
checks matter:

- `BRIDGE_USERNAME` and `BRIDGE_API_TOKEN` are required for every data request.
- API clients send the username in `X-Healthpit-User`.
- `BRIDGE_OTP_SHARED_SECRET` is optional. If set, the iPhone app stores the long
  OTP secret and sends a fresh generated code with every request.
- App clients such as Gympit can create a revocable session with
  `POST /v1/auth/session` by sending username, API token and the current
  6-digit OTP code once. They explicitly connect as slaves and accept only the
  Docker master. The bridge stores only a hash of the generated session
  token. By default, new sessions are valid for 1825 days, roughly 5 years.
  Change `app_session_expires_days` in the Bridge Login settings if you want a
  shorter or longer limit. Import sessions are accepted only for their own workout synchronization
  (upload, delete, and reconcile). Home Assistant
  sessions are accepted for the bridge API so the integration can keep reading
  data and using its existing admin services without storing the OTP secret.
- Active app sessions can be reviewed and revoked in the iPhone app. Changing
  the session lifetime updates active session expiry dates. Changing username,
  API token, or OTP secret revokes existing app sessions automatically.
- Keep the `/health` endpoint harmless; it only returns whether the bridge is up.

Use a long random token and enable OTP for public internet exposure.

## Updating the Docker container

Rebuild and start the headless bridge after an update:

```bash
docker compose up -d --build
```

## Test Payload

```bash
curl -X POST http://localhost:8088/v1/health/batch \
  -H "X-Healthpit-User: peter" \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "X-Healthpit-Otp: 123456" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "iphone-stefan",
    "metrics": [
      {
        "id": "step_count",
        "category": "activity",
        "title": "Schritte",
        "value": 8421,
        "unit": "Schritte",
        "measured_at": "2026-06-20T12:00:00Z",
        "aggregation": "sum",
        "icon": "mdi:walk"
      }
    ]
  }'
```

Home Assistant will create an entity similar to:

```text
sensor.healthpit_peter_iphone_stefan_activity_step_count
```
