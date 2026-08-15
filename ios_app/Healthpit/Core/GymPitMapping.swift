//
//  GymPitMapping.swift
//  HealthPitCore
//
//  GymPit ist die Schwester-App: Krafttraining mit Uebungen, Saetzen und
//  Wiederholungen – Dinge, die Apple Health so nicht kennt.
//
//  Heute kommen GymPit-Trainings auf zwei Wegen an: ueber die Bridge und als
//  Kopie in Apple Health. Beide Wege sind hier abgebildet, damit derselbe
//  Datensatz nicht zweimal landet.
//
//  Wenn GymPit spaeter direkt im neuen Format liefert, aendert sich an
//  HealthPit nichts ausser diesen Zeilen: Der Vertrag steht in
//  `GymPitIngestContract`, und die Zuordnung laeuft ueber dieselbe
//  Import-Reihenfolge wie bei jedem anderen Anbieter.
//

import Foundation

enum GymPitMapping {

    /// Was GymPit heute schickt (Feldnamen der Bridge-Nutzlast) und was es
    /// fachlich bedeutet.
    static let mappings: [ProviderMetricMapping] = [
        .init(provider: .gymPit, sourceMetric: "workout.duration", metricID: "WRK_DURATION",
              sourceUnit: .second, canonicalUnit: .second),
        .init(provider: .gymPit, sourceMetric: "workout.distance_km", metricID: "WRK_DISTANCE",
              sourceUnit: .kilometer, canonicalUnit: .meter),
        .init(provider: .gymPit, sourceMetric: "workout.energy_kcal", metricID: "WRK_ENERGY",
              sourceUnit: .kilocalorie, canonicalUnit: .kilocalorie),
        .init(provider: .gymPit, sourceMetric: "workout.average_heart_rate", metricID: "HRT_RATE",
              sourceUnit: .beatsPerMinute, canonicalUnit: .beatsPerMinute),
        .init(provider: .gymPit, sourceMetric: "workout.max_heart_rate", metricID: "HRT_MAX_RATE",
              sourceUnit: .beatsPerMinute, canonicalUnit: .beatsPerMinute),
        // Krafttraining aufgeschluesselt: jede Groesse eine eigene Entitaet.
        // Als JSON-Klumpen liess sich daran nichts ablesen – kein Verlauf des
        // Arbeitsgewichts, keine Volumensumme, kein Vergleich zwischen
        // Anbietern. Die Struktur bleibt trotzdem erhalten: Uebung und Satz
        // haengen ueber `session_id` am selben Training.
        .init(provider: .gymPit, sourceMetric: "exercise.name", metricID: "WRK_EXERCISE",
              canWrite: false),
        .init(provider: .gymPit, sourceMetric: "set.reps", metricID: "WRK_SET_REPS",
              sourceUnit: .count, canonicalUnit: .count, canWrite: false),
        .init(provider: .gymPit, sourceMetric: "set.weight_kg", metricID: "WRK_SET_WEIGHT",
              sourceUnit: .kilogram, canonicalUnit: .kilogram, canWrite: false),
        .init(provider: .gymPit, sourceMetric: "set.volume_kg", metricID: "WRK_SET_VOLUME",
              sourceUnit: .kilogram, canonicalUnit: .kilogram, canWrite: false),
        .init(provider: .gymPit, sourceMetric: "set.rpe", metricID: "WRK_SET_RPE",
              sourceUnit: .score, canonicalUnit: .score, canWrite: false),
        .init(provider: .gymPit, sourceMetric: "set.type", metricID: "WRK_SET_TYPE",
              canWrite: false),
        .init(provider: .gymPit, sourceMetric: "set.is_personal_record",
              metricID: "WRK_SET_IS_PERSONAL_RECORD", canWrite: false),
        // Geraeteeinstellungen: was man beim naechsten Mal wieder braucht.
        .init(provider: .gymPit, sourceMetric: "equipment.machine_name",
              metricID: "WRK_EQUIPMENT_NAME", canWrite: false),
        .init(provider: .gymPit, sourceMetric: "equipment.seat",
              metricID: "WRK_EQUIPMENT_SEAT", canWrite: false),
        .init(provider: .gymPit, sourceMetric: "equipment.backrest",
              metricID: "WRK_EQUIPMENT_BACKREST", canWrite: false),
        .init(provider: .gymPit, sourceMetric: "equipment.handle",
              metricID: "WRK_EQUIPMENT_HANDLE", canWrite: false),
        .init(provider: .gymPit, sourceMetric: "equipment.range",
              metricID: "WRK_EQUIPMENT_RANGE", canWrite: false),
        .init(provider: .gymPit, sourceMetric: "workout.route", metricID: "WRK_ROUTE"),
        .init(provider: .gymPit, sourceMetric: "workout.weather", metricID: "WRK_WEATHER"),
        .init(provider: .gymPit, sourceMetric: "workout.injury", metricID: "WRK_INJURY")
    ]

