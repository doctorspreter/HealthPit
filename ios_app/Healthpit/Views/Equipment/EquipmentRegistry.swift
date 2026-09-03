//
//  EquipmentRegistry.swift
//  Healthpit
//
//  Welches Training welches Ausruestungsstueck getragen hat.
//
//  Automatisch: ein Stueck deckt ein Training, wenn dessen Datum in seine
//  Nutzungszeit faellt und die Sportart passt. Ausdrueckliche Zuordnungen
//  stechen das — auch die Zuordnung „hier nichts", sonst liesse sich die
//  Automatik nie abwaehlen.
//
//  Decken mehrere Stuecke dasselbe Training ab (zwei Paar Laufschuhe
//  parallel), zaehlt das zuletzt in Gebrauch genommene. Alles andere waere
//  geraten, und doppelt zaehlen darf die Strecke auf keinen Fall.
//

import Foundation

@MainActor
enum EquipmentRegistry {

    static func load(includeRetired: Bool = true) async -> [Equipment] {
        guard let store = try? await HealthPitData.shared.store(),
              let items = try? await store.equipment(includeRetired: includeRetired) else {
            return []
        }
        return items
    }

    static func save(_ item: Equipment) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.upsertEquipment(item)
    }

    static func delete(_ item: Equipment) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.deleteEquipment(id: item.id)
    }

    static func setOverride(workoutID: String, equipmentID: String?) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.setEquipmentOverride(workoutID: workoutID, equipmentID: equipmentID)
    }

    static func clearOverride(workoutID: String) async {
        guard let store = try? await HealthPitData.shared.store() else { return }
        try? await store.clearEquipmentOverride(workoutID: workoutID)
    }

    // MARK: Zuordnung

    /// Das Stueck, das dieses Training getragen hat – oder nichts.
    static func equipment(for workout: UnifiedWorkout,
                          in items: [Equipment],
                          overrides: [String: String?]) -> Equipment? {
        if let override = overrides[workout.id] {
            // Ausdrueckliche Zuordnung, auch wenn sie „nichts" lautet.
            return override.flatMap { id in items.first { $0.id == id } }
        }
        return automaticMatch(for: workout, in: items)
    }

    private static func automaticMatch(for workout: UnifiedWorkout,
                                       in items: [Equipment]) -> Equipment? {
        // Ueber canonicalCode, damit auch die Altbestaende greifen, in denen
        // der deutsche Name als Sporttyp steht („LAUFEN" statt „RUNNING").
        let sportType = workout.health.map { SportTypeDisplay.canonicalCode(for: $0.sportType) }
        return items
            .filter { item in
                guard item.isAutomatic, item.covers(workout.startDate) else { return false }
                guard let sportType else {
                    // Selbst erfasste Trainings tragen keinen kanonischen
                    // Sporttyp; dann entscheidet der Name.
                    return matchesByName(workout.sportName, kind: item.kind)
                }
                return item.kind.automaticSportTypes.contains(sportType)
            }
            // Das zuletzt in Gebrauch genommene gewinnt.
            .max { $0.inUseFrom < $1.inUseFrom }
    }

    private static func matchesByName(_ sportName: String, kind: EquipmentKind) -> Bool {
        let name = sportName.lowercased()
        switch kind {
        case .runningShoes:  return name.contains("lauf") || name.contains("run") || name.contains("jog")
        case .walkingShoes:  return name.contains("geh") || name.contains("walk") || name.contains("wander") || name.contains("hik")
        case .bike, .indoorBike: return name.contains("rad") || name.contains("bike") || name.contains("cycl")
        case .climbingShoes: return name.contains("kletter") || name.contains("boulder") || name.contains("climb")
        case .swimGear:      return name.contains("schwimm") || name.contains("swim")
        case .mat:           return name.contains("yoga") || name.contains("pilates")
        case .other:         return false
        }
    }

    /// Was ein Stueck hinter sich hat, aus den Trainings gerechnet.
    static func usage(of item: Equipment,
                      workouts: [UnifiedWorkout],
                      allEquipment: [Equipment],
                      overrides: [String: String?]) -> EquipmentUsage {
        let covered = workouts.filter {
            equipment(for: $0, in: allEquipment, overrides: overrides)?.id == item.id
        }
        return EquipmentUsage(
            workoutCount: covered.count,
            distanceKm: covered.compactMap(\.distanceKm).reduce(0, +),
            duration: covered.map(\.duration).reduce(0, +),
            lastUsed: covered.map(\.startDate).max()
        )
    }
}
