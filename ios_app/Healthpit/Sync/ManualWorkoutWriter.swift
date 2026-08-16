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

    /// Loescht ein Training in der Datenbank.
    ///
    /// Weich geloescht: Die Zeile bleibt mit `deleted_at` stehen. Ein harter
    /// Wurf haette zur Folge, dass derselbe Datensatz beim naechsten Import aus
    /// Apple Health wieder hereinkaeme — geloescht heisst „will ich nicht
    /// sehen", nicht „kenne ich nicht".
    ///
    /// Frueher stand daneben eine Liste versteckter Kennungen in den
    /// Einstellungen. Zwei Wege, dasselbe zu sagen, und nur einer galt fuer die
    /// Bruecke.
    @discardableResult
    static func delete(workoutID: WorkoutID) async -> Bool {
        guard let store = try? await HealthPitData.shared.store(),
              var workout = try? await store.workout(workoutID) ?? nil else { return false }
        workout.deletedAt = Date()
        workout.updatedAt = Date()
        do {
            try await store.update(workout)
            return true
        } catch {
            return false
        }
    }

    /// Ergaenzt ein von Hand erfasstes Training um den Puls aus Apple Health.
    ///
    /// Der eine verbliebene Griff nach HealthKit — und er gehoert hierher, in
    /// die Aufnahme: Fuer ein Zeitfenster gibt es dort Rohproben, in der
    /// Datenbank Tageswerte. Was hier herauskommt, wird gleich gespeichert und
    /// von da an aus der Datenbank gelesen wie alles andere.
    static func enriched(_ workouts: [LocalWorkout]) async -> [LocalWorkout] {
        var out: [LocalWorkout] = []
        for var workout in workouts {
            if workout.averageHeartRate == nil,
               let summary = try? await HealthKitManager.shared.heartRateSummary(
                start: workout.start, end: workout.end) {
                workout.averageHeartRate = summary.average
                workout.maxHeartRate = workout.maxHeartRate ?? summary.maximum
            }
            out.append(workout)
        }
        return out
    }

    /// Loescht alles, was ueber diesen Weg hereinkam — von Hand, GPX, TCX.
    ///
    /// Weich, wie beim einzelnen Training: Die Zeilen bleiben mit `deleted_at`
    /// stehen, damit ein erneuter Import sie nicht wieder anlegt.
    @discardableResult
    static func delete(source: LocalWorkout.Source) async -> Int {
        guard let store = try? await HealthPitData.shared.store(),
              let stored = try? await store.workouts() else { return 0 }
        var deleted = 0
        for workout in stored {
            guard let local = local(from: workout), local.source == source else { continue }
            var updated = workout
            updated.deletedAt = Date()
            updated.updatedAt = Date()
            if (try? await store.update(updated)) != nil { deleted += 1 }
        }
        return deleted
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
