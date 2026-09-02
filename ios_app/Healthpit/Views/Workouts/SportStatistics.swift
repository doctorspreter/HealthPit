//
//  SportStatistics.swift
//  Healthpit
//
//  Die Kennzahlen einer Sportart.
//
//  Vorher standen hier drei feste Kacheln – Trainings, Dauer und je nach
//  Sportart Volumen oder Distanz. Beim Laufen blieb davon sichtbar die Dauer
//  uebrig, obwohl Tempo, Kalorien und Puls laengst in der Datenbank stehen.
//
//  Welche Kennzahl erscheint, entscheidet nicht die Sportart, sondern was
//  tatsaechlich erfasst ist: Wer seine Laeufe ohne Pulsgurt aufzeichnet, soll
//  keine leere Pulskachel sehen. Nur die Frage, ob eine Sportart in Tempo
//  (min/km) oder in Geschwindigkeit (km/h) gelesen wird, haengt an ihr —
//  Radfahren liest niemand in Minuten je Kilometer.
//

import Foundation

struct SportStat: Identifiable {
    /// Der unuebersetzte Schluessel dient zugleich als Kennung.
    let id: String
    let labelKey: String
    let value: String

    init(_ labelKey: String, _ value: String) {
        id = labelKey
        self.labelKey = labelKey
        self.value = value
    }
}

enum SportStatistics {

    // MARK: Tempo oder Geschwindigkeit

    /// Sportarten, die in km/h statt in min/km gelesen werden.
    private static let speedSportTypes: Set<String> = [
        "CYCLING", "HAND_CYCLING", "ROWING", "SKATING", "SNOW_SPORTS",
        "CROSS_COUNTRY_SKIING", "DOWNHILL_SKIING", "SURFING", "PADDLING",
    ]

    /// Fallback fuer selbst erfasste Trainings, die keinen kanonischen
    /// Sporttyp tragen – dort steht nur der eingetippte Name.
    private static let speedSportNameFragments = [
        "rad", "bike", "cycl", "rudern", "row", "ski", "skat", "schlittschuh",
    ]

    static func readsAsSpeed(_ items: [UnifiedWorkout]) -> Bool {
        for item in items {
            if let sportType = item.health?.sportType,
               speedSportTypes.contains(sportType.uppercased()) {
                return true
            }
        }
        guard let name = items.first?.sportName.lowercased() else { return false }
        return speedSportNameFragments.contains { name.contains($0) }
    }

    // MARK: Kennzahlen

    static func stats(for items: [UnifiedWorkout]) -> [SportStat] {
        guard !items.isEmpty else { return [] }

        var out: [SportStat] = []
        let count = items.count
        let hasSeveral = count > 1

        // Immer vorhanden: wie viel und wie lange.
        out.append(SportStat("Trainings", "\(count)"))

        let durations = items.map(\.duration).filter { $0 > 0 }
        let totalDuration = durations.reduce(0, +)
        if totalDuration > 0 {
            out.append(SportStat("Dauer", formatWorkoutDuration(totalDuration)))
            if hasSeveral, !durations.isEmpty {
                out.append(SportStat("Ø Dauer",
                                     formatWorkoutDuration(totalDuration / Double(durations.count))))
                if let longest = durations.max() {
                    out.append(SportStat("Längste Einheit", formatWorkoutDuration(longest)))
                }
            }
        }

        // Strecke – nur wenn ueberhaupt eine aufgezeichnet wurde.
        let distances = items.compactMap(\.distanceKm).filter { $0 > 0 }
        let totalDistance = distances.reduce(0, +)
        if totalDistance > 0 {
            out.append(SportStat("Distanz", WorkoutUnits.distance(km: totalDistance)))
            if hasSeveral, !distances.isEmpty {
                out.append(SportStat("Ø Distanz",
                                     WorkoutUnits.distance(km: totalDistance / Double(distances.count))))
                if let longest = distances.max() {
                    out.append(SportStat("Längste Strecke", WorkoutUnits.distance(km: longest)))
                }
            }

            // Tempo braucht beides: Strecke und die Zeit, die dazugehoert.
            let pacedDuration = items
                .filter { ($0.distanceKm ?? 0) > 0 }
                .map(\.duration)
                .reduce(0, +)
            if pacedDuration > 0 {
                if readsAsSpeed(items) {
                    out.append(SportStat("Ø Geschwindigkeit",
                                         WorkoutUnits.speed(kmh: totalDistance / (pacedDuration / 3600))))
                } else if let pace = WorkoutUnits.pace(km: totalDistance, duration: pacedDuration) {
                    out.append(SportStat("Ø Tempo", pace))
                }
            }
        }

        // Energie.
        let energies = items.compactMap(\.energyKcal).filter { $0 > 0 }
        if !energies.isEmpty {
            let total = energies.reduce(0, +)
            out.append(SportStat("Kalorien", "\(Int(total.rounded())) kcal"))
            if hasSeveral {
                out.append(SportStat("Ø Kalorien",
                                     "\(Int((total / Double(energies.count)).rounded())) kcal"))
            }
        }

        // Puls – liegt nur bei selbst erfassten Trainings vor.
        let averageRates = items.compactMap(\.averageHeartRate).filter { $0 > 0 }
        if !averageRates.isEmpty {
            let mean = averageRates.reduce(0, +) / Double(averageRates.count)
            out.append(SportStat("Ø Puls", "\(Int(mean.rounded())) bpm"))
        }
        if let peak = items.compactMap(\.maxHeartRate).filter({ $0 > 0 }).max() {
            out.append(SportStat("Max. Puls", "\(Int(peak.rounded())) bpm"))
        }

        // Krafttraining.
        let volumes = items.compactMap(\.volumeKg).filter { $0 > 0 }
        if !volumes.isEmpty {
            out.append(SportStat("Volumen", WorkoutUnits.weight(kg: volumes.reduce(0, +))))
        }
        let sets = items.compactMap(\.setCount).reduce(0, +)
        if sets > 0 {
            out.append(SportStat("Sätze", "\(sets)"))
        }
        let reps = items.compactMap(\.repCount).reduce(0, +)
        if reps > 0 {
            out.append(SportStat("Wiederholungen", "\(reps)"))
        }
        let exercises = Set(items.flatMap(\.strengthExercises).map(\.name))
        if exercises.count > 1 {
            out.append(SportStat("Übungen", "\(exercises.count)"))
        }

        return out
    }
}
