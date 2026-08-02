# Healthpit Bridge app documentation

## Installation

Install the HACS integration first and restart Home Assistant so Supervisor can
recognize the `healthpit_bridge` discovery service.

Add `https://github.com/doctorspreter/healthpit` as a repository in
**Settings > Apps > App store**, then install **Healthpit Bridge**.

The app has no web interface and no sidebar entry. Everything is configured in
the app's **Configuration** tab; everything is displayed through native Home
Assistant entities created by the `healthpit_bridge` integration.

## Configuration groups

The Configuration tab renders one collapsible block per group, in this order:

| Group | Contains |
| --- | --- |
| Garmin Connect | sync switch, account, activity limit |
| Hevy | sync switch, API key, page limit, interval |
| Access and security | bridge username, API token, 2FA, session lifetime |
| Topology | node role, and the master address/credentials when running as slave |
| System | log level |

The **Network** card below them is rendered by Home Assistant itself and maps
the bridge API port.

Nothing outside these groups needs attention for a normal single-bridge setup.
Topology sits last on purpose: as a master there is nothing to fill in there.

## Master and slave

Every Healthpit node — this app, the standalone Docker bridge, or a second
Home Assistant — runs in one of two roles, selected with **Topology · Role of
this node**:

- **master** owns the data, stores it in SQLite, and accepts slave sessions.
  Apple Health, GymPit, Hevy and Garmin all feed into the master.
- **slave** does not accept sessions. It signs in to the node given in
  **Master address** using **Master API token**, plus a one-time OTP code when
  the master requires 2FA. The token is whatever the master issues; no length
  is imposed on it here.

An incomplete topology never stops the bridge. If the role is `slave` while the
address or the token is missing, the log says which one and the app keeps
running with the role it was given — it is not promoted back to master, because
two masters for one user is the one state that must not happen.

Switching the app to `slave` has a consequence worth planning for: it stops
accepting sessions and reports `slave` on `GET /health`, so the native
integration pointed at it will refuse to connect. Point the integration at the
master instead. Note also that a slave does not yet mirror the master's data;
it stands down rather than replicating.

There must be exactly one master per user. A master rejects a second master
with HTTP 409, and `GET /health` reports the configured role so the native
integration refuses to attach to a slave.

The master address accepts `192.168.178.20`, `host:8088` or a full URL; a
missing scheme becomes `http://` and a missing port becomes `:8088`.

## First start

The defaults are safe for a local first start:

- role: `master`
- username: `healthpit`
- API token: generated automatically
- 2FA: disabled
- Hevy/Garmin: disabled
- API port: `8088`

In automatic token mode the app generates a cryptographically random token on
first start and keeps it across restarts and backups. Choose **manual** to
provide a token with at least 32 characters. The active token is readable in
`/data/options.json` inside an app backup and can be replaced at any time from
the Configuration tab.

2FA supports three modes:

- **disabled**: no OTP is required during the initial session handshake;
- **automatic**: the app generates a standard TOTP secret;
- **manual**: enter an existing Base32 TOTP secret.

Changing the username, API token, or TOTP secret revokes issued sessions.

## Scanning the 2FA code

There is no web page to scan from. The master renders the `otpauth://`
enrolment code as a PNG on `GET /v1/auth/otp-qr.png`, and the integration
publishes it as the image entity `image.<user>_2fa_code`.

1. Set **Access and security · Two-factor authentication** to automatic or
   manual and restart the app.
2. Put the image entity on any dashboard, for example with a Picture Entity
   card, and scan it with Healthpit or a TOTP app.

While 2FA is disabled the bridge answers that endpoint with HTTP 404 and the
image entity stays empty — that is the expected state, not a fault.

## Client connection

Use these values in Healthpit/GymPit or the native integration:

| Setting | Value |
| --- | --- |
| Address | Home Assistant IP or hostname |
| Port | `8088` |
| Username | Access and security · Username |
| API token | Access and security · API token |
| OTP | Current six-digit code when 2FA is active |

The initial handshake exchanges these credentials for a revocable long-lived
slave session.

## Native Home Assistant entities

Add `https://github.com/doctorspreter/healthpit` to HACS as an Integration
repository and install **Healthpit Bridge**. Restart Home Assistant.

The app then appears on its own under **Settings > Devices & services** as a
discovered integration. Press **Configure**, confirm, and setup is done — no
token to copy and no OTP code to type.

That shortcut does not weaken anything. On start the master issues one
`home_assistant`-scoped slave session for itself and advertises only that
session token through Supervisor discovery. The API token and the TOTP secret
never leave the app. The session is listed like any other under active app
sessions, expires with the configured session lifetime, is revoked whenever the
username, API token or TOTP secret changes, and can be revoked on its own at
any time. It is reused across restarts while it stays valid.

A node running as `slave` does not advertise itself at all, so Home Assistant
never offers to attach to the wrong one.

If discovery is unavailable — the standalone Docker bridge, for instance — the
manual dialog still asks for host, port, username, API token and a current OTP
code, and exchanges them for the same kind of session.

The integration creates dynamic health sensors, workout/exercise sensors, the
2FA image entity, native workout services, and route `geo_location` entities.
App installation and integration installation are separate because an app
should not receive write access to the entire Home Assistant configuration
directory.

## Hevy and Garmin

Hevy requires an API key (the public API may require Hevy Pro). Configure the
key, page limit, and interval in the **Hevy** group.

Garmin Connect uses the configured email/password and synchronizes on a
six-hour background cycle. Credentials stay inside the app data/options and are
never returned by the public bridge API.

Both imports run inside the master and are master-owned services, not
independently connected peers.

## Network security

Port `8088` is plain HTTP inside the local network. For access outside the
local network, use an HTTPS reverse proxy or tunnel and expose only this port.

## Backup and migration

Home Assistant app backups include `/data`, containing:

```text
/data/db/healthpit_bridge.sqlite3
/data/generated_secrets.json
/data/options.json
```

To migrate from the standalone Docker version, stop both services and restore
`healthpit_bridge.sqlite3` into the app backup/data volume before starting the
app. Never run two masters for the same user simultaneously — set one of them
to `slave` instead.
