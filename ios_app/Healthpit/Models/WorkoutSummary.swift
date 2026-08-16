//
//  WorkoutSummary.swift
//  Healthpit
//
//  Aufbereitetes Workout (PLAN.md 2.2) – losgelöst von HKWorkout, damit die
//  UI ein schlankes, Sendable-Value-Type bekommt.
//

import Foundation

struct WorkoutSummary: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// UUID des zugrunde liegenden HKWorkout (für Detail-/Routen-Abfrage).
    let uuid: UUID
    /// ID des Workouts in der Ursprungs-App, sofern diese sie in HealthKit hinterlegt.
    /// GymPit verwendet hier dieselbe Workout-ID wie beim Bridge-Upload.
    let externalWorkoutID: String?
    /// Anzeigename des Trainingstyps (z. B. "Laufen"). Uebersetzt — taugt zur
    /// Anzeige, niemals als Kennung.
    let activityName: String
    /// Sprachneutrale Sportart, wie die Datenbank sie fuehrt (`RUNNING`).
    ///
    /// Der Anzeigename wandert mit der Sprache: Dieselbe Einheit heisst
    /// „Laufen" oder „Running", je nachdem, wie die App gerade eingestellt
    /// ist. Wer darauf gruppiert, zerlegt eine Sportart in mehrere. Hier steht
    /// die Kennung, die sich nicht bewegt.
    let sportType: String
    /// SF-Symbol passend zum Typ.
    let symbol: String
    /// Ursprungs-App in Apple Health, z. B. "Fitness", "Gympit" oder "Apple Watch".
    let sourceName: String?
    let start: Date
    let end: Date
    let duration: TimeInterval
    /// Verbrannte Energie in kcal (falls verfügbar).
    let energyKcal: Double?
    /// Distanz in Kilometern (falls verfügbar).
    let distanceKm: Double?
    let weather: WorkoutWeather?
    let injury: WorkoutInjury?

    init(id: UUID = UUID(),
         uuid: UUID,
         externalWorkoutID: String? = nil,
         activityName: String,
         sportType: String = "OTHER",
         symbol: String,
         sourceName: String? = nil,
         start: Date,
         end: Date,
         duration: TimeInterval,
         energyKcal: Double?,
         distanceKm: Double?,
         weather: WorkoutWeather? = nil,
         injury: WorkoutInjury? = nil) {
        self.id = id
        self.uuid = uuid
        self.externalWorkoutID = externalWorkoutID
        self.activityName = activityName
        self.sportType = sportType
        self.symbol = symbol
        self.sourceName = sourceName
        self.start = start
        self.end = end
        self.duration = duration
        self.energyKcal = energyKcal
        self.distanceKm = distanceKm
        self.weather = weather
        self.injury = injury
    }

    nonisolated var externalWorkoutUUID: UUID? {
        externalWorkoutID.flatMap(UUID.init(uuidString:))
    }

    nonisolated var isBridgeManagedAppleHealthSource: Bool {
        guard let sourceName else { return false }
        let normalized = sourceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("gympit")
    }

    nonisolated var isEligibleForLocalHealthCache: Bool {
        guard isBridgeManagedAppleHealthSource else { return true }
        let normalizedSource = sourceName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalizedSource.contains("gympit") && externalWorkoutUUID != nil
    }
}
