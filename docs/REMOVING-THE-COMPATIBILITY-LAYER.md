# Prompt: removing the compatibility layer

Two things in this repository are **deliberately temporary**:

1. **The version handshake** between the app and this integration (marker
   `HEALTHPIT-COMPAT-2026-08`). It blocks nothing: the integration accepts
   both app versions and translates the old format, and the app keeps syncing
   with an older integration. Both sides only point out that an update is due.
2. **Compatibility with the old entity names** (`step_count`,
   `sleep_duration`, …). While it lasts, Home Assistant entity ids stay
   unchanged and the metric id travels alongside as an extra field.

Both go away once every installation is up to date. The prompts below are
written so they work in a fresh session without this history.

---

## What the layer does today

| Direction | Behaviour | Where |
|---|---|---|
| Old app → new integration | data is **accepted**, the canonical id is derived from the sensor id, the entry is marked `app_model_version` and `metric_id_source = derived` | `compatibility.py`, `payload.py` |
| ″ | a per-device notice under *Repairs*, clearing itself after the first sync from an updated app | `compatibility_issue.py` |
| New app → old integration | syncing continues, the extra fields are ignored there and filled in by `metrics.upgrade_storage` after the update | app side |
| ″ | a banner in the app's bridge settings | app side |

No direction can damage the database, which is why nothing is blocked.

---

## Check before removing anything

- [ ] Every device runs an app version that sends `model_version = 2`.
      Verifiable in Home Assistant: no `outdated_app_*` entry under *Repairs*,
      and every stored value carries `metric_id_source = app`.
- [ ] Every Home Assistant installation runs the integration with
      `MODEL_VERSION = 2`.
- [ ] For part 2 additionally: users know that entity ids will change
      (history and automations depend on them) — or there is a rename path.

If any point is open: **do not remove.** The transitional code costs almost
nothing; a torn database costs a lot.

---

## Part 1 — prompt: remove the version handshake

> This repository contains a temporary version handshake between the HealthPit
> iPhone app and the Home Assistant integration. Every related spot carries
> the marker `HEALTHPIT-COMPAT-2026-08`.
>
> All installations are up to date now. Please remove it completely:
>
> 1. Find every occurrence with `grep -rn "HEALTHPIT-COMPAT-2026-08" .`
> 2. Delete `custom_components/healthpit/compatibility.py` and
>    `custom_components/healthpit/compatibility_issue.py`.
> 3. In `custom_components/healthpit/http_api.py`, remove the imports from
>    those modules, the `annotate(…)` and `async_update_app_issue(…)` calls,
>    and `**status_fields()` in both the batch answer and the status endpoint.
> 4. Remove the `issues.outdated_app` section from `strings.json` and every
>    `translations/*.json`.
> 5. Write a storage migration that strips `app_model_version` and
>    `metric_id_source` from every stored entry. Without it, fields nobody
>    reads stay behind.
> 6. Delete `tests/test_compatibility_gate.py`.
> 7. On the app side: delete `Bridge/ModelCompatibility.swift`, the
>    `record(…)` call in `connect()`, the `modelVersion` and
>    `requiredAppModelVersion` fields of `BridgeSessionResponse`, the
>    `modelVersion` field of `BridgeBatchPayload`, and the
>    `compatibilityWarning` banner in `BridgeSettingsView`. Clear the
>    `bridge.compatibilityWarning` key from `UserDefaults` as well, otherwise a
>    stale hint stays on screen.
> 8. Run `python3 -m pytest` and build the app.
> 9. Record the removal under "Removed" in `CHANGELOG.md`.
>
> Afterwards `grep -rn "HEALTHPIT-COMPAT-2026-08" .` must find nothing.

---

## Part 2 — prompt: retire the old entity names

> The Home Assistant integration still runs its sensors under the old
> identifiers (`step_count`, `sleep_deep_duration`, …), while the canonical
> identifier (`ACT_STEPS`, `SLP_DEEP_DURATION`) only travels as an attribute.
> The mapping lives in `custom_components/healthpit/metrics.py`
> (`LEGACY_METRIC_IDS`).
>
> Move the integration onto the canonical identifiers:
>
> 1. The storage key in `store.py` (`upsert_metrics`) is
>    `device_id|category|metric_id` with the **old** identifier today, and it
>    determines the entity id. Switch it to the canonical identifier and write
>    a storage migration (version 3) that moves existing keys over.
> 2. **Important:** a changed entity id costs history and automations. Use
>    `entity_registry.async_update_entity` to rename the existing entities
>    instead of creating new ones. Cover it with a test that simulates an
>    existing registry.
> 3. Keep `legacy_metric_id` as an attribute so old automations can still be
>    traced.
> 4. In the app, `HealthMetric.bridgeID` and `BridgeMetricMapping` become
>    unnecessary once the integration expects the canonical identifier. Remove
>    them only after steps 1 and 2 are rolled out.
> 5. Update `docs/DATA-MODEL.md` and `CHANGELOG.md`.
>
> Do not swap the order: let the integration rename first, then move the app.
> The other way round leaves the sensors without anything feeding them.

---

## What stays afterwards

The core is untouched by all of this: the metric registry, observations with
their own ids, provider and external-reference tables, import and export
logic. The transitional code only keeps two versions apart.
