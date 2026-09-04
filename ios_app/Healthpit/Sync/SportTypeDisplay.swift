//
//  SportTypeDisplay.swift
//  Healthpit
//
//  Die Sportart steht in der Datenbank sprachneutral („RUNNING“), damit
//  Garmin und GymPit darauf abbilden koennen. Fuer die Anzeige wird daraus
//  wieder der HealthKit-Typ – dessen Namen und Symbole pflegt die App schon
//  laenger, und die sollen sich nicht doppeln.
//

import Foundation
import HealthKit

enum SportTypeDisplay {

    /// Der kanonische Code zu einem eingetippten oder angezeigten Sportnamen.
    ///
    /// Selbst erfasste Trainings trugen bisher den deutschen Namen als
    /// Sporttyp — aus „Laufen" wurde „LAUFEN", weil die vorhandene
    /// Normalisierung nur Schreibweise glaettet und nicht uebersetzt. In der
    /// Datenbank steht damit Sprache statt Code, und alles, was auf „RUNNING"
    /// prueft, geht daran vorbei: die Ausruestung waere einem manuell
    /// erfassten Lauf nie zugefallen.
    static func canonicalCode(for sport: String) -> String {
        let normalized = sport
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "OTHER" }

        for (fragments, code) in nameFragments where fragments.contains(where: normalized.contains) {
            return code
        }
        // Unbekanntes bleibt, wie es kam – nur in der Schreibweise geglaettet.
        return normalized.uppercased()
            .map { ($0.isLetter || $0.isNumber) ? $0 : "_" }
            .reduce(into: "") { if $1 == "_", $0.last == "_" { return }; $0.append($1) }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Deutsch und Englisch, weil beides im Bestand steht.
    private static let nameFragments: [(Set<String>, String)] = [
        (["laufen", "lauf", "running", "run", "jogging", "jog"], "RUNNING"),
        (["gehen", "walking", "walk", "spazier"], "WALKING"),
        (["wandern", "hiking", "hike"], "HIKING"),
        (["radfahren", "rad", "cycling", "bike", "biking"], "CYCLING"),
        (["schwimmen", "swimming", "swim"], "SWIMMING"),
        (["krafttraining", "kraft", "strength"], "STRENGTH_TRAINING"),
        (["bouldern", "klettern", "climbing", "bouldering"], "CLIMBING"),
        (["squash"], "SQUASH"),
        (["yoga"], "YOGA"),
        (["pilates"], "PILATES"),
        (["rudern", "rowing"], "ROWING"),
        (["sonstiges", "other"], "OTHER"),
    ]

    /// Der HealthKit-Typ zu einem Sportcode.
    ///
    /// Trifft der Code keinen Fall, wird er einmal ueber `canonicalCode`
    /// geschickt: Altbestaende tragen den deutschen Namen als Sporttyp
    /// („LAUFEN"), und ohne diesen zweiten Versuch stuende auf der Kachel
    /// „Sonstiges" statt „Laufen". Erst der Fehlschlag loest das aus — ein
    /// gueltiger Code wie HAND_CYCLING soll nicht ueber die Namenserkennung
    /// zu CYCLING eingedampft werden.
    static func activityType(for sportType: String) -> HKWorkoutActivityType {
        let direkt = knownActivityType(sportType)
        if direkt != .other { return direkt }
        let kanonisch = canonicalCode(for: sportType)
        return kanonisch == sportType.uppercased() ? .other : knownActivityType(kanonisch)
    }

    private static func knownActivityType(_ sportType: String) -> HKWorkoutActivityType {
        switch sportType.uppercased() {
        case "RUNNING":               return .running
        case "WALKING":               return .walking
        case "HIKING":                return .hiking
        case "CYCLING":               return .cycling
        case "SWIMMING":              return .swimming
        case "STRENGTH_TRAINING":     return .traditionalStrengthTraining
        case "HIIT":                  return .highIntensityIntervalTraining
        case "YOGA":                  return .yoga
        case "ROWING":                return .rowing
        case "ELLIPTICAL":            return .elliptical
        case "STAIR_CLIMBING":        return .stairClimbing
        case "CORE_TRAINING":         return .coreTraining
        case "PILATES":               return .pilates
        case "DANCE":                 return .dance
        case "BOXING":                return .boxing
        case "CLIMBING":              return .climbing
        case "TENNIS":                return .tennis
        case "SOCCER":                return .soccer
        case "BASKETBALL":            return .basketball
        case "GOLF":                  return .golf
        case "SKATING":               return .skatingSports
        case "SNOW_SPORTS":           return .snowSports
        case "CROSS_COUNTRY_SKIING":  return .crossCountrySkiing
        case "PADDLE_SPORTS":         return .paddleSports
        case "SURFING":               return .surfingSports
        case "MARTIAL_ARTS":          return .martialArts
        case "MIND_AND_BODY":         return .mindAndBody
        case "COOLDOWN":              return .cooldown
        case "RECOVERY":              return .preparationAndRecovery
        default:                      return .other
        }
    }

    static func describe(_ sportType: String) -> (name: String, symbol: String) {
        let activity = activityType(for: sportType)
        return (activity.displayName, activity.symbol)
    }
}
