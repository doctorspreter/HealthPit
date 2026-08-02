# Healthpit Bridge

Healthpit Bridge stores health metrics and workouts for Healthpit on iPhone,
GymPit and Home Assistant, optionally imports Hevy and Garmin data, and
provides a native REST API on port `8088`.

The app is headless: no web interface, no sidebar entry.

The Home Assistant app adds:

- all configuration in **Settings > Apps > Healthpit Bridge > Configuration**,
  grouped by topology, access, Hevy, Garmin and system;
- a selectable node role, so the app runs as master or as slave of another
  Healthpit node;
- English and German option labels following the Home Assistant language;
- secure automatic or manual API-token setup;
- optional automatic or manual TOTP/2FA setup;
- a scannable `otpauth://` QR code published as a Home Assistant image entity;
- persistent SQLite data and credentials included in app backups.

See the **Documentation** tab after installation for setup instructions.

Repository URL: `https://github.com/doctorspreter/healthpit`
