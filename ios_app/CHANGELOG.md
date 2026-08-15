# Changelog

All notable changes to the HealthPit iPhone app.

## [Unreleased]

### Added

- **One database underneath the app.** Every value — from Apple Health,
  Garmin, Huawei, GymPit or the Home Assistant bridge — goes through the same
  import path into one measurement store, and every screen reads from there.
  The previous attempt ran the database *alongside* the app: screens read
  caches while batch runs filled the database on the side. Duplicate nights,
  backups that came out empty while the screen was full, and deletions that
  changed nothing on screen all came from that one decision.
- **Strength training broken out.** Repetitions, weight, volume, RPE, set
  type, personal record and equipment settings are separate entities now
  instead of one JSON blob. A blob cannot be charted: no working-weight trend,
  no volume sum, no comparison between providers.
- **38 Pilates and yoga exercises** with MET values, so calories can be worked
  out where a provider reports none: MET × body weight × duration.
- **Origin is read, not assumed.** The writing app decides the provider — a
  Garmin value arriving through Apple Health is filed under Garmin.
- Progress display on first launch, showing what is being read.

### Fixed

- **Nights were cut off at midnight.** Sleep was queried for the calendar day,
  so every phase lying entirely before midnight never reached the app — seven
  hours became the two after midnight. The query now starts 18 hours earlier
  and keeps the nights that end inside the period.
- **Recordings from different sources were mixed.** Watch and phone record the
  same night; thrown together, the time in bed came from one and the phases
  from the other, and the result was a night that never happened. Each
  recording is kept for itself, and the display picks the most complete one.
- **282 labels bypassed the in-app language.** Switching to English left half
  the interface German. Everything runs through the translation now, and the
  shared building blocks translate their own labels.
- Dates and numbers follow the system language, texts follow the app language.
  Before, a sleep screen could show "Fr. 14. Aug. 2026" above "Aug 14, 2026".

### Changed

- Manual, imported and bridge workouts are written to the database instead of
  a separate JSON file. The heuristic that used to match two lists against
  each other is gone — in the database a workout is one row.

