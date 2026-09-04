# Änderungsprotokoll

## Home Assistant 2.8.0

### Added

- **Three new categories: `pain`, `health` and `equipment`.** App 26.09 sends
  what is ongoing in pain and injuries, how much a diary saw in the last 30
  days, and which piece of equipment is due for service or replacement. That
  last one is the point of the whole thing: "change the chain" does not belong
  in an app you have to open — it belongs in a notification.

### Fixed

- **An unknown category no longer fails the whole sync.** The app updates from
  the App Store and the integration from HACS, and nobody does both in the
  same minute. A category this version had not heard of raised an error for
  the entire request, so one new sensor stopped everything else from
  arriving — the opposite of what the compatibility module beside it promises.
  Unknown categories are filed under `vitals` and logged instead.

### Notes

- The data model is unchanged (`MODEL_VERSION = 2`). Nothing existing is
  renamed or removed.
- App 26.09 wants this version to file its new sensors correctly. With an
  older integration the sync still works from now on — the new sensors simply
  land under `vitals` until it is updated.

## Home Assistant 2.7.1

### Fixed

- **"The unit changed from \"\" to \"\"", over and over.** Home Assistant keeps
  the empty string and None apart, and a sensor that reported one on this sync
  and the other on the next was told on every sync that its unit had changed
  and could not be converted. The message read like nonsense because both
  units print as nothing — one of them is a string, the other is not. The
  symbol table mapped `CNT` and `SCORE` to `""`, while an unknown or missing
  code fell through `dict.get` to `None`: the same sensor, two answers,
  depending on what the app happened to send. Repetitions and set counts were
  hit hardest, from HealthPit and GymPit alike.
- Unitless is now `None` everywhere, decided by one function that cannot
  return `""`. Three tests hold the rule in place — one on the table, one on
  the function, one that checks every `native_unit_of_measurement` normalises
  before the value reaches Home Assistant.

### Notes

- Sensors whose stored statistics carry the empty string will ask once more
  after this update, and then stay quiet. Home Assistant's own dialog offers
  to update or clear those historical values; for a unitless sensor there is
  nothing to convert, so either choice is safe.

## Home Assistant 2.7.0

### Changed

- **The last German words in the integration are gone.** Its entity names were
  already English — `Last workout`, `Duration`, `Pace` — but six labels and two
  fallbacks were not: `Übungen`, `Sätze`, `Volumen`, `Dauer`, `Distanz`,
  `Kalorien`, and `Übung` as the name of an exercise that arrives without one.
  They travelled into Home Assistant and back into the app, where a German
  word ended up standing in an English screen.

### Notes

- These labels are read by the app, which uses them as translation keys and
  filters its own figures against them, so this release needs app 26.09 or
  newer to be understood fully. Older apps are not broken by it: they show the
  English word where they used to show the German one, and nothing is lost.
  The app of this round maps both spellings back, so an integration that has
  not been updated yet keeps working exactly as before.
- The data model is unchanged (`MODEL_VERSION = 2`). No entity is renamed or
  removed, and no history is affected.

## Home Assistant 2.6.1

### Fixed

- Nothing changed in the integration itself; this release goes with app 26.08.8
  and GymPit, which now send the canonical sport for every workout.

## Home Assistant 2.6.0

### Changed

- **The workouts come from the database.** The app used to read them straight
  out of HealthKit for the upload, which threw away everything the database had
  already decided: the same session recorded by three apps was three workouts
  again, disabled sources were uploaded anyway, and the sport travelled as a
  translated display name.
- **The sport travels as an identifier.** `sport_type: "RUNNING"` next to the
  display name. Home Assistant no longer has to guess a sport from „Laufen",
  "Running" or "Outdoor Run" — the guessing stays only for what is already
  stored and for older app versions.
- A merged workout keeps its canonical sport, so the same session does not land
  under a different sport once it has been merged.

## Home Assistant 2.5.2

### Fixed

- **A sport fell apart into several.** The sport arrives as a translated
  display name — „Laufen" in German, "Running" in English, "Outdoor Run" from
  another source — and was compared letter for letter. "Peter Run" therefore
  counted only the sessions spelled its way, and the rest sat next to it under
  names of their own. Spellings are folded together now, matched word by word
  at the start: "t-rad-itional strength training" is not cycling. The sensors
  of the folded spellings are removed once.
