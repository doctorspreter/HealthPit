//
//  WorkoutDetail.swift
//  Healthpit
//
//  Detaildaten zu einem einzelnen Workout: alle verfügbaren Kennzahlen
//  (Distanz, Kalorien, Puls Ø/Max/Min, Schritte …) plus die GPS-Route.
//

import Foundation

/// Eine einzelne Kennzahl eines Workouts (Label + fertig formatierter Wert).
struct WorkoutStat: Identifiable, Hashable, Sendable {
    let id = UUID()
    let label: String
    let value: String
    let systemImage: String

    /// Die Bridge schickt den Namen einer Kennzahl mit. Aeltere Fassungen
    /// schicken ihn deutsch („Dauer"), neuere englisch („Duration") — was die
    /// App verlaesst, soll englisch sein.
    ///
    /// Beides muss ankommen: eine Integration, die noch nicht aktualisiert
    /// wurde, darf hier nicht ploetzlich unuebersetzte Texte erzeugen. Der
    /// eingehende Name wird deshalb erst auf den deutschen Schluessel
    /// zurueckgefuehrt und dann uebersetzt.
    var localizedLabel: String { L10n.string(WorkoutStat.key(for: label)) }

    /// Bridge-Name → Schluessel. Was nicht in der Tabelle steht, geht
    /// unveraendert durch: ein unbekannter Name ist besser als ein leerer.
    nonisolated static func key(for label: String) -> String {
        englishToKey[label.normalizedWorkoutStatLabel] ?? label
    }

    /// Kennzahlen, die die App ohnehin selbst anzeigt und die aus der Bridge
    /// nicht ein zweites Mal danebengestellt werden sollen.
    ///
    /// Deutsch und englisch, weil eine noch nicht aktualisierte Integration
    /// die alten Namen schickt. Stand die Liste in den Views, lief sie
    /// auseinander — sie stand dort zweimal.
    nonisolated static func isDuplicateOfLocalField(_ label: String) -> Bool {
        let normalized = label.normalizedWorkoutStatLabel
        if duplicateLabels.contains(normalized) { return true }
        if normalized.hasPrefix("distanz") || normalized.hasPrefix("distance") { return true }
        if normalized.contains("kalorien") || normalized.contains("calories") { return true }
        if normalized.contains("puls") || normalized.contains("heart rate") { return true }
        return false
    }

    /// Zusaetzlich auszublenden, sobald die App das Tempo selbst zeigt.
    nonisolated static let paceLabels: Set<String> = [
        "ø geschwindigkeit", "ø pace", "ø tempo",
        "pace", "speed", "avg. pace", "avg. speed",
    ]

    private nonisolated static let duplicateLabels: Set<String> = [
        "dauer", "duration", "total time",
        "distanz", "distance", "total distance",
        "kalorien", "calories",
        "aktive kalorien", "active calories",
        "ø puls", "ø heart rate", "avg. heart rate", "avg heart rate",
        "max puls", "max. heart rate", "max heart rate",
        "min puls", "min. heart rate", "min heart rate",
    ]

    private nonisolated static let englishToKey: [String: String] = [
        "duration":     "Dauer",
        "distance":     "Distanz",
        "total distance": "Gesamtstrecke",
        "calories":     "Kalorien",
        "volume":       "Volumen",
        "sets":         "Sätze",
        "exercises":    "Übungen",
        "exercise":     "Übung",
        "pace":         "Ø Tempo",
        "speed":        "Ø Geschwindigkeit",
        "sessions":     "Trainings",
        "total time":   "Dauer",
    ]
}

/// Ein Routenpunkt (Sendable-Ersatz für CLLocationCoordinate2D, das nicht
/// Sendable ist – wird in der View in CLLocationCoordinate2D umgewandelt).
struct RoutePoint: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let timestamp: Date?
}

struct WorkoutSplit: Identifiable, Hashable, Sendable {
    let id: Int
    let distanceKm: Double
    let duration: TimeInterval
    let averageSpeedKmh: Double
    let paceSecondsPerKm: TimeInterval
    let start: Date?
    let end: Date?
}

struct HeartRatePoint: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date: Date
    let bpm: Double
}

struct HeartRateSummary: Hashable, Sendable {
    let average: Double
    let minimum: Double
    let maximum: Double
    let samples: [HeartRatePoint]
}

/// Gesamtes Detailpaket für die Workout-Detailansicht.
struct WorkoutDetail: Sendable {
    let stats: [WorkoutStat]
    let route: [RoutePoint]
    let splits: [WorkoutSplit]
    let heartRate: HeartRateSummary?
}

extension String {
    var normalizedWorkoutStatLabel: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "Ø", with: "ø")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
