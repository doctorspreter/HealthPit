# Mobile App Architecture

Status: 2026-07-18

This file is the authoritative reference for the iPhone app. Every change to
navigation, data flow, dashboard tiles, detail views, synchronization behavior,
or the Home Assistant representation must update this document in the same
change.

## Core principles

The app must be usable immediately after launch:

- Show local SQLite/cache data first.
- Fetch new or changed data through pull-to-refresh, the toolbar sync action,
  background synchronization, or an explicit action in Settings.
- Perform expensive processing on the bridge/server, not while opening a view
  on the iPhone.
- Send new Health and workout deltas to the bridge and receive processed
  packages in return.
- Run a complete Apple Health workout query only as an explicit Settings
  action.
- Do not render empty placeholders for missing optional data. For example, omit
  the map and explanatory replacement text when a workout has no route.

## Entry point

File: `Healthpit/ContentView.swift`

1. `ContentView` reads `@AppStorage("hasConnectedHealth")`.
2. If Health access has not been confirmed, it presents `OnboardingView`.
3. Successful onboarding sets `hasConnectedHealth = true`.
4. The app subsequently opens directly in `DashboardView`.

## Main architecture

The SwiftUI app is divided into these layers:

- `Healthpit/Views`: complete UI and navigation.
- `Healthpit/Models`: domain models for categories, metrics, date ranges,
  workouts, sleep, Hevy, and local workouts.
- `Healthpit/HealthKit`: HealthKit access and types.
- `Healthpit/Bridge`: communication with the Docker/bridge backend,
  authentication, local/external URL selection, and background sync.
- `Healthpit/Support`: local SQLite/cache stores, formatting, importers, record
  calculation, and preload logic.
- `custom_components/healthpit_bridge`: native Home
  Assistant metric sensors and bridge services. No custom dashboard is shipped
  in the current architecture.

The central cache is implemented in
`Healthpit/Support/HealthpitDatabase.swift`. Its SQLite database is stored at
`Application Support/Database/healthpit.sqlite3`, using a `cache_entries`
table with generic JSON payloads keyed by cache key.

## Data flow

### Normal launch

1. The app starts through `ContentView`.
2. `DashboardView` opens.
3. Dashboard tiles load cached values first.
4. Merely opening the app never triggers a full Apple Health query.
5. Missing data is represented by `–` or a compact empty state.

### Manual refresh

Refresh can be triggered by:

- Pull-to-refresh on the dashboard.
- The sync button in the dashboard toolbar.
- Pull-to-refresh in Workouts, Activity, and Records.
- The **Sync now** action in Settings.

Dashboard pull-to-refresh and the toolbar action intentionally differ:

- Pull-to-refresh performs a local Apple Health refresh. It reads current
  HealthKit metrics, sleep, and Apple Health workouts into local caches without
  contacting the bridge.
- The toolbar button performs explicit server synchronization through
  `BridgeSyncService.syncNow()`, including status and error feedback.
- Pull-to-refresh in detail views is context-specific: Activity loads live and
  trend data from HealthKit, Workouts refreshes the current range, and Records
  recalculates local records.
- Both paths must preserve visible cached data and must not block the UI for an
  extended period.

Server synchronization from the toolbar, Settings, or background sync:

1. Run `BridgeSyncService.syncNow()`.
2. Collect current HealthKit metrics.
3. Send the metric batch to `POST /v1/health/batch`.
4. Send Apple Health workout deltas to `POST /v1/workouts/imports`.
5. Send local/imported workouts to `POST /v1/workouts/imports`.
6. Let the bridge fetch Garmin and Hevy data server-side.
7. Download changed Apple Health workouts from `GET /v1/workouts/imports`.
8. Download the already merged manual, imported, Garmin, and Hevy workout list
   from the same endpoint.
9. Update local caches.
10. Recalculate records from local caches.

### Full workout resync

Location: **Settings > Reload all Apple Health workouts**

1. `BridgeSyncService.fullResyncAppleHealthWorkouts()` loads every Apple Health
   workout.