- **New sensors had no past.** Everything a workout sensor shows is a
  calculation over workouts Home Assistant already holds, but the backfill only
  ran when someone asked for it — GymPit after a sync, the app on a history
  import. Whoever did neither saw empty curves over data that was right there.
  It now runs by itself, shortly after a workout sensor is created.

## Home Assistant 2.5.1

### Fixed

- **The clean-up of the previous layout was a standing rule.** It removed
  entities whose unique ID started with the old prefix, and it ran on every
  push — forever. That is a trap: the day something legitimately carries that
  shape again, it would disappear without anyone being told why. It now runs
  until one pass finds nothing left to do, and the store notes that down, so it
  never runs again. Storage upgrades keep that note.

## Home Assistant 2.5.0

### Changed

- **One device per sport.** Every sport that has workouts gets its own device —
  "Peter Run", "Peter Cycling", "Peter Walk" — hanging under the person next to
  the health areas. The single "Workouts" device that held a run, a ride and
  every strength session in one list is gone.
- **Strength training lives with its machines.** Sessions coming from GymPit go
  to "Peter Gym workouts", where the exercises already are. One training in one
  place.
- **The exercises are no longer in two places at once.** Weight, repetitions,
  volume and RPE arrive as canonical values from GymPit and are sensors of
  their own; the workout upload produced a second, German-named copy of the
  same numbers. Only what a single value cannot say is left: sessions, best
  weight, total volume, personal records and when the exercise was last
  trained.
- **Names no longer carry the sport or the language.** The device is called
  "Peter Run", so the sensor on it is simply "Distance" instead of „Laufen
  Distanz". Every name in this integration is English and fixed, because a name
  travels into an entity ID and must not move with the interface language.

### Removed

- The workout sensors of the previous layout (`{user}_workout_…`) are removed
  from the entity registry rather than left behind as unavailable rows. Their
  devices follow once they hold nothing.

### Added

- The backfill covers the exercise aggregates too: sessions and total volume
  are written into the statistics at the hour each session happened. What the
  removed sensors showed is a calculation over the stored workouts, so it comes
  back with its whole history rather than starting at zero today.

## Home Assistant 2.4.5

### Changed

- **The exercises no longer get a device each.** They are entities on the one
  "Gym workouts" device now and carry the exercise in their name. Home
  Assistant lists devices flat, so a device per machine put fifteen entries
  next to Body, Heart and Sleep — the grouping the hierarchy promised was
  nowhere to be seen. Entity IDs and history are untouched; the empty devices
  left behind are removed automatically once nothing hangs on them any more.

### Added

- **Strength values reach into the past.** Every set GymPit sends is written
  into the long-term statistics at the hour it happened, with mean, lowest and
  highest per hour. Only the newest value per exercise is kept in the store and
  Home Assistant's state table cannot be backdated, so everything before the
  last upload existed nowhere: a year of training showed a single point.
- Numeric exercise sensors have a state class and, where it fits, a device
  class. Without a state class Home Assistant keeps no statistics at all, and
  the imported past would have had nothing to hang on.

### Fixed

- A value whose sensor does not exist yet is kept and retried instead of being
  dropped. The sensor is created from the same push that carries the value, so
  the first attempt regularly comes too early.

## Home Assistant 2.4.0

### Added

- **Values are grouped into devices.** Every user still has their device, but
  their values now sit under areas below it — Body, Heart, Sleep, Activity,
  Workouts. Entity IDs are untouched: in Home Assistant the device is separate
  from the entity ID, so history and automations survive the regrouping.
- **One device per exercise.** Strength values arrive per exercise now, so the
  leg press has its own device with weight, repetitions, volume and RPE
  underneath. A single "set weight" sensor would jump between exercises with
  every set — 45 kg on the abductor, then 80 on the leg press — and its history
  would be noise.
- **Canonical values are accepted.** From app model version 2 the payload
  carries HealthPit's own identifiers (`WRK_SET_WEIGHT` instead of
  `weight_kg`). Nothing is translated on the way any more. Identifiers that are
  not canonical are refused so the translation table cannot come back through
  the side door.
- Equipment settings (seat, backrest, handle, range) arrive as text sensors —
  but only where they were actually set. GymPit no longer ships presets, so a
  value that arrives is one the user chose.

### Notes

- Older app versions send no values at all. That is not an error; they keep
  working exactly as before.
