//
//  ObservationBackup.swift
//  HealthPitCore
//
//  Die Sicherung enthielt bisher nur die lokalen Trainings – Schlaf,
//  Messwerte und alles, was ueber die Anbieter hereinkam, fehlte darin.
//  Wer daraus wiederherstellte, bekam ein Drittel seiner Daten zurueck.
//
//  Jetzt kommt der Beobachtungsspeicher dazu, und zwar nach Herkunft
//  getrennt: was in HealthPit selbst entstanden ist, steht fuer sich; jede
//  Erweiterung, von der Daten da sind, bekommt einen eigenen Abschnitt. So
//  laesst sich sehen – und spaeter auch einzeln zurueckholen –, was woher
//  stammt.
//

import Foundation

/// Alles, was von einer Herkunft stammt.
struct ProviderBackupSection: Codable, Sendable, Identifiable {
    var id: String { provider.rawValue }

    let provider: ProviderCode
    /// Klartextname zum Zeitpunkt der Sicherung. Die Datei soll auch dann
    /// lesbar sein, wenn der Code den Anbieter nicht mehr kennt.
    let providerName: String
    /// In HealthPit selbst entstanden – manuell erfasst oder aus einer Datei
    /// importiert, ohne fremdes System dahinter.
    let isHealthPitOwn: Bool

    var observations: [HealthObservation]
    var workouts: [StoredWorkout]
    /// Unter welchen fremden IDs diese Daten dort liegen. Ohne sie wuerde
    /// nach dem Zurueckspielen jeder Anbieter alles neu anlegen.
    var references: [ExternalReference]

    var isEmpty: Bool { observations.isEmpty && workouts.isEmpty }

    var summary: String {
        "\(providerName): \(observations.count) · \(workouts.count)"
    }
}

struct HealthPitObservationBackup: Codable, Sendable {
    /// 1 = flache Listen. 2 = nach Herkunft gegliedert.
    static let currentVersion = 2

    var version: Int
    var exportedAt: Date
    /// Ein Abschnitt je Herkunft, HealthPit zuerst.
    var sections: [ProviderBackupSection]
    var sourcePolicies: [MetricSourcePolicy]
    /// Metriken, die es nur bei diesem Nutzer gibt (herstellereigene Scores,
    /// provisorisch angelegte). Der eingebaute Katalog kommt aus dem Code.
    var customMetrics: [MetricDefinition]

    init(sections: [ProviderBackupSection],
         sourcePolicies: [MetricSourcePolicy],
         customMetrics: [MetricDefinition],
         exportedAt: Date = Date()) {
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.sections = sections
        self.sourcePolicies = sourcePolicies
        self.customMetrics = customMetrics
    }

    // Ueber alle Abschnitte hinweg – fuer alles, was die Herkunft nicht
    // interessiert.
    var observations: [HealthObservation] { sections.flatMap(\.observations) }
    var workouts: [StoredWorkout] { sections.flatMap(\.workouts) }
    var references: [ExternalReference] { sections.flatMap(\.references) }

    /// Nur das, was in HealthPit selbst eingetragen wurde.
    var healthPitOwn: ProviderBackupSection? {
        sections.first { $0.isHealthPitOwn }
    }

    /// Die Erweiterungen, von denen Daten vorliegen.
    var extensions: [ProviderBackupSection] {
        sections.filter { !$0.isHealthPitOwn }
    }

    var isEmpty: Bool { sections.allSatisfy(\.isEmpty) }

    var summary: String {
        sections.map(\.summary).joined(separator: " · ")
    }