2. Upload workouts to the bridge in packages.
3. Store the complete local set in `HealthWorkoutCacheStore`.
4. Reset the upload cutoff and package cursor.
5. Recalculate records.

This action is deliberately excluded from normal app startup.

## Bridge connection

Files:

- `Healthpit/Bridge/BridgeSettings.swift`
- `Healthpit/Bridge/BridgeSyncService.swift`
- `Healthpit/Views/Settings/BridgeSettingsView.swift`

Settings include the external HTTPS bridge URL, an optional local connection,
local host and port (`8088` by default), username, device name, sync enabled
state and interval, and API token/OTP secret in Keychain. The OTP secret can be
entered with the QR scanner.

URL selection:

1. When local mode is enabled and a local host exists, build a local URL.
2. Normalize the local connection to `http://`, even if `https://` was entered
   accidentally.
3. Probe `GET /health` with a short timeout.
4. Use the local bridge only if it is healthy and returns
   `node_role = master`.
5. Otherwise fall back to the external `https://` URL.

The app does not inspect the Wi-Fi network name; local selection is based only
on bridge reachability.

The Docker bridge is the single master for each configured user. Healthpit,
GymPit, and Home Assistant always request a `slave` session. The session
handshake succeeds only when the bridge responds with `server_role = master`
and the assigned client role is `slave`. A client requesting `master` is
rejected, which prevents master-to-master connections. Operational app sync
requires the issued slave session token; the API token is used only to create
that session.

## Main navigation

File: `Healthpit/Views/Dashboard/DashboardView.swift`

- Root container: `NavigationStack`
- Title: `Fitness`
- Trailing toolbar: sync through `BridgeSyncService.syncNow()` and a gear that
  opens `BridgeSettingsView`
- Pull-to-refresh:
  `HealthpitPreloadService.refreshLocalAppleHealthCaches()`

Dashboard destinations:

| Tile | Destination |
| --- | --- |
| Activity | `CategoryDetailView(category: .activity)` |
| Workouts | `WorkoutListView()` |
| Sleep | `SleepDetailView()` |
| Heart | `CategoryDetailView(category: .heart)` |
| Records | `RecordsView()` |
| Body | `CategoryDetailView(category: .body)` |
| Nutrition | `CategoryDetailView(category: .nutrition)` |
| Vitals | `CategoryDetailView(category: .vitals)` |

## Dashboard tiles

Files:

- `Healthpit/Models/DashboardItem.swift`
- `Healthpit/Views/Dashboard/CategoryCard.swift`
- `Healthpit/Views/Settings/DashboardOrderSettingsSection.swift`

The required default order is Activity, Workouts, Sleep, Heart, Records, Body,
Nutrition, and Vitals. Home Assistant uses the same order.

Sizes map as follows:

- `1x1` -> `DashboardWidgetSize.small`
- `2x2` -> `DashboardWidgetSize.medium`
- `4x1` -> `DashboardWidgetSize.wide`

The **Settings > Home** section shows one row per tile with icon, title, up and
down arrows, and a segmented size selector. Arrows move the tile by exactly one
position and are disabled at the corresponding list boundary. Sizes are saved
per tile. **Restore defaults** restores the required order and `2x2` sizes.
Home Assistant must implement the same behavior and terminology, adapted to
landscape layout where necessary.

The following are not allowed: `1x2` tiles, vertically compressed text
columns, white tiles with white text, or tiles without working navigation when
a destination exists.

- Small tiles show only the most important value.
- Medium tiles show the most important one or two values.
- Wide tiles show up to four values or one small chart.
- Stale individual values display their measurement date in small text.
- German UI labels retain their umlauts and are never transliterated to
  `ae`, `oe`, or `ue`.

Workout tiles prioritize the latest workout, date/time, duration, distance, or
energy—not the total workout count. Wide tiles additionally show a seven-day
count, daily average, and compact daily bars. Sleep tiles prioritize last
night, sleep duration, time in bed, efficiency, and available stages. Record
tiles show current bests and the newest record.

Category headline order:

