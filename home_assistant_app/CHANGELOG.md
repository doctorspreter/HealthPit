# Changelog

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
