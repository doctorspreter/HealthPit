//
//  HealthDataSourceSettings.swift
//  Healthpit
//
//  Lokale Einstellungen fuer HealthKit-Quellen und Apple-Health-Exporte.
//

import Foundation

struct HealthSourceDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let dataPointIDs: Set<String>

    nonisolated var isHealthpit: Bool {
        id == Bundle.main.bundleIdentifier
    }
}

struct HealthDataPointDescriptor: Identifiable, Hashable, Sendable {
    static let workoutsID = "healthpit.workouts"
    static let sleepID = "healthpit.sleep"
    static let cycleID = "healthpit.cycle"

    let id: String
    let title: String
    let systemImage: String
    let section: String

    nonisolated static let all: [HealthDataPointDescriptor] = {
        let metrics = HealthMetric.all.map {
            HealthDataPointDescriptor(id: $0.id,
                                      title: $0.title,
                                      systemImage: $0.systemImage,
                                      section: $0.category.title)
        }
        return metrics + [
            HealthDataPointDescriptor(id: workoutsID,
                                      title: "Trainings",
                                      systemImage: "figure.run",
                                      section: "Trainings"),
            HealthDataPointDescriptor(id: sleepID,
                                      title: "Schlaf",
                                      systemImage: "bed.double.fill",
                                      section: "Schlaf"),
            HealthDataPointDescriptor(id: cycleID,
                                      title: "Zyklus",
                                      systemImage: "drop.circle.fill",
                                      section: "Zyklus")
        ]
    }()

    nonisolated static func descriptor(id: String) -> HealthDataPointDescriptor? {
        all.first { $0.id == id }
    }
}

enum HealthDataSourceSettings {
    nonisolated static let disabledSourcesKey = "healthData.disabledSources"
    nonisolated static let disabledDataPointsKey = "healthData.disabledSourceDataPoints"
    nonisolated static let writeWorkoutsKey = "healthData.write.workouts"
    nonisolated static let writeActiveEnergyKey = "healthData.write.activeEnergy"
    nonisolated static let writeWalkingDistanceKey = "healthData.write.walkingDistance"
    nonisolated static let writeCyclingDistanceKey = "healthData.write.cyclingDistance"

    nonisolated static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            writeWorkoutsKey: true,
            writeActiveEnergyKey: true,
            writeWalkingDistanceKey: true,
            writeCyclingDistanceKey: true
        ])
    }

    nonisolated static func isSourceEnabled(_ sourceID: String,
                                             defaults: UserDefaults = .standard) -> Bool {
        !stringSet(forKey: disabledSourcesKey, defaults: defaults).contains(sourceID)
    }

    nonisolated static func setSource(_ sourceID: String,
                                      enabled: Bool,
                                      defaults: UserDefaults = .standard) {
        var disabled = stringSet(forKey: disabledSourcesKey, defaults: defaults)
        if enabled { disabled.remove(sourceID) } else { disabled.insert(sourceID) }
        setStringSet(disabled, forKey: disabledSourcesKey, defaults: defaults)
    }

    nonisolated static func isDataPointEnabled(_ dataPointID: String,
                                                for sourceID: String,
                                                defaults: UserDefaults = .standard) -> Bool {
        isSourceEnabled(sourceID, defaults: defaults)
            && !stringSet(forKey: disabledDataPointsKey, defaults: defaults)
                .contains(dataPointKey(sourceID: sourceID, dataPointID: dataPointID))
    }

    nonisolated static func setDataPoint(_ dataPointID: String,
                                         for sourceID: String,
                                         enabled: Bool,
                                         defaults: UserDefaults = .standard) {
        var disabled = stringSet(forKey: disabledDataPointsKey, defaults: defaults)
        let key = dataPointKey(sourceID: sourceID, dataPointID: dataPointID)
        if enabled { disabled.remove(key) } else { disabled.insert(key) }
        setStringSet(disabled, forKey: disabledDataPointsKey, defaults: defaults)
    }

    nonisolated static func isWritingEnabled(forKey key: String,
                                              defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }

    nonisolated private static func dataPointKey(sourceID: String, dataPointID: String) -> String {
        "\(sourceID)|\(dataPointID)"
    }

    nonisolated private static func stringSet(forKey key: String,
                                              defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    nonisolated private static func setStringSet(_ values: Set<String>,
                                                 forKey key: String,
                                                 defaults: UserDefaults) {
        defaults.set(values.sorted(), forKey: key)
    }
}
