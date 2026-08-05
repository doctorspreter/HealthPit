# Änderungsprotokoll

## 26.08

> ## ⚠️ Wichtig: Diese Fassung braucht eine neue Installation
>
> **Die neue Integration „Healthpit“ muss über HACS installiert werden.**
> Sie ersetzt die bisherige „Healthpit Bridge“.
>
> **Der Docker-Container und die Home-Assistant-App werden nicht mehr
> benötigt** und können nach der Umstellung entfernt werden. Die App sendet ihre
> Daten direkt an Home Assistant.
>
> 1. In HACS die Integration **Healthpit** installieren, Home Assistant neu
>    starten und sie unter **Geräte & Dienste** hinzufügen.
> 2. Im Home-Assistant-Profil einen **Long-Lived Access Token** anlegen und in
>    der App unter **Einstellungen ▸ Verbindung** eintragen.
> 3. Alte „Healthpit Bridge“-Integration, Docker-Container und Add-on entfernen.

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
