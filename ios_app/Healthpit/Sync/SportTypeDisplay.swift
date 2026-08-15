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

    static func activityType(for sportType: String) -> HKWorkoutActivityType {
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
