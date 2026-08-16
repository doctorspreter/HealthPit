//
//  HiddenWorkoutMigration.swift
//  Healthpit
//
//  Geloeschte Trainings gehoeren in die Datenbank.
//
//  Ein Training aus Apple Health liess sich nicht wirklich loeschen — iOS
//  erlaubt das nur der App, die es geschrieben hat. HealthPit merkte sich
//  deshalb eine Liste versteckter Kennungen in den Einstellungen und filterte
//  sie beim Anzeigen wieder heraus.
//
//  Das war ein zweiter Weg, dasselbe zu sagen: Die Datenbank kennt „geloescht"
//  laengst, als `deleted_at`. Und der zweite Weg galt nicht ueberall — jede
//  Ansicht musste den Filter selbst anwenden, und wer ihn vergass, zeigte
//  Geloeschtes wieder an.
//
//  Diese Umstellung laeuft genau einmal: Was in der Liste stand, wird in der
//  Datenbank als geloescht vermerkt, danach ist die Liste leer und wird nicht
//  mehr gefuehrt.
//

import Foundation

enum HiddenWorkoutMigration {

    static let flagKey = "hidden_workouts_to_database"
    static let flagValue = "v1"

    /// Ueberfuehrt die versteckten Kennungen und leert die Liste.
    @discardableResult
    static func runIfNeeded(store: HealthPitStore,
                            defaults: UserDefaults = .standard) async -> Int {
        if (try? await store.migrationFlag(flagKey)) == flagValue { return 0 }

        let raw = defaults.string(forKey: BridgeSettings.hiddenHealthWorkoutIDsKey) ?? ""
        let hidden = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }

        var deleted = 0
        for identifier in hidden {
            guard let matches = try? await store.workouts(originProvider: .appleHealth,
                                                          sourceRecordID: identifier) else { continue }
            for var workout in matches where workout.deletedAt == nil {
                workout.deletedAt = Date()
                workout.updatedAt = Date()
                if (try? await store.update(workout)) != nil { deleted += 1 }
            }
        }

        // Erst wenn alles uebernommen ist. Bricht der Lauf vorher ab, steht die
        // Liste beim naechsten Start noch da und es wird erneut versucht.
        defaults.removeObject(forKey: BridgeSettings.hiddenHealthWorkoutIDsKey)
        try? await store.setMigrationFlag(flagKey, value: flagValue)
        return deleted
    }
}
