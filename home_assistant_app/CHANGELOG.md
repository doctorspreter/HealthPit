# Changelog

## 1.3.3

- Fixed the app restarting forever after switching the role to slave. An
  incomplete topology raised and killed the bootstrap; it now logs which field
  is missing and keeps running with the configured role. It is never promoted
  back to master, because two masters for one user must not happen.
- Dropped the 32-character minimum on the master's API token. That token is
  issued by the remote master, so its length is not ours to police.
- A rejected setting prints one readable line instead of repeating the same
  traceback on every restart.
- The startup line now reports the active role.

## 1.3.2

- Unified the default bridge username to `healthpit` across the app, the
  Docker bridge, the integration and the iPhone app. The integration and the
  iPhone app previously defaulted to `peter`, so a fresh install disagreed with
  the app about who was signing in.

## 1.3.1

- Fixed discovery never reaching Home Assistant. Registration first called
  GET /discovery to clear stale messages, but that endpoint is reserved for
  Home Assistant itself and answers an app with 401, so the POST that follows
  never ran. Supervisor already replaces the previous message for the same app
  and service, so the read and delete are gone.
- A failure while issuing the Home Assistant session no longer stops the app
  from starting; it falls back to manual pairing and says so in the log.
- The log line now states whether the session token was attached.

## 1.3.0

- Home Assistant now sets the integration up from discovery with a single
  confirmation. The master issues one scoped, revocable slave session for
  Home Assistant and advertises only that token; the API token and the TOTP
  secret never leave the app.
- The session is reused across restarts, revoked together with the other app
  sessions when credentials change, and revocable on its own.
- A node running as slave no longer advertises itself through discovery.
- Clients other than Home Assistant, including Healthpit on iPhone and GymPit,
  are unaffected and keep using username, API token and OTP.

## 1.2.0

- Grouped the configuration into collapsible sections — Garmin, Hevy, Access,
  Topology, System — instead of one flat list with prefixed labels.
- Moved Garmin to the top and Topology to the bottom, since a master needs
  nothing from the topology group.
- Rewrote the option help texts so it is clear which fields apply to a master
  and which only to a slave.
- Options written by 1.1.0 and earlier are still read, so an existing
  installation keeps its settings.

## 1.1.0

- Removed the Ingress web interface and the Healthpit sidebar entry. The app is
  now headless; all settings live in the app's Configuration tab.
- Grouped the configuration options into numbered sections so Topology,
  Access, Hevy, Garmin and System stay clearly separated.
- Added a selectable node role. Every node can run as `master` or as `slave` of
  another Healthpit node, so a second Docker bridge or app can be attached
  without two masters fighting over the same user.
- `GET /health` and `GET /v1/bridge/status` now report the configured role
  instead of always claiming `master`, and a slave refuses session handshakes.
- Added `GET /v1/auth/otp-qr.png`, rendering the 2FA enrolment code as a PNG.
  The integration publishes it as an image entity for any dashboard card.

## 1.0.2

- Fixed the app failing to start with `ModuleNotFoundError: No module named
  'app'` by running the bootstrap as a module.

## 1.0.0

- Initial Home Assistant OS app release.
- Added Home Assistant Ingress settings UI.
- Added English and German configuration/UI localization with automatic
  Home Assistant/browser language detection.
- Added persistent automatic and manual API-token modes.
- Added disabled, automatic and manual TOTP/2FA modes.
- Added scannable `otpauth://` QR code and OTP verification.
- Added Supervisor-backed configuration for Hevy and Garmin.
- Added secure Supervisor discovery for the separately installed HACS
  integration without exposing API or TOTP secrets.
- Kept administration isolated from the public bridge API port.
