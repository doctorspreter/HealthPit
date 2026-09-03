//
//  PainJournal.swift
//  Healthpit
//
//  Was der Schmerzbereich anzeigt, kommt aus zwei Quellen: den hier
//  erfassten Eintraegen und den Verletzungen, die beim Training notiert
//  wurden. Beide stehen in derselben Liste.
//
//  Ein Eintrag aus einem Training traegt eine aus der Trainingskennung
//  abgeleitete ID. Wird er hier bearbeitet, liegt er danach in der Tabelle
//  und verdraengt die abgeleitete Fassung — sonst stuende er doppelt da.
//

import Foundation

@MainActor
enum PainJournal {

    static func load() async -> [PainEntry] {
        let stored = await storedEntries()
        var byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })

        for entry in await workoutEntries() where byID[entry.id] == nil {
            byID[entry.id] = entry
        }

        return byID.values.sorted { $0.startedAt > $1.startedAt }
    }

    static func save(_ entry: PainEntry) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.upsertPainEntry(entry)
    }

    static func delete(_ entry: PainEntry) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.deletePainEntry(id: entry.id)
    }

    // MARK: Quellen

    private static func storedEntries() async -> [PainEntry] {
        guard let store = try? await HealthPitData.shared.store(),
              let entries = try? await store.painEntries() else {
            return []
        }
        return entries
    }

    /// Die Verletzungen aus den Trainings – lesbar, aber nicht hier gepflegt,
    /// solange sie niemand uebernommen hat.
    ///
    /// Ueber die zusammengefuehrten Trainings, nicht ueber `workouts()`: das
    /// liefert nur die Apple-Health-Seite, und eine im Editor eingetragene
    /// Verletzung haengt am selbst erfassten Training. Genau daran ist es
    /// vorbeigelaufen — eingetragene Schmerzen tauchten hier nie auf.
    private static func workoutEntries() async -> [PainEntry] {
        await HealthQuery.shared.unifiedWorkouts().compactMap { workout in
            guard let injury = workout.injury, !injury.isEmpty else { return nil }
            return PainEntry(workoutID: workout.id,
                             injury: injury,
                             start: workout.startDate)
        }
    }
}