- Activity: steps, walking/running distance, flights, active calories.
- Heart: resting heart rate, heart rate, HRV, VO₂ max.
- Body: weight, BMI, body fat, lean mass.
- Nutrition: energy, water, carbohydrates, protein.
- Vitals: SpO₂, respiratory rate, body temperature, blood glucose.

Home Assistant must use the same headline order, `4x1` supplementary blocks,
and information density. A tile must not be empty when its bridge payload
contains data.

## Onboarding

File: `Healthpit/Views/Onboarding/OnboardingView.swift`

Onboarding requests Apple Health read access. Completion sets
`hasConnectedHealth = true` and navigates through `ContentView` to
`DashboardView` on future launches.

## Settings

File: `Healthpit/Views/Settings/BridgeSettingsView.swift`

The dashboard gear opens these sections:

- **Bridge**: external URL, local mode, local host/port, username, device name,
  sync enabled state, interval, and last sync.
- **Dashboard**: start-tile order and size.
- **App**: version from `CFBundleShortVersionString` and `CFBundleVersion`.
- **Security**: API token, OTP secret, and OTP QR scanner.
- Sync actions: **Sync now** and **Reload all Apple Health workouts**.

The QR action presents `OTPScannerView`; **Done** closes Settings.

## Activity

File: `Healthpit/Views/Activity/ActivityOverviewView.swift`

The Activity tile opens a view titled **Activity** with today's date, relevant
activity and sleep trends, today's important activity values, and a link to
all activity metrics. Tapping a value opens `MetricDetailView`; the all-values
link opens `CategoryMetricListView(category: .activity)`.

Load cached values from `DashboardMetricCacheStore` first. Pull-to-refresh
loads live HealthKit values and saves them. Trends compare the last 14 complete
days/nights with the preceding 90 days, excluding today. Show a trend only when
both its relative and absolute change are meaningful. Activity trends include
steps, distance, active calories, exercise minutes, flights, and relevant
pace/performance values. Sleep trends include duration, deep sleep, REM, awake
time, and efficiency when they differ materially from the three-month norm.
Today's list remains a daily view; its gray reference is the three-month norm,
not a seven-day average.

## Categories and metric details

Relevant files:

- `Healthpit/Models/HealthCategory.swift`
- `Healthpit/Models/HealthMetric.swift`
- `Healthpit/Views/Detail/CategoryDetailView.swift`
- `Healthpit/Views/Detail/MetricDetailView.swift`

Categories are Activity, Workouts, Heart, Sleep, Body, Nutrition, and Vitals.
Activity, Workouts, Sleep, and Records have dedicated main views. Heart, Body,
Nutrition, and Vitals use the generic metric list. Each row shows the icon,
localized German name, latest value, and unit. Body values add a color
classification; stale values show a small date. Tapping opens
`MetricDetailView`.

Metric detail contains the metric title; day/week/month/year selection; compact
previous/next and date controls; exactly one history chart; a statistical
summary; and a collapsed timestamp/value table.

- Use bars for cumulative values.
- Statistics for cumulative values such as steps, active calories, exercise
  minutes, distance, and water use `average/day` over visible elapsed days.
  Future days never dilute an in-progress range.
- Use a line, area, and points for average/instantaneous values.
- Draw the average as a dashed line.
- Body metrics include a compact green-to-yellow-to-red threshold legend.
- Never place a second trend, distribution, or cumulative chart directly below
  the first one.
- Collapse individual values by default whenever a history chart exists.

## Workouts

Files:

- `Healthpit/Views/Workouts/WorkoutListView.swift`
- `Healthpit/Views/Workouts/WorkoutRangeOverview.swift`
- `Healthpit/Views/Workouts/WorkoutDetailView.swift`
- `Healthpit/Views/Workouts/WorkoutRouteMapView.swift`
- `Healthpit/Views/Workouts/ManualWorkoutView.swift`

The Workouts tile opens a day/week/month/year selector,
`WorkoutRangeOverview`, and the merged Apple Health, Garmin, Hevy, and
local/manual/imported workout list. Pull-to-refresh rereads only the selected
range from Apple Health into `HealthWorkoutCacheStore`; it does not contact the
bridge or Hevy.

