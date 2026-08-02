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
| System | log level |

The **Network** card below them is rendered by Home Assistant itself and maps
the bridge API port.

The bridge serves exactly one user today. Support for several users on one
bridge, which is what challenges between people need, is the next step.

## First start

The defaults are safe for a local first start:

- username: `healthpit`
- API token: generated automatically
- 2FA: disabled
- Hevy/Garmin: disabled
- API port: `8088`

In automatic token mode the app generates a cryptographically random token on
first start, writes it back into **Access and security · API token** and keeps
it across restarts and backups. Leave the field empty and the token appears
there after the first start; Home Assistant masks it like any password field
and reveals it on request.

To roll the token, switch on **Generate a new token** and save. The next start
creates a fresh random token, writes it into the field and turns the switch
back off by itself. Every existing session is revoked in the process, so the
iPhone, GymPit and the integration have to sign in again.

Choose **manual** to provide a token of at least 8 characters. A manually
entered token is never overwritten.

An automatically generated TOTP secret is written back the same way, so it can
be typed into an authenticator that cannot scan the QR code.

2FA supports three modes:

- **disabled**: no OTP is required during the initial session handshake;
- **automatic**: the app generates a standard TOTP secret;
- **manual**: enter an existing Base32 TOTP secret.

Changing the username, API token, or TOTP secret revokes issued sessions.

## Scanning the 2FA code

There is no web page to scan from. The bridge renders the `otpauth://`
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
client session.

## Native Home Assistant entities

Add `https://github.com/doctorspreter/healthpit` to HACS as an Integration
repository and install **Healthpit Bridge**. Restart Home Assistant.

The app then appears on its own under **Settings > Devices & services** as a
discovered integration. Press **Configure**, confirm, and setup is done — no
token to copy and no OTP code to type.

That shortcut does not weaken anything. On start the bridge issues one
`home_assistant`-scoped client session for itself and advertises only that
session token through Supervisor discovery. The API token and the TOTP secret
never leave the app. The session is listed like any other under active app
sessions, expires with the configured session lifetime, is revoked whenever the
username, API token or TOTP secret changes, and can be revoked on its own at
any time. It is reused across restarts while it stays valid.

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

Both imports run inside the bridge and are bridge-owned services, not
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
app. Never run two bridges for the same user simultaneously; they would
overwrite each other's data.
