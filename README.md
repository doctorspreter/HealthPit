# Healthpit

Healthpit is an open-source, local-first health data platform for iPhone,
Home Assistant, Docker, GymPit, Hevy, and Garmin.

This single repository intentionally supports two independent Home Assistant
installation methods:

- **HACS integration:** installs the native entities from
  `custom_components/healthpit_bridge`.
- **Home Assistant app repository:** installs the Healthpit Bridge from
  `home_assistant_app` and manages its settings through
  **Settings > Apps > Healthpit Bridge**.

The app and integration communicate through the versioned Healthpit Bridge
API. The integration source exists only once; the app does not copy or write
files into Home Assistant Core.

## Repository layout

| Path | Purpose | Installation |
| --- | --- | --- |
| `custom_components/healthpit_bridge` | Native Home Assistant integration | HACS |
| `home_assistant_app` | Home Assistant OS app | Home Assistant app repository |
| `home_assistant_docker` | Standalone Docker bridge | Docker Compose |
| `ios_app` | Healthpit iPhone app | Xcode |

## Install the Home Assistant integration with HACS

1. Open **HACS > Integrations**.
2. Open the menu and choose **Custom repositories**.
3. Add `https://github.com/doctorspreter/healthpit` as category
   **Integration**.
4. Install **Healthpit Bridge** and restart Home Assistant.

## Install the Home Assistant app

1. Open **Settings > Apps > App store**.
2. Open the repository menu and add
   `https://github.com/doctorspreter/healthpit`.
3. Install and start **Healthpit Bridge**.
4. Configure everything in the app's **Configuration** tab. The app is headless:
   it has no web interface and adds no sidebar entry.
5. Optionally enable 2FA. The enrolment code is published by the integration as
   the image entity `image.<user>_2fa_code`, scannable from any dashboard card.

When the HACS integration is already installed, the app advertises itself
through Home Assistant Supervisor discovery. Home Assistant then pre-fills the
internal hostname, port, and username. For security, the API token and current
2FA code are still entered once during integration setup and are exchanged for
a revocable session token.

The app configuration is available in English and German and follows the Home
Assistant language.

## Master and slave

Each Healthpit node — the app, the Docker bridge, or a second Home Assistant —
runs as either `master` or `slave`, selected in its own configuration. The
master owns the data and accepts slave sessions; a slave signs in to the
configured master and accepts no sessions of its own. There must be exactly one
master per user, and a master rejects a second master with HTTP 409.

## Security

- Generated API tokens use 384 bits of randomness.
- Generated TOTP secrets use 160 bits of randomness.
- Credentials and the SQLite database remain in the app's `/data` volume and
  are included in Home Assistant backups.
- Changing the username, API token, or TOTP secret revokes existing sessions.
- There is no management UI to expose; settings are written only through the
  Home Assistant Supervisor.
- Port `8088` is plain HTTP for the local network. Use HTTPS through a reverse
  proxy or tunnel for remote access.

Do not commit `.env` files, databases, backups, API tokens, OTP secrets, Garmin
credentials, or Xcode user data. See [SECURITY.md](SECURITY.md) for reporting
security issues.

## Development

Build the Home Assistant app locally:

```bash
docker build -t healthpit-ha-app ./home_assistant_app
```

Start the standalone bridge:

```bash
cd home_assistant_docker
cp .env.example .env
docker compose up -d --build
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
