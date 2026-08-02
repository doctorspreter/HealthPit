# Healthpit Bridge - Home Assistant Integration

This custom integration polls the headless Healthpit Bridge and creates native
Home Assistant sensors for health metrics, sports, workouts, and strength
exercises.

## Features

- Dynamic metric sensors with unit, icon, category, aggregation,
  `device_class`, `state_class`, and measurement timestamp.
- Stable sport sensors for the latest workout, workout count, duration,
  distance, pace, speed, energy, heart rate, and strength totals when the
  source data contains those values.
- Stable exercise/machine sensors for the latest session, session count, sets,
  repetitions, last and best weight, volume, RPE, duration, and personal
  records when available.
- A native `geo_location` entity for every stored GPS point of every workout.
  These points can be displayed by Home Assistant's original map without a
  custom dashboard card.
- One Healthpit user device containing all metric sensors.
- Automatic creation of sensors for metrics that appear after setup.
- Native services for deleting imported workouts, starting Hevy or Garmin
  synchronization, and managing workout merge/separation rules.

The integration does not install a custom dashboard, sidebar panel, Lovelace
card, iframe, or MQTT entities.

The bundled Healthpit brand icon is displayed locally by Home Assistant 2026.3
or newer. After replacing the integration files, restart Home Assistant and
hard-refresh the browser if an older cached icon is still visible.

## Installation

1. Add `https://github.com/doctorspreter/healthpit` to HACS as a custom
   **Integration** repository and install **Healthpit Bridge**. Alternatively,
   copy this folder to `<config>/custom_components/healthpit_bridge/`.
2. Restart Home Assistant.
3. Open **Settings > Devices & Services** and select the discovered Healthpit
   Bridge, or choose **Add Integration > Healthpit Bridge**.
4. If the Home Assistant app is installed, host, port, and username are filled
   automatically through Supervisor discovery. Enter the API token and current
   six-digit OTP code when OTP is enabled.

Home Assistant exchanges the API credentials and one current OTP code for a
revocable slave session token. It accepts the connection only when the bridge
identifies itself as the master; master-to-master connections are
rejected. The integration then polls `GET /v1/health/latest`
and `GET /v1/workouts/imports` every five minutes by default. Workout routes
are requested without point sampling so every coordinate stored by the bridge
is exposed to Home Assistant.

Workout and exercise entity IDs remain stable: new sessions update the same
sport or machine sensors instead of creating permanent entities for every
historical workout.

Route point entity IDs remain stable for a workout and point number. Select the
`healthpit_bridge` geolocation source in a native map card, or add the generated
`geo_location` entities directly. Home Assistant displays the points as map
markers; its original map does not connect them with a line. A route with many
GPS samples consequently creates many entities and map markers.

Native map card example:

```yaml
type: map
geo_location_sources:
  - healthpit_bridge
cluster: true
```

Keep clustering enabled for large routes. Disabling it can make the browser and
Home Assistant frontend very slow when many GPS points are present.

## Services

- `healthpit_bridge.delete_workout`
- `healthpit_bridge.sync_hevy`
- `healthpit_bridge.sync_garmin`
- `healthpit_bridge.save_workout_link`
- `healthpit_bridge.delete_workout_link`

MQTT discovery is no longer part of the Healthpit architecture. Legacy MQTT
devices and old manually configured Healthpit dashboard resources can be
removed after migration.