    /// Nur die Abschnitte der genannten Herkuenfte.
    ///
    /// Damit laesst sich eine Sicherung anlegen, die ausschliesslich die
    /// eigenen Eintraege enthaelt oder die einer einzelnen Erweiterung – etwa
    /// um sie einzeln weiterzugeben oder gezielt zurueckzuholen.
    func filtered(to providers: Set<ProviderCode>) -> HealthPitObservationBackup {
        var copy = self
        copy.sections = sections.filter { providers.contains($0.provider) }
        // Die Freigaben je Metrik gehoeren zu den Quellen, die noch drin sind.
        copy.sourcePolicies = sourcePolicies.filter { providers.contains($0.provider) }
        return copy
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case version, exportedAt, sections, sourcePolicies, customMetrics
        // Format 1.
        case observations, workouts, references
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        sourcePolicies = try container.decodeIfPresent([MetricSourcePolicy].self,
                                                        forKey: .sourcePolicies) ?? []
        customMetrics = try container.decodeIfPresent([MetricDefinition].self,
                                                      forKey: .customMetrics) ?? []

        if let sections = try container.decodeIfPresent([ProviderBackupSection].self, forKey: .sections) {
            self.sections = sections
            return
        }

        // Eine Sicherung im ersten Format: flache Listen. Sie wird beim Lesen
        // nach Herkunft aufgeteilt, damit alles Weitere nur eine Form kennt.
        let observations = try container.decodeIfPresent([HealthObservation].self,
                                                          forKey: .observations) ?? []
        let workouts = try container.decodeIfPresent([StoredWorkout].self, forKey: .workouts) ?? []
        let references = try container.decodeIfPresent([ExternalReference].self,
                                                        forKey: .references) ?? []
        sections = ObservationBackupService.group(observations: observations,
                                                  workouts: workouts,
                                                  references: references)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(sections, forKey: .sections)
        try container.encode(sourcePolicies, forKey: .sourcePolicies)
        try container.encode(customMetrics, forKey: .customMetrics)
    }
}

/// Eine Zeile der Uebersicht in der Datensicherung.
struct BackupInventoryEntry: Sendable, Identifiable, Equatable {
    var id: String { provider.rawValue }

    let provider: ProviderCode
    let providerName: String
    let isHealthPitOwn: Bool
    let observations: Int
    let workouts: Int

    var total: Int { observations + workouts }
}

enum ObservationBackupService {

    /// Was von wem vorliegt – ohne den Bestand zu laden.
    ///
    /// Die Datensicherung zeigt das an, bevor exportiert wird: sonst waere
    /// „Daten exportieren" eine Wundertuete, und niemand koennte sehen, ob
    /// eine Erweiterung ueberhaupt etwas geliefert hat.
    static func inventory(store: HealthPitStore,
                          userID: String = HealthPitUser.local) async throws -> [BackupInventoryEntry] {
        let registry = ProviderRegistry()
        let observations = try await store.observationCountsByOrigin(userID: userID)
        let workouts = try await store.workoutCountsByOrigin(userID: userID)

        let entries = Set(observations.keys).union(workouts.keys).map { provider in
            BackupInventoryEntry(provider: provider,
                                 providerName: registry.definition(provider)?.name ?? provider.rawValue,
                                 isHealthPitOwn: provider == .healthPit,
                                 observations: observations[provider] ?? 0,
                                 workouts: workouts[provider] ?? 0)
        }
        return entries.sorted { lhs, rhs in
            if lhs.isHealthPitOwn != rhs.isHealthPitOwn { return lhs.isHealthPitOwn }
            return lhs.provider < rhs.provider
        }
    }

    /// Alles aus dem Beobachtungsspeicher einsammeln, nach Herkunft geordnet.
    ///
    /// Geloeschte Zeilen kommen mit: Sie sind der Beleg dafuer, dass etwas
    /// bewusst weg ist. Ohne sie wuerde ein Anbieter sie beim naechsten Sync
    /// wieder anlegen.
    static func makeBackup(store: HealthPitStore,
                           userID: String = HealthPitUser.local) async throws -> HealthPitObservationBackup {
        let builtIn = Set(MetricCatalog.builtIn.map(\.metricID))
        let registry = await store.metricRegistry
        return HealthPitObservationBackup(
            sections: group(observations: try await store.allObservations(userID: userID,
                                                                          includeDeleted: true),
                            workouts: try await store.workouts(userID: userID, includeDeleted: true),
                            references: try await store.allReferences(userID: userID)),
            sourcePolicies: try await store.sourcePolicies(userID: userID),
            customMetrics: registry.all.filter { !builtIn.contains($0.metricID) }
        )
    }

