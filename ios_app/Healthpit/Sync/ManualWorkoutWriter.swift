//
//  ManualWorkoutWriter.swift
//  Healthpit
//
//  Selbst angelegte und importierte Trainings gehen in dieselbe Datenbank wie
//  alles andere – mit der Herkunft `HPT`.
//
//  Vorher lagen sie in einer eigenen JSON-Datei neben dem uebrigen Bestand.
//  Das war der Grund, warum Listen zwei Quellen zusammenfuehren mussten und
//  warum ein Training doppelt erscheinen konnte, sobald es zusaetzlich ueber
//  Apple Health hereinkam.
//
//  Uebungen, Route, Wetter und Beschwerden passen in kein Metrikfeld. Sie
//  reisen vollstaendig im `raw_payload` der Zeile mit – dafuer ist er da.
//

import Foundation

enum ManualWorkoutWriter {

    /// Schreibt ein selbst angelegtes Training in die Datenbank.
    @discardableResult
    static func save(_ workout: LocalWorkout) async -> Bool {
        do {
            let store = try await HealthPitData.shared.store()
            let pipeline = ImportPipeline(store: store)
            _ = try await pipeline.import(incoming(workout), from: .healthPit)
            return true
        } catch {
            print("Training konnte nicht gespeichert werden: \(error)")
            return false
        }
    }

    /// Mehrere auf einmal – etwa das, was die Bridge von GymPit liefert.
    static func saveMany(_ workouts: [LocalWorkout]) async {
        guard !workouts.isEmpty else { return }
        do {
            let store = try await HealthPitData.shared.store()
            let pipeline = ImportPipeline(store: store)
            for workout in workouts {
                _ = try await pipeline.import(incoming(workout),
                                              from: workout.source == .gympit ? .homeAssistant : .healthPit)
            }
        } catch {
            print("Trainings konnten nicht gespeichert werden: \(error)")
        }
    }

    static func incoming(_ workout: LocalWorkout) -> IncomingWorkout {
        var observations: [IncomingObservation] = []
        func add(_ metricID: MetricID,
                 _ value: Double?,
                 _ unit: UnitCode,
                 _ sourceMetric: String,
                 aggregation: Aggregation = .sum) {
            guard let value, value > 0 else { return }
            observations.append(IncomingObservation(sourceMetric: sourceMetric,
                                                    metricID: metricID,
                                                    value: value,
                                                    unit: unit,
                                                    startTime: workout.start,
                                                    endTime: workout.end,
                                                    aggregation: aggregation,
                                                    periodType: .workout,
                                                    originProvider: .healthPit,
                                                    metadata: ["source": "manual"]))
        }

        add("WRK_DURATION", workout.end.timeIntervalSince(workout.start), .second, "workout.duration")
        add("WRK_DISTANCE", workout.distanceKm, .kilometer, "workout.distance")
        add("NRG_ACTIVE", workout.energyKcal, .kilocalorie, "workout.active_energy")
        add("HRT_RATE_AVG", workout.averageHeartRate, .beatsPerMinute,
            "workout.heart_rate_avg", aggregation: .average)
        add("HRT_RATE_MAX", workout.maxHeartRate, .beatsPerMinute,
            "workout.heart_rate_max", aggregation: .maximum)

        return IncomingWorkout(sportType: workout.sport.uppercased(),
                               title: workout.title,
                               notes: workout.notes.isEmpty ? nil : workout.notes,
                               startTime: workout.start,
                               endTime: workout.end,
                               originProvider: originProvider(for: workout.source),
                               // Die eigene ID ist die Record-ID: Sie bleibt
                               // beim Bearbeiten gleich, deshalb findet die
                               // Wiedererkennung dieselbe Zeile wieder.
                               externalRecordID: workout.id.uuidString,
                               metadata: ["source": "manual",
                                          "local_source": workout.source.rawValue],
                               rawPayload: payload(workout),
                               observations: observations)
    }

    /// Das vollstaendige Training als JSON – Uebungen, Route und alles, was
    /// keine Metrik ist.
    static func payload(_ workout: LocalWorkout) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(workout) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Zurueck aus der Zeile – fuer Detailansichten, die Uebungen und Route
    /// brauchen.
    static func local(from stored: StoredWorkout) -> LocalWorkout? {
        guard let payload = stored.rawPayload,
              let data = payload.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocalWorkout.self, from: data)
    }

    /// GymPit-Einheiten stammen von GymPit, auch wenn sie ueber die App
    /// hereinkamen. Alles andere hat HealthPit selbst erfasst.
    private static func originProvider(for source: LocalWorkout.Source) -> ProviderCode {
        source == .gympit ? .gymPit : .healthPit
    }
}