The toolbar offers GPX/TCX import, server refresh, manual training, and the
workout link manager. Tapping a row opens `UnifiedWorkoutDetailView`.
Swipe-to-delete removes local workouts locally and from the bridge, while Apple
Health and Hevy workouts are hidden only in the app.

Merging is authoritative on the bridge. The iPhone app and Home Assistant use
the same completed list from `GET /v1/workouts/imports`.

- Match Apple Health, Garmin, Hevy, and local workouts by nearby start times.
- Merge Apple Health and local/imported workouts even without Hevy when start,
  duration, and distance are sufficiently close.
- Use Apple Health `HKMetadataKeyExternalUUID` for exact linkage to a GymPit
  import when available; time matching is only a fallback.
- Keep GymPit-created Apple Health workouts visible in the local HealthKit
  cache, but do not upload them again to the bridge.
- Conservatively group remaining local cross-source duplicates when start,
  duration, and distance describe the same training.
- Strength workouts may merge on the same day.
- Store manual `merge` and `separate` rules on the bridge.
- Link keys use `source:id`, for example `apple_health:UUID`, `hevy:123`,
  `garmin:garmin-123`, `gpx:...`, or `manual:...`.
- Link changes modify the bridge API and do not trigger independent local
  calculations in either client.
- The bridge management page shows the merged list, duplicate candidates,
  rules, raw imported workouts, and Hevy workouts. Merge/separate controls use
  real source-key dropdowns, with free text reserved for API fallback.
- Forced merges must retain all `source_ids`.
- Semantically deduplicate imported workouts from the same non-Apple source by
  source, sport, title, start, and duration/end.

## Workout detail

Workout detail can be a local/Apple Health view, a Hevy view with exercises,
sets, volume, and integrated Health values, or a combined cross-source view.

The Health workout detail shows sport, icon, date/time, a map only with at least
two route points, metric grid, optional weather, optional splits/history, and
an optional heart-rate chart. Reloading or pulling down must pick up a route
that became available in Apple Health after the initial import.

Show all real sample series in addition to min/average/max: heart rate, route
pace/speed, elevation, and other derivable route values. Never render a default
pace curve without valid pace/speed data. Summaries do not replace charts.
Render measurements once as time-series charts and kilometer/split data as a
table, not a duplicate chart. Sources are always the final block.

Apple Health no longer has a separate sub-button. Its non-duplicate values are
integrated directly. Values already supplied by Hevy, imports, or the base
workout are not repeated; distinct values such as steps, flights, swim strokes,
or fastest kilometer remain visible.

Workouts may include injury location, pain type, and severity, for example
left knee, slight pulling pain, 3/10. Sync these through local/imported workout
and bridge payloads. The injury section is near the bottom, before sources.

## Sport overviews

Each sport should eventually have an overview derived from its workouts,
including workout count, latest session, total time, meaningful total distance,
available best performance/record, and a selected-range history. The workout
list already carries sport, date, duration, distance/energy, and merged sources.
Future implementation must document the overview as a dedicated destination or
filter area.

## Sleep

File: `Healthpit/Views/Sleep/SleepDetailView.swift`

Sleep uses day/week/month/year and compact previous/next plus date controls.
The day view is tied to the selected day/night rather than always showing the
latest night. It presents date, sleep and bed duration, efficiency, awake time,
stages, a hypnogram, and per-stage duration. Longer ranges present average
sleep, night count, stage bars, average cards, per-night stacked stages, and
averages for sleep, deep sleep, REM, and efficiency.

## Records

File: `Healthpit/Views/Dashboard/RecordsView.swift`

Records are always all-time; there is no date-range control. Sport selection
filters presentation without changing the all-time data. **All** sorts newest
first. The featured record is the newest visible record, and highlights rotate
with the newest visible records rather than permanently favoring historical
priorities. Every record shows its workout date in headers, highlights, rows,
Home Assistant, and Docker management. Opening a record also leaves the date
visible in the workout detail. **Show more** appears when needed.