- Only the latest value per exercise and metric is stored. The long-term
  history is Home Assistant's job — its recorder keeps what the sensor
  reported.

## Home Assistant 2.3.1

### Fixed

- **The integration failed to set up.** The storage upgrade was handed to
  Home Assistant's `Store` as a `migrate_func` keyword, which that class does
  not take — setup ended in `TypeError` and the integration never loaded. The
  migration now lives in a `Store` subclass overriding `_async_migrate_func`,
  which is the documented hook. A test reads the source and fails if the wrong
  hook ever comes back.


## Home Assistant 2.3.0

### Added

- **Central metric registry.** Every value now carries a stable,
  provider-neutral identifier (`ACT_STEPS`, `HRT_RATE`, `BDY_WEIGHT`) next to
  the sensor id it always had, plus its category, canonical unit and where it
  came from. See [docs/DATA-MODEL.md](docs/DATA-MODEL.md).
- **Provider fields on every value.** `origin_provider` says where a value was
  produced, `ingest_provider` how it reached HealthPit — a Garmin reading that
  arrives through Apple Health is now distinguishable from an Apple one.
- **Storage version 2** upgrades everything already stored: canonical ids are
  filled in, workouts get provider codes, values whose meaning is unknown are
  kept and marked rather than dropped. Nothing is deleted, no key changes, and
  running it twice changes nothing.
- **Both app versions are supported.** An app that still sends only the old
  sensor ids is accepted and translated; a per-device notice under *Repairs*
  asks for an update and clears itself after the first sync from an updated
  app. Nothing is rejected.
- **Duplicate decisions say what they were about.** The `duplicates` endpoint
  now describes both sides of a past decision — sport, title, start, source —
  instead of sending two opaque keys.

### Changed

- Sensors expose the new fields as attributes: `canonical_metric_id`,
  `registry_category`, `origin_provider`, `ingest_provider`, and where known
  `source_app_id`, `observation_id`, `unit_code`, `period_type`.
- **Entity ids are unchanged on purpose.** A renamed entity loses its history
  and breaks automations, so the old sensor id stays the storage key.
  Retiring the old names is a separate, later step:
  [docs/REMOVING-THE-COMPATIBILITY-LAYER.md](docs/REMOVING-THE-COMPATIBILITY-LAYER.md).

### Removed

- The `testordner` sandbox copy of the iOS app, which never belonged in this
  repository.


## Home Assistant 2.2.0

### Added

- The authenticated API can now import hourly HealthKit metric history into
  Home Assistant's long-term statistics.
- A dedicated workout-history endpoint can rebuild cumulative workout
  statistics after a full historical upload from the iPhone app.
- Payload tests cover ordered history batches, finite numeric values, display
  precision, and dynamic GymPit workout entity discovery.

### Changed

- Sensor states and imported statistics now use metric-aware precision, which
  removes meaningless floating-point tails while preserving useful decimals.
- Recorder metadata now includes the current mean type and unit class required
  by Home Assistant's statistics API.
- The setup documentation and `healthpit.import_history` service description
  now explain the complete historical import flow.

### Fixed

- Non-finite metric values are rejected before they can enter storage or
  long-term statistics.

## 26.09

### Added

- **Pain and injuries as an area of their own.** A calendar, the complaints
  that are still running, and the history below it. A day is coloured for as
  long as a complaint covers it — not only the day it was entered, but the
  whole span up to its end, so a two-week strain is two weeks long on the
  calendar. Depth of colour follows the severity. An entry carries body
  region, kind of pain, severity, start, end and a note.
- **The injuries noted during a workout show up there too.** They are read
  from the workouts and listed alongside the entries made here, and they end
  with the training day: what hurt during sport is not automatically still
  there the next morning. Whoever wants it to carry on opens the entry and
  takes the end out or pushes it back; from then on it lives in the table and
  that default no longer applies to it. Its identifier is derived from the
  workout, so a later sync cannot enter it twice.
- **Physical health: a diary for what comes in episodes.** Headache, migraine,
  panic attack, dizziness, asthma, allergy and more. An entry carries the
  form, the severity, start and end, the symptoms alongside it, the possible
  triggers, and whether a medication helped. The lists of symptoms and
  triggers follow the condition — asking about aura on a panic attack would be
  nonsense, and a long list where most of it does not apply gets filled in by
  nobody. Each diary shows how often it happened per month, the average
  severity and duration, and the triggers and symptoms that come up most; that
  last one is the only reason anyone keeps such a diary.
