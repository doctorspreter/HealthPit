//
//  HealthKitTypes.swift
//  Healthpit
//
//  Zentrale Registry ALLER HealthKit-Typen, für die wir Lesezugriff anfragen
//  (PLAN.md Abschnitt 2 + 3.3). An genau einer Stelle gebündelt, damit nichts
//  vergessen wird – "Berechtigungs-Set vollständig halten" (PLAN Abschnitt 9):
//  jeder neue Typ muss hier landen, sonst kommen stumm keine Daten.
//
//  Enthält neben den Quantity-Metriken aus HealthMetric auch die Typen, die
//  (noch) kein eigenes Modell haben: Schlaf, Stehstunden, Workouts, Blutdruck
//  als Correlation und die Stammdaten (Characteristics).
//

import HealthKit

enum HealthKitTypes {

    /// Vollständiges Set aller Typen, für die Lesezugriff angefragt wird.
    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        // 1) Alle deklarierten Mengen-Metriken (Aktivität, Herz, Körper, …).
        //    Die Registry ist die einzige Quelle – jeder neue HealthMetric wird
        //    damit automatisch mitautorisiert.
        for metric in HealthMetric.all {
            types.insert(metric.quantityType)
        }

        // 3) Category-Typen (Schlafphasen, Stehstunden).
        for identifier in categoryIdentifiers {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        // 4) Workouts inkl. GPS-Route (Route braucht EIGENE Autorisierung!).
        types.insert(HKObjectType.workoutType())
        types.insert(HKSeriesType.workoutRoute())

        // WICHTIG – Blutdruck NICHT als HKCorrelationType(.bloodPressure)
        // autorisieren (HealthKit wirft sonst beim requestAuthorization eine
        // Exception). Stattdessen sind nur die Einzelkomponenten
        // .bloodPressureSystolic / .bloodPressureDiastolic in der Registry.

        // 6) Unveränderliche Stammdaten (Geburtsdatum, Geschlecht, …).
        for identifier in characteristicIdentifiers {
            if let type = HKObjectType.characteristicType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        return types
    }

    /// Typen, die wir selbst nach Apple Health schreiben koennen.
    static var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        types.insert(HKQuantityType(.activeEnergyBurned))
        types.insert(HKQuantityType(.distanceWalkingRunning))
        types.insert(HKQuantityType(.distanceCycling))
        return types
    }

    /// Kategoriale Typen (PLAN 2.1 / 2.4).
    private static let categoryIdentifiers: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis,
        .appleStandHour,
    ]

    /// Stammdaten (PLAN 2.5).
    private static let characteristicIdentifiers: [HKCharacteristicTypeIdentifier] = [
        .dateOfBirth,
        .biologicalSex,
        .bloodType,
        .fitzpatrickSkinType,
        .wheelchairUse,
    ]
}