Load from `WorkoutRecordCacheStore` and refresh with
`WorkoutRecordRefreshService.refreshFromLocalCaches()`. A row or highlight
opens the related `UnifiedWorkoutDetailView`; if its workout is no longer
cached, keep the record visible without navigation.

## Body, Heart, Nutrition, and Vitals

These tiles use `CategoryMetricListView` and open `MetricDetailView` on tap.

- Body: weight, BMI, body fat, lean mass, height, and waist circumference, with
  color classification and dates for stale values.
- Heart: heart rate, resting heart rate, walking heart-rate average, recovery
  heart rate, HRV, VO₂ max, systolic/diastolic blood pressure, perfusion index,
  and AFib history.
- Nutrition: energy, water, carbohydrates, protein, fat, sugar, fiber, caffeine,
  vitamins, and minerals.
- Vitals: respiratory rate, SpO₂, body temperature, basal temperature, and
  blood glucose.

## Local and imported workouts

Sources include manual entry, GPX, TCX, Garmin, and bridge downloads.

- Store them in `LocalWorkoutStore` and upload through
  `BridgeSyncService.uploadLocalWorkouts()`.
- Upload only locally owned `manual`, `gpx`, and `tcx` records. Never mirror
  server-owned sources such as `garmin` back to the bridge.
- Propagate local/imported deletions to the bridge.
- Preserve weather, injury, route, and heart-rate data when present.
- Deduplicate manual/imported workouts by source, normalized sport, normalized
  title, start minute, and end minute—not UUID alone.
- Use the HealthKit UUID as the Apple Health technical ID and
  `HKMetadataKeyExternalUUID`, when available, for exact cross-source linkage.
- When two records share a semantic key, keep the more complete record based on
  duration, distance, route, heart rate, notes, weather, and injury. If quality
  is equal, keep the most recently received record.
- Prevent sync loops on the bridge: import upserts remove older semantic
  duplicates and import GET responses are deduplicated.
- A manually entered workout exported to Apple Health and returned through
  sync must appear once as a multi-source merged workout.

## Hevy

Files:

- `Healthpit/Bridge/BridgeFitnessService.swift`
- `Healthpit/Support/HevyFitnessCacheStore.swift`
- `Healthpit/Views/Workouts/WorkoutListView.swift`
- `Healthpit/Views/Workouts/WorkoutDetailView.swift`

Do not recompute Hevy data expensively on normal launch. Refresh through the
bridge fitness service and cache. Merge Hevy workouts with matching Apple
Health/local workouts. Detail views show exercises, sets, volume, and related
records.

## Garmin

Files:

- `home_assistant_docker/app/garmin.py`
- `home_assistant_docker/app/store.py`
- `home_assistant_docker/app/main.py`

The bridge—not the iPhone—syncs Garmin Connect. It stores activities as
imported source `garmin` with IDs `garmin-<activityId>` and preserves available
route points, duration, distance, calories, average heart rate, and maximum
heart rate. Bridge settings contain email, password, enabled state, and maximum
activity count. Periodic background sync must never block the iPhone.

The iPhone creates stable local UUIDs from Garmin IDs and never uploads Garmin
records back to the bridge. The server merges duplicates across Garmin, Apple
Health, Hevy, and local sources. A manual bridge fetch can import older Garmin
data, which then appears through the shared workout API in both clients.

## Background synchronization

Files:

- `Healthpit/Bridge/BackgroundSyncScheduler.swift`
- `Healthpit/Bridge/BridgeSettings.swift`

Reschedule background sync after every successful run using the configured
interval. It must not block app launch. When sync is disabled, no automatic
expensive refresh may run.

## Home Assistant representation

The current Home Assistant integration is deliberately sensor-only. It does
not register a sidebar panel, custom card, iframe, or aggregate dashboard
sensor. Dashboard presentation remains a future feature and must be designed
separately when it is reintroduced.

Current rules:

- Create one native Home Assistant sensor for every metric returned by
  `GET /v1/health/latest`.
- Poll merged workouts from `GET /v1/workouts/imports` without route points.
- Create stable per-sport sensors for the latest workout, count, duration,
  distance, pace, speed, energy, heart rate, and available strength totals.