- **Equipment with service and replacement**, as an area of its own on the
  home screen. Shoes, bike, mat: each with a date from which it is in use, so it falls to the matching workouts on its
  own — whoever buys shoes in March does not want to assign every run by hand.
  A single workout can still be assigned differently, and that choice beats
  the automatic one, including the choice "none". Distance is calculated from
  the workouts rather than counted separately: a second tally would be the
  first number to drift once a workout is added or deleted.
- **Equipment has parts.** A bike is not replaced when the chain has done
  3000 km — the chain is. Each piece carries a list of parts, each with its own
  interval and its own "last done": chain, brake pads, tyres, cassette, cables,
  chain lube and a full service for a bike; insoles and laces for shoes; a
  resole for climbing shoes. The suggestions are starting points, every
  interval can be changed, and a free-named part covers whatever nobody
  thought of here.
- **Distance and time, together.** A threshold can be set in kilometres, in
  days, or in both — shoes after 800 km *or* after three years, whichever comes
  first, because the foam hardens in the cupboard too. Whichever limit is
  driving the display is named underneath it.
- **Every figure a sport actually has.** Tapping a sport used to show three
  fixed tiles — sessions, duration, and either volume or distance — so a run
  showed little more than its duration while pace, calories and heart rate sat
  in the database unused. The tiles are built from what is recorded now, and a
  figure with no data behind it is left out rather than shown empty.
- **Up to three figures in one chart, chosen on the figures themselves.**
  Every figure that has data can be picked — duration, distance, calories,
  pace, heart rate, volume, sets, reps — by tapping its own tile below the
  chart, which then carries the colour of its line. A separate row of buttons
  above the chart would have written the same words a second time; the values
  are already there. Each line is scaled to its own peak, because kilometres
  and calories on one axis would leave the distance flat on the floor; the
  real values with their units appear on tap.
- **The new areas reach Home Assistant.** Ongoing complaints and the strongest
  of them, how much a diary saw in the last 30 days, distance per piece of
  equipment and how many parts are due. That last one is why: "change the
  chain" belongs in a notification, not in an app you have to open. Needs
  integration 2.8.0.

### Changed

- **Units follow the measurement setting all the way to Home Assistant.**
  Choosing imperial now sends lb and mi across instead of converting for the
  screen only. So that a switch does not tear the long-term statistics apart,
  every such sensor carries a matching `device_class` and a unit spelled the
  way Home Assistant spells it — `mL`, not `ml`; `fl. oz.`, not `fl oz`. The
  metric history is converted on the same path as the current value; leaving
  it raw would have made one sensor jump between lb and kg.
- **A manual workout stores a canonical sport.** It used to store the typed
  name: "Laufen" became `LAUFEN`, because the existing normalisation only
  smooths spelling and does not translate. The database held language instead
  of a code, and everything checking for `RUNNING` walked past it — running
  shoes would never have fallen to a manually recorded run. Existing rows
  still resolve, by name.

### Fixed

- **German words in the sleep section, whatever the language.** Not a missing
  translation: the stat cards looked their title up with a key that was
  assembled at runtime — `"\(prefix)Schlafzeit"`. No such key can exist in any
  table, so every one of them fell back to the German literal. The key is a
  plain literal again and the "Ø" is put in front only after the lookup, since
  it is a sign and not a word. Reported from TestFlight on an en-US device.
- **Sensor names and units in Home Assistant followed the app language.** The
  whole bridge payload was built from the display layer: `title` was
  `L10n.string(titleKey)` and `unit` was `L10n.string(canonicalUnitSymbol)`,
  both translated. Switching the app to English renamed every sensor and
  changed its `unit_of_measurement`. Everything that leaves the app now uses
  `L10n.canonical`, which always reads the English table. `HealthMetric.swift`
  had forbidden exactly this in writing since it was written.
- **`device_class` was lost outside German.** It switched on the translated
  unit symbol, so `°C` only ever matched in German and temperature sensors
  arrived without a device class.
- **Pain recorded in a workout never reached the pain area.** It was read
  through the Apple Health side of a workout, and an injury typed into the
  editor hangs on the locally recorded one — the wrong of the two sources.