    /// Bundle-Kennungen, an denen ein GymPit-Datensatz in Apple Health
    /// erkennbar ist.
    static let appleHealthSourceHints = ["gympit", "de.tauwe.gympit"]

    /// Stammt dieser Apple-Health-Datensatz urspruenglich aus GymPit?
    ///
    /// Bisher erkannte die App das an einem Textvergleich auf den Quellnamen
    /// („enthaelt gympit“). Das bleibt der Notnagel – sauber ist die
    /// External-ID unten.
    static func isGymPitSource(bundleIdentifier: String?, sourceName: String?) -> Bool {
        let haystack = [bundleIdentifier, sourceName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return appleHealthSourceHints.contains { haystack.contains($0) }
    }
}

/// Was HealthPit von GymPit braucht, damit ein Training genau einmal ankommt.
///
/// Der Vertrag ist bewusst klein: Er verlangt nichts, was GymPit nicht ohnehin
/// hat. Solange GymPit die Workout-ID stabil haelt, laesst sich alles Weitere
/// nachtraeglich zuordnen – auch rueckwirkend fuer Trainings, die heute schon
/// ueber Apple Health hereingekommen sind.
enum GymPitIngestContract {

    /// Pflicht: die ID, unter der GymPit das Training selbst fuehrt.
    ///
    /// Sie wird zur `external_record_id` der Referenz. Damit ist ein zweiter
    /// Upload desselben Trainings ein Update und kein neues Training.
    static let externalRecordIDField = "workout_id"

    /// Empfohlen: dieselbe ID auch in Apple Health hinterlegen
    /// (`HKMetadataKeyExternalUUID`).
    ///
    /// Dann erkennt HealthPit die Apple-Kopie als denselben Datensatz –
    /// Stufe 3 der Import-Reihenfolge, ohne Heuristik.
    static let appleHealthExternalIDKey = "HKMetadataKeyExternalUUID"

    /// Optional, sobald GymPit das neue Modell spricht: die HealthPit
    /// Observation ID bzw. Workout ID, die HealthPit beim Export mitgibt.
    static let syncIdentifierField = "sync_identifier"

    /// Sportart als neutraler Code (`STRENGTH_TRAINING`), nicht als
    /// Anzeigename – der darf sich uebersetzen lassen, ohne dass die
    /// Zuordnung kippt.
    static let sportTypeField = "sport_type"

    /// Baut aus einer GymPit-Nutzlast das, was der Kern erwartet.
    ///
    /// Absichtlich tolerant: Fehlt die Sportart, wird das Training trotzdem
    /// uebernommen. Fehlt die Workout-ID, greift die normale
    /// Deduplizierung – dann eben ohne Beweis.
    static func makeIncomingWorkout(workoutID: String?,
                                    sportType: String?,
                                    title: String?,
                                    start: Date,
                                    end: Date,
                                    syncIdentifier: String? = nil,
                                    sourceAppID: String? = "de.tauwe.gympit",
                                    isDeleted: Bool = false,
                                    rawPayload: String? = nil,
                                    observations: [IncomingObservation] = []) -> IncomingWorkout {
        IncomingWorkout(sportType: sportType?.uppercased() ?? "STRENGTH_TRAINING",
                        title: title,
                        startTime: start,
                        endTime: end,
                        originProvider: .gymPit,
                        externalRecordID: workoutID,
                        syncIdentifier: syncIdentifier,
                        sourceAppID: sourceAppID,
                        isDeleted: isDeleted,
                        metadata: ["contract": "gympit_v1"],
                        rawPayload: rawPayload,
                        observations: observations)
    }
}
