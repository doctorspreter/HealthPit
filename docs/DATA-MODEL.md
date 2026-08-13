# HealthPit data model: metric ids and observations

HealthPit is growing beyond Apple Health. Garmin, Huawei and others follow,
and every one of them names the same value differently. This document
describes how HealthPit keeps one real measurement as exactly one record, no
matter how many providers also carry it.

The Home Assistant integration in `custom_components/healthpit` implements the
parts described here. The iOS side is being rebuilt in step with it.

---

## Two kinds of identifier

```
METRIC        What kind of value is it?     → MetricID        HRT_RATE
OBSERVATION   Which measurement is it?      → ObservationID   UUIDv7
PROVIDER      Which system is involved?     → GAR / APP / HUA
ORIGIN        Where was it produced?        → origin_provider
INGEST        How did it reach HealthPit?   → ingest_provider
```

A metric id says *what* a value is. It is global, provider-neutral and
permanent: uppercase, English, `_` as the separator, a category prefix, and
never reused for a different meaning. If Garmin, Huawei and Apple Health all
report a pulse, it is `HRT_RATE` for all three — where the value came from is
stored separately.

An observation id identifies one concrete measurement. UUIDv7, so it sorts by
creation time and stays globally unique.

### Categories

`ACT` activity · `HRT` heart · `SLP` sleep · `BDY` body · `NRG` energy ·
`RSP` respiratory · `TMP` temperature · `VTL` vitals · `NUT` nutrition ·
`WRK` workout · `CYC` cycle · `ENV` environment · `PRP` proprietary

### Units

The canonical unit is the base unit of the dimension: `M`, `KG`, `S`, `KCAL`,
`L`, `PCT`, `BPM`, `MPS`, `CEL`. What the interface displays (km, miles,
pounds) is a separate question and stays with the interface.

`BPM`, `RPM` and `BRPM` are deliberately *not* convertible into each other. A
pulse is not a cadence, even though both count per minute.

### Vendor-specific values

Not everything may be merged. A Garmin Body Battery and an Oura Readiness
Score both range from 0 to 100, and they still say nothing about each other.
Such metrics carry the provider code as their prefix and are marked
`is_proprietary`:

```
GAR_BODY_BATTERY      OUR_READINESS_SCORE      SAM_ENERGY_SCORE
```

---

## What the integration stores

Every value pushed to Home Assistant now carries, next to the sensor id it
always had:

| Field | Meaning |
|---|---|
| `canonical_metric_id` | the central identifier, e.g. `ACT_STEPS` |
| `legacy_metric_id` | the sensor id the app has always sent (`step_count`) |
| `registry_category` | category behind the identifier |
| `origin_provider` | where the value was produced |
| `ingest_provider` | how it reached HealthPit |
| `source_app_id` | the app or device the platform names |
| `observation_id` | the app's identifier for this one measurement |
| `unit_code` | canonical unit |
| `period_type` | instant, interval, hour, day, night, session, workout |

They appear as attributes on every sensor.

**Entity ids do not change.** The storage key is still the old sensor id,
because a renamed entity loses its history and breaks every automation
pointing at it. The canonical id travels next to it. Retiring the old names is
a separate, later step — see
[docs/REMOVING-THE-COMPATIBILITY-LAYER.md](REMOVING-THE-COMPATIBILITY-LAYER.md).

### Storage migration

Storage version 2 upgrades what is already stored: every value gets its
canonical id, providers are filled in, and workouts get provider codes derived
from their source. Nothing is deleted, no key changes, and running it twice
changes nothing. A value whose meaning cannot be determined is kept and marked
`PRP_…` rather than dropped.

---

## Old sensor id → metric id

The full table is `custom_components/healthpit/metrics.py`
(`LEGACY_METRIC_IDS`, 95 entries). An excerpt:

| Sensor id so far | Metric id | Canonical unit |
|---|---|---|
| `step_count` | `ACT_STEPS` | CNT |
| `distance_walking_running` | `ACT_DISTANCE_WALK_RUN` | M |
| `active_energy_burned` | `NRG_ACTIVE` | KCAL |
| `heart_rate` | `HRT_RATE` | BPM |
| `heart_rate_variability_sdnn` | `HRT_HRV_SDNN` | MS |
| `body_mass` | `BDY_WEIGHT` | KG |
| `oxygen_saturation` | `RSP_SPO2` | PCT |
| `sleep_deep_duration` | `SLP_DEEP_DURATION` | S |
| `cycle_current_day` | `CYC_CURRENT_DAY` | CNT |
| `workout_count_all_time` | `WRK_COUNT_TOTAL` | CNT |

`HRT_HRV_SDNN` and `HRT_HRV_RMSSD` are separate on purpose: Apple reports
SDNN, Garmin and Oura usually RMSSD. A shared `HRT_HRV` would mix two
incomparable series into one chart.

An identifier that is not in the table is not guessed. A wrong mapping would
silently merge two different values; an honest gap is better, and the value is
kept under a provisional `PRP_…` id until someone maps it.

---

## Both app versions are supported

Two app versions are in the field, and the integration handles both:

| App sends | What happens |
|---|---|
| only the old sensor id | accepted; the canonical id is derived from the table, the entry is marked `metric_id_source = derived`, and a repair notice asks for an app update |
| sensor id **and** metric id | accepted as sent, marked `metric_id_source = app`, and the notice disappears |

Nothing is rejected, because neither direction can damage the database. The
notice lives under Home Assistant's *Repairs*, one per device, and clears
itself after the first sync from an updated app.

This handshake is temporary. Its removal is described in
[docs/REMOVING-THE-COMPATIBILITY-LAYER.md](REMOVING-THE-COMPATIBILITY-LAYER.md).

---

## Duplicates

Two recordings of one session appear when several sources report the same
workout. Suggestions and decisions live under the `duplicates` endpoint; a
decision is recorded against source keys, so it survives the same workout
being uploaded again.

Decisions now travel with a description of both sides — sport, title, start,
source — so the app can show *which* workouts a decision was about instead of
two opaque keys.

---

## Deduplication order

When a record arrives, identity is established in this order. Only the first
four are proof:

1. HealthPit's own sync identifier (`HEALTHPIT:OBS-…`)
2. a known external record id for this provider
3. a known original record id (a Garmin value arriving through Apple Health)
4. the same closed period for the same metric and origin — a day total or a
   night is defined by its period, so a different number is a newer state, not
   a second value
5. a controlled heuristic, recorded as an indication rather than a fact

Time and value alone are never enough. Two genuine pulse readings can both say
72 bpm.
