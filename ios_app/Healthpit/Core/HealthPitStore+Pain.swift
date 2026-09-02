//
//  HealthPitStore+Pain.swift
//  HealthPitCore
//
//  Lesen und Schreiben des Schmerz- und Verletzungsbestands.
//
//  Wie ueberall im Store: englische Codes hinein, englische Codes heraus.
//  Uebersetzt wird erst in der Ansicht.
//

import Foundation

extension HealthPitStore {

    /// Alle Eintraege, neueste zuerst. Geloeschtes bleibt draussen.
    func painEntries(userID: String = HealthPitUser.local) throws -> [PainEntry] {
        try database.query("""
            SELECT * FROM pain_entry
            WHERE user_id = ? AND deleted_at IS NULL
            ORDER BY started_at DESC;
            """, [.text(userID)])
            .compactMap(PainEntry.init(row:))
    }

    /// Legt an oder aktualisiert – die Kennung entscheidet.
    ///
    /// Eintraege aus einem Training tragen eine aus der Trainingskennung
    /// abgeleitete ID, damit ein erneuter Abgleich sie nicht verdoppelt.
    func upsertPainEntry(_ entry: PainEntry,
                         userID: String = HealthPitUser.local,
                         provider: ProviderCode = .healthPit) throws {
        let now = Date()
        try database.run("""
            INSERT INTO pain_entry
                (entry_id, user_id, kind, body_region, pain_quality, severity,
                 started_at, ended_at, notes, workout_id, origin_provider,
                 created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(entry_id) DO UPDATE SET
                kind         = excluded.kind,
                body_region  = excluded.body_region,
                pain_quality = excluded.pain_quality,
                severity     = excluded.severity,
                started_at   = excluded.started_at,
                ended_at     = excluded.ended_at,
                notes        = excluded.notes,
                workout_id   = excluded.workout_id,
                updated_at   = excluded.updated_at,
                deleted_at   = NULL;
            """, [
                .text(entry.id),
                .text(userID),
                .text(entry.kind.rawValue),
                .text(entry.region.rawValue),
                .text(entry.quality?.rawValue),
                .int(entry.severity),
                .date(entry.startedAt),
                .date(entry.endedAt),
                .text(entry.notes),
                .text(entry.workoutID),
                .text(provider.rawValue),
                .date(now),
                .date(now),
            ])
    }

    /// Weich geloescht, wie alles andere auch – eine Sicherung soll den
    /// Loeschvorgang mitnehmen koennen.
    func deletePainEntry(id: String, userID: String = HealthPitUser.local) throws {
        try database.run("""
            UPDATE pain_entry SET deleted_at = ?, updated_at = ?
            WHERE entry_id = ? AND user_id = ?;
            """, [.date(Date()), .date(Date()), .text(id), .text(userID)])
    }
}

extension PainEntry {
    nonisolated init?(row: SQLRow) {
        guard let id = row.string("entry_id"),
              let kindRaw = row.string("kind"),
              let kind = PainEntryKind(rawValue: kindRaw),
              let regionRaw = row.string("body_region"),
              let started = row.double("started_at") else {
            return nil
        }
        self.init(id: id,
                  kind: kind,
                  // Ein unbekannter Code darf den Eintrag nicht verschlucken.
                  region: BodyRegion(rawValue: regionRaw) ?? .other,
                  quality: row.string("pain_quality").flatMap(PainQuality.init(rawValue:)),
                  severity: row.int("severity") ?? 0,
                  startedAt: Date(timeIntervalSince1970: started),
                  endedAt: row.double("ended_at").map(Date.init(timeIntervalSince1970:)),
                  notes: row.string("notes") ?? "",
                  workoutID: row.string("workout_id"))
    }
}
