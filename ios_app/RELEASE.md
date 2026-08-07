# HealthPit 1.0.0

Release date: 2026-07-26

## Packages

- **Xcode**: iOS app for iOS 26.5 or later. Open the project in Xcode, verify
  the signing team, test on a physical iPhone, and then distribute it through
  Product > Archive.
- **Home Assistant Docker**: Standalone bridge for Docker Compose. Copy
  `.env.example` to `.env`, replace every required `CHANGE_ME` value, and run
  `docker compose up -d --build`.
- **Home Assistant integration**: Copy
  `custom_components/healthpit_bridge` to
  `<config>/custom_components/healthpit_bridge` and restart Home Assistant.

## Security

The release does not include SQLite databases, backups, API keys, OTP secrets,
or user-specific Xcode data.

## Versions

- iOS app: 1.0 (Build 1)
- Bridge API: 1.1.0
- Home Assistant integration: 1.3.0
