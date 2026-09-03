//
//  HealthEpisode.swift
//  HealthPitCore
//
//  Tagebuch fuer wiederkehrende Beschwerdebilder: Kopfschmerz, Migraene,
//  Panikattacke und was sonst in Episoden auftritt.
//
//  Eine Episode ist mehr als ein Messwert: sie hat Beginn und Ende, eine
//  Staerke, eine Auspraegung, Begleiterscheinungen, moegliche Ausloeser und
//  die Frage, ob ein Medikament geholfen hat. Genau das braucht ein Arzt,
//  wenn er ein Muster erkennen soll.
//
//  In der Datenbank stehen englische Codes, wie ueberall. Die Auswahllisten
//  haengen am Beschwerdebild: bei einer Panikattacke nach Aura zu fragen
//  waere Unfug, und eine lange Liste, in der das meiste nicht passt, fuellt
//  niemand aus.
//

import Foundation

/// Das Beschwerdebild, zu dem Tagebuch gefuehrt wird.
enum HealthCondition: String, CaseIterable, Identifiable, Sendable, Codable {
    case headache = "HEADACHE"
    case migraine = "MIGRAINE"
    case panicAttack = "PANIC_ATTACK"
    case dizziness = "DIZZINESS"
    case nausea = "NAUSEA"
    case asthma = "ASTHMA"
    case allergy = "ALLERGY"
    case backPain = "BACK_PAIN"
    case stomach = "STOMACH"
    case fever = "FEVER"
    case other = "OTHER"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .headache:    return "Kopfschmerz"
        case .migraine:    return "Migräne"
        case .panicAttack: return "Panikattacke"
        case .dizziness:   return "Schwindel"
        case .nausea:      return "Übelkeit"
        case .asthma:      return "Asthma"
        case .allergy:     return "Allergie"
        case .backPain:    return "Rückenschmerz"
        case .stomach:     return "Magen-Darm"
        case .fever:       return "Fieber"
        case .other:       return "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .headache, .migraine: return "brain.head.profile"
        case .panicAttack:         return "wind"
        case .dizziness:           return "arrow.triangle.2.circlepath"
        case .nausea, .stomach:    return "pills"
        case .asthma:              return "lungs"
        case .allergy:             return "allergens"
        case .backPain:            return "figure.walk"
        case .fever:               return "thermometer.medium"
        case .other:               return "cross.case"
        }
    }

    /// Auspraegungen. Leer heisst: bei diesem Bild gibt es keine sinnvolle.
    var subtypes: [EpisodeSubtype] {
        switch self {
        case .headache, .migraine:
            return [.tension, .migraineWithAura, .migraineWithoutAura, .cluster, .sinus]
        case .panicAttack:
            return [.suddenOnset, .situational, .nocturnal]
        case .asthma:
            return [.exerciseInduced, .allergic, .nocturnal]
        default:
            return []
        }
    }

    var symptoms: [EpisodeSymptom] {
        switch self {
        case .headache, .migraine:
            return [.nausea, .vomiting, .lightSensitivity, .soundSensitivity,
                    .aura, .neckTension, .visualDisturbance]
        case .panicAttack:
            return [.palpitations, .shortnessOfBreath, .sweating, .trembling,
                    .dizziness, .chestTightness, .fearOfLosingControl, .numbness]
        case .asthma:
            return [.shortnessOfBreath, .cough, .wheezing, .chestTightness]
        case .allergy:
            return [.sneezing, .itching, .rash, .shortnessOfBreath, .swelling]
        case .stomach, .nausea:
            return [.nausea, .vomiting, .cramps, .diarrhoea, .bloating]
        default:
            return [.nausea, .dizziness, .fatigue, .cramps]
        }
    }

    var triggers: [EpisodeTrigger] {
        switch self {
        case .headache, .migraine:
            return [.stress, .lackOfSleep, .dehydration, .weather, .screenTime,
                    .alcohol, .caffeine, .food, .hormonal, .exertion]
        case .panicAttack:
            return [.stress, .lackOfSleep, .caffeine, .crowds, .confinedSpace,
                    .conflict, .unknown]
        case .asthma:
            return [.exertion, .coldAir, .pollen, .dust, .animals, .infection]
        case .allergy:
            return [.pollen, .dust, .animals, .food]
        default:
            return [.stress, .lackOfSleep, .food, .weather, .exertion, .unknown]
        }
    }
}

enum EpisodeSubtype: String, CaseIterable, Identifiable, Sendable, Codable {
    case tension = "TENSION"
    case migraineWithAura = "MIGRAINE_WITH_AURA"
    case migraineWithoutAura = "MIGRAINE_WITHOUT_AURA"
    case cluster = "CLUSTER"
    case sinus = "SINUS"
    case suddenOnset = "SUDDEN_ONSET"
    case situational = "SITUATIONAL"
    case nocturnal = "NOCTURNAL"
    case exerciseInduced = "EXERCISE_INDUCED"
    case allergic = "ALLERGIC"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .tension:              return "Spannungskopfschmerz"
        case .migraineWithAura:     return "Migräne mit Aura"
        case .migraineWithoutAura:  return "Migräne ohne Aura"
        case .cluster:              return "Cluster"
        case .sinus:                return "Nasennebenhöhlen"
        case .suddenOnset:          return "Aus heiterem Himmel"
        case .situational:          return "Situationsgebunden"
        case .nocturnal:            return "Nachts"
        case .exerciseInduced:      return "Durch Anstrengung"
        case .allergic:             return "Allergisch"
        }
    }
}