- Create stable per-exercise/machine sensors for the latest session, sessions,
  sets, repetitions, last/best weight, volume, RPE, duration, and personal
  records when supplied by GymPit or Hevy.
- Aggregate historical workouts into stable entities instead of creating a new
  permanent Home Assistant entity for each completed session.
- Include category, metric ID, device ID, aggregation, and measurement time as
  sensor attributes.
- Apply `device_class`, `state_class`, unit, and icon when supplied by the
  bridge.
- Attach all metric sensors to the configured Healthpit user device.
- Create missing sensors automatically when a later sync introduces a metric.
- Do not poll bridge management state, routes, separate Hevy summaries, or
  workout links for unused UI models.
- Keep only the native services that remain useful without a dashboard:
  deleting an imported workout, starting Hevy/Garmin sync, and saving or
  deleting workout-link rules.
- MQTT discovery is not part of the target architecture.
- The Docker bridge exposes only `/health` and `/v1/*` API behavior. It does
  not serve an HTML dashboard.

## Performance rules

- No full HealthKit scan on startup.
- No full record rebuild when opening Records.
- No full workout scan when opening Workouts.
- Lists and details load local caches first.
- Refresh may update data but must not block the UI indefinitely.
- Bridge packages should be sufficiently processed for small local updates.
- Full recalculation happens only through explicit Settings or maintenance
  actions.

## Change log

### 2026-06-28

- Established this file as the authoritative architecture and navigation
  reference.
- Documented the current app, sync, and Home Assistant structure.
- Required a mobile-equivalent Home Assistant app with only documented
  landscape and daily-step differences and active-theme styling.
- Integrated distinct Apple Health values directly into workout detail.
- Standardized dashboard tile sizes, ordering, and settings behavior.
- Required late Apple Health routes and all real sample series to refresh into
  workout detail.
- Added Garmin as a bridge-owned source merged server-side and distributed
  through the shared workout list.
- Documented manual `merge` and `separate` rules and stable iPhone Garmin IDs.
- Expanded Home Assistant workout/route payloads, tables, and local SVG maps.
- Defined Records as all-time and metric details as history/statistics/table.

### 2026-06-30

- Made today's Activity values open metric detail.
- Added range/date controls to Sleep and tied day view to the selected date.
- Limited metric details and workout samples to one history chart plus
  statistics/table.
- Put sources last and split data in regular tables.
- Standardized average/day for cumulative metrics and collapsed raw values.
- Normalized local bridge URLs to HTTP.
- Increased Home Assistant tile readability and restored stable heights.

### 2026-07-09

- Replaced UUID-only local import deduplication with semantic keys.
- Added bridge-side semantic cleanup and response deduplication.
- Improved Apple Health/local merging and conservative iPhone fallback grouping.
- Added project hygiene ignores and calendar-year range semantics.
- Added all-time record filtering by sport.
- Aligned Home Assistant cache versions, automatic history loading, explicit
  metric opening, retry behavior, and dynamic metric sensor creation.
- Rebuilt bridge workout management around merged lists, collapsible tables,
  source-key dropdowns, duplicate candidates, and stronger deduplication.

### 2026-07-12

- Sorted records newest first across iPhone, Home Assistant, and bridge.
- Added record-to-workout navigation everywhere.
- Required workout dates to remain visible before and after opening a record.

### 2026-07-18

- Made Home Assistant the primary bridge management frontend with dashboard
  PIN, Hevy/Garmin synchronization, and workout link actions through services.
- Removed MQTT from the target architecture and attached all native sensors to
  the user device.

### 2026-08-01

- Converted the project documentation to English.
- Removed the legacy Docker/add-on web dashboard, Home Assistant panel assets,
  dashboard PIN, and unused dashboard polling.
- Reduced the Home Assistant integration to native health, workout, and
  exercise sensors plus five useful bridge services.
- Added stable sport sensors including running pace and stable machine sensors
  for GymPit/Hevy strength-training values.
- Fixed Hevy background synchronization so it honors `HEVY_SYNC_ENABLED`.