    /// Teilt den Bestand nach dem Erzeuger auf.
    ///
    /// Massgeblich ist `origin_provider`, nicht der Lieferweg: Ein
    /// Garmin-Wert, der ueber Apple Health hereinkam, gehoert zu Garmin.
    /// Sonst stuende er unter Apple Health und waere nach einem
    /// Anbieterwechsel nicht wiederzufinden.
    static func group(observations: [HealthObservation],
                      workouts: [StoredWorkout],
                      references: [ExternalReference]) -> [ProviderBackupSection] {
        let registry = ProviderRegistry()
        var providers = Set(observations.map(\.originProvider))
        providers.formUnion(workouts.map(\.originProvider))

        // Referenzen haengen an den Entitaeten, nicht am Anbieter der
        // Referenz – sie reisen mit dem Abschnitt ihres Erzeugers.
        var sectionByEntity: [String: ProviderCode] = [:]
        for observation in observations {
            sectionByEntity[observation.observationID.rawValue] = observation.originProvider
        }
        for workout in workouts {
            sectionByEntity[workout.workoutID.rawValue] = workout.originProvider
        }

        var referencesByProvider: [ProviderCode: [ExternalReference]] = [:]
        for reference in references {
            guard let provider = sectionByEntity[reference.entityID] else { continue }
            referencesByProvider[provider, default: []].append(reference)
        }

        let sections = providers.map { provider in
            ProviderBackupSection(
                provider: provider,
                providerName: registry.definition(provider)?.name ?? provider.rawValue,
                isHealthPitOwn: provider == .healthPit,
                observations: observations.filter { $0.originProvider == provider },
                workouts: workouts.filter { $0.originProvider == provider },
                references: referencesByProvider[provider] ?? []
            )
        }

        // HealthPit zuerst, danach die Erweiterungen alphabetisch – eine
        // Sicherung soll immer gleich aussehen.
        return sections.sorted { lhs, rhs in
            if lhs.isHealthPitOwn != rhs.isHealthPitOwn { return lhs.isHealthPitOwn }
            return lhs.provider < rhs.provider
        }
    }

    struct RestoreReport: Sendable, Equatable {
        var observations = 0
        var workouts = 0
        var references = 0
        var policies = 0
        var metrics = 0
        /// Was je Herkunft zurueckkam.
        var byProvider: [String: Int] = [:]
    }

    /// Zurueckspielen, ohne etwas zu ueberschreiben, das neuer ist.
    ///
    /// Eine Sicherung ist ein Sicherheitsnetz. Eine aeltere Datei darf nicht
    /// loeschen, was seitdem dazugekommen ist – deshalb wird ergaenzt und nur
    /// dort ersetzt, wo die Sicherung den neueren Stand hat.
    ///
    /// `only` beschraenkt auf einzelne Herkuenfte, etwa um nur die in
    /// HealthPit erfassten Daten zurueckzuholen.
    @discardableResult
    static func restore(_ backup: HealthPitObservationBackup,
                        into store: HealthPitStore,
                        only providers: Set<ProviderCode>? = nil) async throws -> RestoreReport {
        var report = RestoreReport()

        for metric in backup.customMetrics where await store.metricDefinition(metric.metricID) == nil {
            try await store.registerMetric(metric)
            report.metrics += 1
        }

        for section in backup.sections {
            if let providers, !providers.contains(section.provider) { continue }
            var restoredHere = 0

            for workout in section.workouts {
                if let existing = try await store.workout(workout.workoutID) {
                    guard workout.updatedAt > existing.updatedAt else { continue }
                    try await store.update(workout)
                } else {
                    try await store.insert(workout)
                }
                report.workouts += 1
                restoredHere += 1
            }

            for observation in section.observations {
                if let existing = try await store.observation(observation.observationID) {
                    guard observation.updatedAt > existing.updatedAt else { continue }
                    try await store.update(observation)
                } else {
                    try await store.insert(observation)
                }
                report.observations += 1
                restoredHere += 1
            }

            for reference in section.references {
                var restored = reference
                // Die Zeilennummer stammt aus der alten Datenbank und sagt
                // hier nichts; der Store findet die Zeile ueber die
                // Unique-Regeln.
                restored.id = nil
                try await store.upsert(restored)
                report.references += 1
            }

            report.byProvider[section.provider.rawValue] = restoredHere
        }

        for policy in backup.sourcePolicies {
            try await store.setSourcePolicy(metricID: policy.metricID,
                                            provider: policy.provider,
                                            sourceAppID: policy.sourceAppID,
                                            enabled: policy.enabled,
                                            userID: policy.userID)
            report.policies += 1
        }

        return report
    }
}