- **More German on English screens, found by running it.** The two labels on
  the first screen had no English entry at all — the very screen App Review
  looks at. The workout calendar had its weekday initials written into the
  source as `Mo Di Mi Do Fr Sa So`; they come from the calendar now. A
  workout's title is stored text and went past the translation. In total 60
  keys were added across this round, and all four translated tables are
  complete: 1024 keys, none missing in Spanish, French or Simplified Chinese.
- **One key meant two things.** `Einheiten` was both the training sessions on
  the workout header and the measurement units in settings, so the header read
  "Units" in English. Sessions have their own key now.
- An "Equipment" heading stood over an empty section on a workout when no
  equipment was recorded at all.

### Notes

- Sensors whose unit used to be a German word (`Schritte`, `Etagen`, `Züge`,
  `Stöße`, `Atemzüge/min`) have no quantity Home Assistant knows, so they carry
  no `device_class`. Their unit changes once, to the English word, and Home
  Assistant will note the change for those sensors.
- Schema v3 to v6: `pain_entry`, `health_episode`, `equipment`,
  `equipment_usage` and `equipment_component`. Body regions, kinds of pain,
  conditions, symptoms, triggers and part kinds are all stored as English
  codes, the way the sport is stored on a workout — the display names are
  translated in the app.

### App Review

- The button in front of the HealthKit permission request reads "Continue"
  instead of "Connect to Apple Health", and the card on the home screen reads
  the same instead of "Allow access" (guideline 5.1.1(iv)). The explanatory
  text in front of the request is untouched — that part is allowed.

## 26.08.8

### Behoben — beim Durchsehen und im Simulator gefunden

- **Die Versionsnummer stand als „26.08."** — beim Hochzählen war die letzte
  Stelle verlorengegangen. Nur im Simulator zu sehen, nicht im Code.
