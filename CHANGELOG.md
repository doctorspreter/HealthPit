# Änderungsprotokoll

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

## 26.08.3

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
