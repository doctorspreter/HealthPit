//
//  AppleHealthIngest+Workouts.swift
//  Healthpit
//
//  Trainings aus Apple Health in die Datenbank.
//
//  Auch hier gilt die Trennung von Erzeuger und Lieferweg: Ein Training, das
//  Garmin oder GymPit nach Apple Health gelegt hat, wird unter seinem Erzeuger
//  gefuehrt und behaelt dessen Record-ID. Nur so findet es beim naechsten Mal
//  zu sich selbst zurueck, statt ein zweites Mal angelegt zu werden.
//

import Foundation
import HealthKit

extension AppleHealthIngest {

    func importWorkouts(from start: Date,
                        to end: Date,
                        pipeline: ImportPipeline) async throws -> Int {
        let workouts = try await workoutSamples(from: start, to: end)
        var imported = 0
        for workout in workouts {
            _ = try await pipeline.import(Self.incoming(workout), from: .appleHealth)
            imported += 1
        }
        return imported
    }

    static func incoming(_ workout: HKWorkout) -> IncomingWorkout {
        let bundleID = workout.sourceRevision.source.bundleIdentifier
        let provider = ProviderRegistry.provider(forBundleID: bundleID,
                                                 sourceName: workout.sourceRevision.source.name,
                                                 ownBundleID: Bundle.main.bundleIdentifier)
        // Die ID des urspruenglichen Erzeugers, falls die schreibende App sie
        // durchgereicht hat. Damit erkennt HealthPit dasselbe Training wieder,
        // wenn es spaeter direkt von der Quelle kommt.
        let externalUUID = workout.metadata?[HKMetadataKeyExternalUUID] as? String
        let syncIdentifier = workout.metadata?[HKMetadataKeySyncIdentifier] as? String

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
                                                    startTime: workout.startDate,
                                                    endTime: workout.endDate,
                                                    aggregation: aggregation,
                                                    periodType: .workout,
                                                    originProvider: provider,
                                                    sourceAppID: bundleID,
                                                    metadata: ["source": "apple_health"]))
        }

        add("WRK_DURATION", workout.duration, .second, "workout.duration")
        add("WRK_DISTANCE",
            workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: HKUnit.meter())
                ?? workout.statistics(for: HKQuantityType(.distanceCycling))?
                .sumQuantity()?.doubleValue(for: HKUnit.meter()),
            .meter, "workout.distance")
        add("NRG_ACTIVE",
            workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()),
            .kilocalorie, "workout.active_energy")
        add("HRT_RATE_AVG",
            workout.statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
            .beatsPerMinute, "workout.heart_rate_avg", aggregation: .average)
        add("HRT_RATE_MAX",
            workout.statistics(for: HKQuantityType(.heartRate))?
                .maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
            .beatsPerMinute, "workout.heart_rate_max", aggregation: .maximum)

        return IncomingWorkout(sportType: sportType(workout.workoutActivityType),
                               title: workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String,
                               startTime: workout.startDate,
                               endTime: workout.endDate,
                               originProvider: provider,
                               originExternalID: externalUUID,
                               externalRecordID: workout.uuid.uuidString,
                               syncIdentifier: syncIdentifier,
                               sourceAppID: bundleID,
                               sourceDeviceModel: workout.device?.model,
                               metadata: ["source": "apple_health"],
                               observations: observations)
    }

    private func workoutSamples(from start: Date, to end: Date) async throws -> [HKWorkout] {
        let store = HKHealthStore()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    /// HealthKit-Sportart als sprachneutrale Kennung.
    ///
    /// Grossbuchstaben, Englisch – dieselbe Schreibweise wie bei den Metriken,
    /// damit Garmin und GymPit spaeter darauf abbilden koennen.
    static func sportType(_ activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .running:             return "RUNNING"
        case .walking:             return "WALKING"
        case .hiking:              return "HIKING"
        case .cycling:             return "CYCLING"
        case .swimming:            return "SWIMMING"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining: return "STRENGTH_TRAINING"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga:                return "YOGA"
        case .rowing:              return "ROWING"
        case .elliptical:          return "ELLIPTICAL"
        case .stairClimbing:       return "STAIR_CLIMBING"
        case .coreTraining:        return "CORE_TRAINING"
        case .pilates:             return "PILATES"
        case .dance:               return "DANCE"
        case .boxing:              return "BOXING"
        case .climbing:            return "CLIMBING"
        case .tennis:              return "TENNIS"
        case .soccer:              return "SOCCER"
        case .basketball:          return "BASKETBALL"
        case .golf:                return "GOLF"
        case .skatingSports:       return "SKATING"
        case .snowSports,
             .downhillSkiing:      return "SNOW_SPORTS"
        case .crossCountrySkiing:  return "CROSS_COUNTRY_SKIING"
        case .paddleSports:        return "PADDLE_SPORTS"
        case .surfingSports:       return "SURFING"
        case .martialArts:         return "MARTIAL_ARTS"
        case .mindAndBody:         return "MIND_AND_BODY"
        case .cooldown:            return "COOLDOWN"
        case .preparationAndRecovery: return "RECOVERY"
        default:                   return "OTHER"
        }
    }
}