enum EpisodeSymptom: String, CaseIterable, Identifiable, Sendable, Codable {
    case nausea = "NAUSEA"
    case vomiting = "VOMITING"
    case lightSensitivity = "LIGHT_SENSITIVITY"
    case soundSensitivity = "SOUND_SENSITIVITY"
    case aura = "AURA"
    case neckTension = "NECK_TENSION"
    case visualDisturbance = "VISUAL_DISTURBANCE"
    case palpitations = "PALPITATIONS"
    case shortnessOfBreath = "SHORTNESS_OF_BREATH"
    case sweating = "SWEATING"
    case trembling = "TREMBLING"
    case dizziness = "DIZZINESS"
    case chestTightness = "CHEST_TIGHTNESS"
    case fearOfLosingControl = "FEAR_OF_LOSING_CONTROL"
    case numbness = "NUMBNESS"
    case cough = "COUGH"
    case wheezing = "WHEEZING"
    case sneezing = "SNEEZING"
    case itching = "ITCHING"
    case rash = "RASH"
    case swelling = "SWELLING"
    case cramps = "CRAMPS"
    case diarrhoea = "DIARRHOEA"
    case bloating = "BLOATING"
    case fatigue = "FATIGUE"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .nausea:              return "Übelkeit"
        case .vomiting:            return "Erbrechen"
        case .lightSensitivity:    return "Lichtempfindlich"
        case .soundSensitivity:    return "Lärmempfindlich"
        case .aura:                return "Aura"
        case .neckTension:         return "Nackenverspannung"
        case .visualDisturbance:   return "Sehstörung"
        case .palpitations:        return "Herzrasen"
        case .shortnessOfBreath:   return "Atemnot"
        case .sweating:            return "Schwitzen"
        case .trembling:           return "Zittern"
        case .dizziness:           return "Schwindel"
        case .chestTightness:      return "Engegefühl in der Brust"
        case .fearOfLosingControl: return "Kontrollverlust-Angst"
        case .numbness:            return "Taubheitsgefühl"
        case .cough:               return "Husten"
        case .wheezing:            return "Pfeifende Atmung"
        case .sneezing:            return "Niesreiz"
        case .itching:             return "Juckreiz"
        case .rash:                return "Hautausschlag"
        case .swelling:            return "Schwellung"
        case .cramps:              return "Krämpfe"
        case .diarrhoea:           return "Durchfall"
        case .bloating:            return "Blähungen"
        case .fatigue:             return "Erschöpfung"
        }
    }
}

enum EpisodeTrigger: String, CaseIterable, Identifiable, Sendable, Codable {
    case stress = "STRESS"
    case lackOfSleep = "LACK_OF_SLEEP"
    case dehydration = "DEHYDRATION"
    case weather = "WEATHER"
    case screenTime = "SCREEN_TIME"
    case alcohol = "ALCOHOL"
    case caffeine = "CAFFEINE"
    case food = "FOOD"
    case hormonal = "HORMONAL"
    case exertion = "EXERTION"
    case crowds = "CROWDS"
    case confinedSpace = "CONFINED_SPACE"
    case conflict = "CONFLICT"
    case coldAir = "COLD_AIR"
    case pollen = "POLLEN"
    case dust = "DUST"
    case animals = "ANIMALS"
    case infection = "INFECTION"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .stress:        return "Stress"
        case .lackOfSleep:   return "Schlafmangel"
        case .dehydration:   return "Zu wenig getrunken"
        case .weather:       return "Wetter"
        case .screenTime:    return "Bildschirmzeit"
        case .alcohol:       return "Alkohol"
        case .caffeine:      return "Koffein"
        case .food:          return "Essen"
        case .hormonal:      return "Hormonell"
        case .exertion:      return "Anstrengung"
        case .crowds:        return "Menschenmenge"
        case .confinedSpace: return "Enge Räume"
        case .conflict:      return "Konflikt"
        case .coldAir:       return "Kalte Luft"
        case .pollen:        return "Pollen"
        case .dust:          return "Staub"
        case .animals:       return "Tiere"
        case .infection:     return "Infekt"
        case .unknown:       return "Unbekannt"
        }
    }
}

/// Ein Eintrag im Tagebuch.
struct HealthEpisode: Identifiable, Hashable, Sendable {
    let id: String
    var condition: HealthCondition
    var subtype: EpisodeSubtype?
    /// 0…10, null heisst „nicht angegeben".
    var severity: Int
    var startedAt: Date
    var endedAt: Date?
    var symptoms: Set<EpisodeSymptom>
    var triggers: Set<EpisodeTrigger>
    var medication: String
    /// Ob das Medikament geholfen hat. `nil`, solange nichts gesagt wurde —
    /// das ist etwas anderes als „hat nicht geholfen".
    var medicationHelped: Bool?
    var notes: String

    nonisolated init(id: String = UUID().uuidString,
                     condition: HealthCondition = .headache,
                     subtype: EpisodeSubtype? = nil,
                     severity: Int = 0,
                     startedAt: Date = .now,
                     endedAt: Date? = nil,
                     symptoms: Set<EpisodeSymptom> = [],
                     triggers: Set<EpisodeTrigger> = [],
                     medication: String = "",
                     medicationHelped: Bool? = nil,
                     notes: String = "") {
        self.id = id
        self.condition = condition
        self.subtype = subtype
        self.severity = severity
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.symptoms = symptoms
        self.triggers = triggers
        self.medication = medication
        self.medicationHelped = medicationHelped
        self.notes = notes
    }

    nonisolated var isOngoing: Bool { endedAt == nil }

    /// Dauer, solange die Episode vorbei ist.
    nonisolated var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }
}