- Der Erklärungstext der Datensicherung beschrieb noch die alte Sicherung
  („alle lokalen Workouts").
- **Kopfzeilen blieben deutsch, auch auf Englisch:** „15 Messwerte" und die
  Beschreibung jedes Gesundheitsbereichs gingen an der Übersetzung vorbei, weil
  sie als Parameter statt als Text übergeben werden.

### Entfernt

- **Die letzten Dateien neben der Datenbank.** Die Rekordseite las die
  Trainings aus der Datenbank *und* die daraus gerechneten Rekorde aus einer
  Datei — sie werden jetzt aus den Trainings gerechnet, die ohnehin schon
  dastehen. Der Speicher für die selbst erfassten Trainings ist ganz
  verschwunden: Löschen geht in die Datenbank, die Sicherung liest von dort,
  und eine Sicherung der alten Fassung landet beim Einlesen ebenfalls dort.
- **Vier Reste beim Nachzählen:** Der Zusammenführer zweier Bestände in der
  Trainingsliste war nach dem Umbau unerreichbar (rund 160 Zeilen), der Puls im
  Editor und das Training im undatierten Import lasen noch an der Datenbank
  vorbei, und die Brücke holte die selbst erfassten Trainings weiterhin aus der
  Datei daneben — was dort gelöscht war, ging trotzdem hoch.
- **Drei Zwischenspeicher, die nur noch geschrieben wurden.** Trainings, Schlaf
  und die Startseiten-Kennzahlen wurden bei jedem Abgleich in Dateien
  geschrieben, die seit dem Umbau niemand mehr liest — eine zweite Kopie
  desselben Bestands. Der Vorladedienst holt nur noch, was wirklich von außen
  kommt.
- Die Lesewege in `HealthKitManager`, die nach dem Umbau unerreichbar waren:
  Zyklusübersicht, Stundenverlauf, Schlafabfrage, Tageswert, Zielfortschritt.
  Rund 200 Zeilen, die aussahen, als würden sie noch gebraucht.

### Behoben — beim Durchsehen gefunden

- **Die Datensicherung enthielt nur die von Hand erfassten Trainings.** Der
  Dienst für die ganze Datenbank war gebaut und wurde von niemandem aufgerufen.
  Alles aus Apple Health, jede Nacht, jeder Messwert und jede Quellenregel
  fehlten in der Datei. Eine Sicherung trägt jetzt den ganzen Bestand, nach
  Herkunft geordnet; alte Sicherungen lassen sich weiter einlesen.
- **„Lokale Daten löschen" hat die Datenbank nie angefasst.** Geleert wurden
  nur die Dateien daneben — es sah gelöscht aus, bis die nächste Ansicht
  nachfragte.
- Die Zykluskachel auf der Startseite und das Trainingsdetail im Editor lasen
  weiter unmittelbar aus Apple Health.

## 26.08.7

### Geändert

- **Strecke und Pulskurve stehen jetzt auch in der Datenbank.** Sie waren der
  letzte Bestand, den die App bei jedem Öffnen frisch aus Apple Health las. Der
  Katalog führt `WRK_ROUTE` seit dem Umbau — es war nie eine Frage des Modells,
  sondern der Menge. Geholt wird deshalb beim ersten Öffnen eines Trainings und
  dann behalten: Was man ansieht, liegt danach vollständig in der Datenbank;
  was niemand ansieht, kostet nichts.
- Die Kennzahlen der Detailseite werden aus dem gespeicherten Training
  gerechnet statt aus dem HealthKit-Objekt.
- Der Puls für ein von Hand erfasstes Training wird beim Erfassen ergänzt, in
  der Aufnahmeschicht — die Brücke greift auf nichts mehr außerhalb der
  Datenbank zu.

## 26.08.6

### Geändert

- **Gelöscht steht jetzt in der Datenbank.** Ein Training aus Apple Health
  liess sich nie wirklich löschen — iOS erlaubt das nur der App, die es
  geschrieben hat. HealthPit merkte sich deshalb eine Liste versteckter
  Kennungen in den Einstellungen, und jede Ansicht musste sie selbst beachten.
  Wer den Filter vergass, zeigte Gelöschtes wieder an; die Brücke lud es weiter
  hoch. Jetzt wird die Zeile in der Datenbank als gelöscht vermerkt, und alle
  Ansichten bekommen sie gar nicht mehr zu sehen. Was in der alten Liste stand,
  wird beim ersten Start einmalig übernommen.
- Weich gelöscht: die Zeile bleibt stehen. Ein harter Wurf hätte zur Folge,
  dass derselbe Datensatz beim nächsten Import aus Apple Health wieder
  hereinkäme.
- Die Detailseite eines selbst erfassten Trainings liest Strecke, Übungen und
  Sätze aus der Datenbank statt aus der zweiten Datei daneben.

## 26.08.5

### Geändert

- **Alles liest jetzt aus der Datenbank.** Die Brücke nach Home Assistant, die
  Vorlade-Zwischenspeicher und die Zyklusansicht holten ihre Werte weiterhin
  unmittelbar aus Apple Health — und damit galt für sie nichts von dem, was die
  Datenbank entschieden hatte: keine Quellenregeln, keine Wiedererkennung
  doppelter Aufzeichnungen, keine kanonischen Einheiten. Betroffen waren
  Messwerte, Stundenverlauf, Schlaf, Zyklus, Zielfortschritt und die
  Trainings-Zwischenspeicher.
- **Der Zyklus liegt endlich in der Datenbank.** Blutungstage und die
  Ereignisse (Ovulationstest, Zervixschleim, Zwischenblutung, sexuelle
  Aktivität) werden beim Import mitgelesen. Geschrieben wird weiterhin nach
  Apple Health — dort gehört der Eintrag hin —, und danach zieht die Datenbank
  sofort nach.
- Der Verlauf, den die App nach Home Assistant schickt, hat jetzt Tages- statt
  Stundenauflösung. Das ist die Auflösung, in der die Datenbank die Werte
  führt; die Diagramme über Monate und Jahre ändern sich dadurch nicht.

### Bleibt bei Apple Health

- Strecke und Pulskurve eines Trainings sowie der Puls zu einem von Hand
  erfassten Training: Rohserien mit tausenden Punkten je Einheit stehen nicht
  in der Datenbank. Beides ist Ableitung beim Erfassen, keine Anzeige.

## 26.08.4

### Behoben

- **Der Trainings-Upload las an der Datenbank vorbei.** Er holte die Trainings
  unmittelbar aus HealthKit — und damit war jede Entscheidung der Datenbank
  wieder verworfen: dieselbe Einheit aus drei Apps war erneut drei Trainings,
  abgeschaltete Quellen gingen trotzdem hoch, und die Sportart reiste als
  übersetzter Anzeigename. Jetzt kommt sie aus der Datenbank, mitsamt der
  sprachneutralen Sportart.

## 26.08.3

### Behoben

- **Entschiedene Duplikate ließen sich nicht zuordnen.** Unter „Entschieden"
  stand nur „Als ein Training" und ein Knopf zum Zurücknehmen — richtig, aber
  ununterscheidbar. Die Integration schickt die beiden Trainings längst neben
  den Schlüsseln mit; die App hat sie nur nie gelesen. Jetzt stehen Sportart,
  Datum, Dauer, Strecke und Quelle beider Aufzeichnungen darunter. Wurde ein
  Training seither gelöscht, sagt die Zeile das und bleibt zurücknehmbar.

### Neu

- **Zusammenführen fragt jetzt nach.** Statt sofort zu entscheiden, öffnet
  „Zusammenführen" ein Blatt: Welche der beiden Aufzeichnungen bleibt, und soll
  die andere auch aus Apple Health verschwinden?
- Zu jeder Seite steht dabei, **welche App den Eintrag in Apple Health
  geschrieben hat** — und ob HealthPit ihn dort löschen darf. iOS erlaubt jeder
  App nur, ihre eigenen Einträge zu entfernen. Kommt dasselbe Training von
  Health Sync und von Huawei, kann HealthPit keine der Kopien löschen; das
  steht vor der Entscheidung da und nicht als Fehlermeldung danach. Für diesen
  Fall führt ein Knopf direkt in Apple Health.

## 26.08.2

### Behoben

- **Sauerstoffsättigung stand als 9620 %.** Die Anzeige rechnete Prozentwerte
  weiterhin so um, wie HealthKit sie liefert — als Bruch zwischen 0 und 1. Aus
  der Datenbank kommen sie aber schon als Prozent, und ×100 aus 96,2 dann 9620.
  Betraf jeden Prozentwert: Körperfett, Gehstabilität, Gangasymmetrie,
  Perfusionsindex. Was aus Apple Health gelesen und an Home Assistant geschickt
  wird, war und bleibt richtig.
- Die Ampel-Grenzen für Prozentwerte standen noch im alten Maßstab (0,95 statt
  95) und stuften deshalb alles als „gut“ ein.
- **Diagramme mit unbrauchbarer Skala.** Die Achse begann immer bei null. Bei
  einer Sauerstoffsättigung zwischen 95 und 98 hieß das: ein waagerechter
  Streifen ganz oben, jeden Tag derselbe. Sie spannt sich jetzt um die
  vorhandenen Werte. Bei Summen — Schritte, Kalorien — bleibt sie bei null,
  dort ist die Höhe des Balkens die Aussage.

## 26.08.1

### Neu

- **Duplikate.** Melden mehrere Quellen dasselbe Training, schlägt die
  Integration die Paare vor; unter **Einstellungen ▸ Duplikate** wird
  entschieden, was zusammengehört. Entscheidungen lassen sich zurücknehmen.
  Vorgeschlagen wird nur, nie automatisch zusammengeführt: zwei Einheiten kurz
  hintereinander sind genauso echt wie eine doppelt gemeldete.

### Behoben

- GymPit-Krafttrainings werden beim Öffnen und Aktualisieren der Workout-Liste
  aus Home Assistant nachgeladen. Die App zeigt dadurch wieder Übungen und
  Sätze statt nur der Zusammenfassung aus Apple Health.
- Die App lud GymPit-Trainings erneut hoch, die GymPit selbst schon gesendet
  hatte. Jedes Training lag dadurch zweimal in Home Assistant.
- Schreibweise überall **HealthPit** und **GymPit**.
- Der Umstellungshinweis erscheint bei jedem Start, bis die Verbindung zu Home
  Assistant einmal erfolgreich synchronisiert hat. Vorher verschwand er nach
  dem ersten Wegtippen, auch wenn nichts eingerichtet war.

## 26.08

> ## ⚠️ Wichtig: Diese Fassung braucht eine neue Installation
>
> **Die neue Integration „HealthPit“ muss über HACS installiert werden.**
> Sie ersetzt die bisherige „HealthPit Bridge“.
>
> **Der Docker-Container und die Home-Assistant-App werden nicht mehr
> benötigt** und können nach der Umstellung entfernt werden. Die App sendet ihre
> Daten direkt an Home Assistant.
>
> 1. In HACS die Integration **HealthPit** installieren, Home Assistant neu
>    starten und sie unter **Geräte & Dienste** hinzufügen.
> 2. Im Home-Assistant-Profil einen **Long-Lived Access Token** anlegen und in
>    der App unter **Einstellungen ▸ Verbindung** eintragen.
> 3. Alte „HealthPit Bridge“-Integration, Docker-Container und Add-on entfernen.

### Neu

- **Direkt an Home Assistant.** Die App sendet ihre Daten mit einem Long-Lived
  Access Token unmittelbar an Home Assistant; die Integration speichert sie und
  erzeugt die Entitäten. Kein Container, kein Add-on, kein Zwischenstück.
- **Mehrere Personen im Haushalt.** Ein Eintrag genügt für alle. Jede Person legt
  ihren eigenen Token an, Home Assistant erkennt daran, wem die Daten gehören,
  und jede bekommt ein eigenes Gerät mit eigenen Entitäten.
- **Zyklus-Tracker:** eigene Kategorie mit Dashboard-Kachel, monatsweiser
  Übersicht, Zyklusliste und Ereignissen. Liest Blutung, Zwischenblutung,
  Ovulationstests, Zervixschleim und sexuelle Aktivität aus Apple Health;
  Blutungstage, Zwischenblutungen und Ovulationstests lassen sich in der App
  erfassen, löschen und werden zurückgeschrieben. Fremde Einträge bleiben
  unangetastet. Die Kennzahlen gehen wie alle anderen Daten mit.
- **Maßeinheiten umschaltbar:** Wie in Apple Health / Metrisch / Imperial, unter
  Einstellungen ▸ Sprache und Einheiten. Betrifft Distanz, Tempo, Gewicht, Größe,
  Temperatur und Trinkmenge sowie den Workout-Bereich inklusive Meilen-Runden.
  Übertragen werden weiterhin metrische Werte, damit die Sensoren in Home
  Assistant ihre Historie behalten.
- **Laufstrecken als zusammenhängende Route.** Bisher wurde jeder GPS-Punkt
  einzeln übertragen. Jetzt gibt es je Person ein Bild mit dem gezeichneten
  Streckenverlauf und einen Sensor mit Distanz und Eckdaten; jede Strecke lässt
  sich als GPX, GeoJSON oder SVG abrufen.
- **Rückwirkende Statistiken.** Der Dienst `healthpit.import_history` schreibt
  die aufsummierten Sportwerte aller gespeicherten Workouts in die
  Langzeitstatistik, damit Graphen die Vergangenheit abdecken. Wiederholbar.
- **Statusanzeige beim Synchronisieren:** die fünf Schritte einzeln mit
  Fortschritt, am Ende die Zahl der übertragenen Werte oder der Grund des
  Fehlschlags. Der erste Sync startet nach dem Verbinden von selbst.
- **Wiederkehrende Trainings.** Beim manuellen Anlegen lässt sich ein Rhythmus
  hinterlegen — täglich, wöchentlich, zweiwöchentlich, monatlich — mit Enddatum
  und Vorschau, wie viele Einträge entstehen.
- **Kacheln der Startseite ausblenden** und wieder einblenden; sie kehren an ihre
  alte Stelle zurück.
- **Kachel für fehlende Apple-Health-Freigabe.** Wurde die Freigabe abgelehnt,
  erscheint sie als erste Kachel und fragt erneut.
- **Einstellungen in Untermenüs:** Verbindung, Datenquellen, Datensicherung,
  Startseite, Sprache und Einheiten.

### Behoben

- Absturz in der Schlafansicht in allen Sprachen außer Deutsch.
- Synchronisierung schlug mit „400“ fehl, sobald Zyklusdaten vorhanden waren.
- Fehlermeldungen zeigten nur die Statusnummer statt des Grundes.
- Mehrere Texte blieben deutsch, obwohl eine andere Sprache eingestellt war.
- Sportarten wechselten nicht mit der Sprache.
- Rohe Serverantworten standen in der Statuszeile statt unter „Technische
  Details“.
- Die iOS-Freigabe für das lokale Netzwerk wurde nie angefragt, wodurch die
  lokale Verbindung ohne erkennbaren Grund scheiterte.

### Zum Umstieg

Die Integration heißt jetzt `healthpit`, die Entitäts-IDs ändern sich also einmal.
Wer eine Vorgängerfassung installiert hatte, entfernt die Integration und fügt
sie neu hinzu. Danach lohnt `healthpit.import_history`, damit die Langzeitgraphen
nicht bei null anfangen.
