//
//  HealthPitStore+Episode.swift
//  HealthPitCore
//
//  Lesen und Schreiben des Beschwerde-Tagebuchs.
//

import Foundation

extension HealthPitStore {

    /// Alle Episoden, neueste zuerst. Ohne `condition` ueber alle Bilder.
    func healthEpisodes(condition: HealthCondition? = nil,
                        userID: String = HealthPitUser.local) throws -> [HealthEpisode] {
        var sql = """
            SELECT * FROM health_episode
            WHERE user_id = ? AND deleted_at IS NULL
            """
        var bindings: [SQLValue] = [.text(userID)]
        if let condition {
            sql += " AND condition = ?"
            bindings.append(.text(condition.rawValue))
        }
        sql += " ORDER BY started_at DESC;"
        return try database.query(sql, bindings).compactMap(HealthEpisode.init(row:))
    }

    func upsertHealthEpisode(_ episode: HealthEpisode,
                             userID: String = HealthPitUser.local,
                             provider: ProviderCode = .healthPit) throws {
        let now = Date()
        try database.run("""
            INSERT INTO health_episode
                (episode_id, user_id, condition, subtype, severity, started_at,
                 ended_at, symptoms, triggers, medication, medication_helped,
                 notes, origin_provider, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(episode_id) DO UPDATE SET
                condition         = excluded.condition,
                subtype           = excluded.subtype,
                severity          = excluded.severity,
                started_at        = excluded.started_at,
                ended_at          = excluded.ended_at,
                symptoms          = excluded.symptoms,
                triggers          = excluded.triggers,
                medication        = excluded.medication,
                medication_helped = excluded.medication_helped,
                notes             = excluded.notes,
                updated_at        = excluded.updated_at,
                deleted_at        = NULL;
            """, [
                .text(episode.id),
                .text(userID),
                .text(episode.condition.rawValue),
                .text(episode.subtype?.rawValue),
                .int(episode.severity),
                .date(episode.startedAt),
                .date(episode.endedAt),
                .text(Self.joinCodes(episode.symptoms.map(\.rawValue))),
                .text(Self.joinCodes(episode.triggers.map(\.rawValue))),
                .text(episode.medication),
                episode.medicationHelped.map { SQLValue.integer($0 ? 1 : 0) } ?? .null,
                .text(episode.notes),
                .text(provider.rawValue),
                .date(now),
                .date(now),
            ])
    }

    func deleteHealthEpisode(id: String, userID: String = HealthPitUser.local) throws {
        try database.run("""
            UPDATE health_episode SET deleted_at = ?, updated_at = ?
            WHERE episode_id = ? AND user_id = ?;
            """, [.date(Date()), .date(Date()), .text(id), .text(userID)])
    }

    /// Codes sortiert speichern, damit derselbe Inhalt dieselbe Zeile ergibt.
    fileprivate static func joinCodes(_ codes: [String]) -> String {
        codes.sorted().joined(separator: ",")
    }

    fileprivate static func splitCodes(_ text: String?) -> [String] {
        (text ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension HealthEpisode {
    nonisolated init?(row: SQLRow) {
        guard let id = row.string("episode_id"),
              let conditionRaw = row.string("condition"),
              let started = row.double("started_at") else {
            return nil
        }
        let symptoms = HealthPitStore.splitCodes(row.string("symptoms"))
            .compactMap(EpisodeSymptom.init(rawValue:))
        let triggers = HealthPitStore.splitCodes(row.string("triggers"))
            .compactMap(EpisodeTrigger.init(rawValue:))
        self.init(id: id,
                  // Ein unbekannter Code darf den Eintrag nicht verschlucken.
                  condition: HealthCondition(rawValue: conditionRaw) ?? .other,
                  subtype: row.string("subtype").flatMap(EpisodeSubtype.init(rawValue:)),
                  severity: row.int("severity") ?? 0,
                  startedAt: Date(timeIntervalSince1970: started),
                  endedAt: row.double("ended_at").map(Date.init(timeIntervalSince1970:)),
                  symptoms: Set(symptoms),
                  triggers: Set(triggers),
                  medication: row.string("medication") ?? "",
                  medicationHelped: row.int("medication_helped").map { $0 != 0 },
                  notes: row.string("notes") ?? "")
    }
}
