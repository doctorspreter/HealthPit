//
//  HealthPitBootstrap.swift
//  Healthpit
//
//  Was beim Start passiert – in dieser Reihenfolge:
//
//  1. Datenbank oeffnen.
//  2. HEALTHPIT-CONVERT-2026-08: Altbestand uebernehmen, falls einer da ist.
//     Das laeuft, bevor irgendetwas anderes schreibt, und loescht nichts. Die
//     alten Ablagen bleiben liegen, bis der Umstieg bestaetigt ist.
//  3. Apple Health lesen: beim ersten Mal vollstaendig, danach nur noch das
//     Neue.
//
//  Die Reihenfolge ist kein Zufall. Der Altbestand enthaelt Dinge, die es
//  sonst nirgends gibt – manuell angelegte Trainings etwa. Kaeme Apple Health
//  zuerst, stuende der eigene Eintrag danach neben einer Kopie aus Apple
//  Health, statt als dasselbe erkannt zu werden.
//

import Foundation
import Observation

@MainActor
@Observable
final class HealthPitBootstrap {
    static let shared = HealthPitBootstrap()

    enum Phase: Equatable {
        case idle
        /// Altbestand wird uebernommen.
        case converting
        /// Apple Health wird zum ersten Mal vollstaendig gelesen.
        case importing(IngestProgress)
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Was der letzte Lauf gebracht hat – fuer die Anzeige nach dem Start.
    private(set) var lastImport: AppleHealthIngestReport?
    private(set) var lastConversion: LegacyMigrationReport?

    private var didRun = false
    private let ingest = AppleHealthIngest()

    private init() {}

    /// Beim App-Start aufrufen. Laeuft genau einmal je Sitzung.
    func run() async {
        guard !didRun else { return }
        didRun = true

        do {
            let store = try await HealthPitData.shared.store()

            // HEALTHPIT-CONVERT-2026-08
            let converter = LegacyMigration(store: store)
            let inventory = try await converter.inspect()
            if inventory.hasAnything && !inventory.alreadyMigrated {
                phase = .converting
                lastConversion = try await converter.run()
            }

            if await AppleHealthIngest.needsFullImport(store: store) {
                phase = .importing(IngestProgress())
                lastImport = try await ingest.runFullImport(store: store) { [weak self] progress in
                    self?.phase = .importing(progress)
                }
            } else {
                // Der Nachlauf braucht keine Anzeige: Er dauert Sekunden und
                // laeuft, waehrend die Startseite schon steht.
                phase = .ready
                lastImport = try await ingest.runIncremental(store: store)
            }
            phase = .ready
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Von Hand ausgeloest: alles noch einmal aus Apple Health lesen.
    @discardableResult
    func reimportEverything() async throws -> AppleHealthIngestReport {
        let store = try await HealthPitData.shared.store()
        phase = .importing(IngestProgress())
        defer { phase = .ready }
        let report = try await ingest.runFullImport(store: store) { [weak self] progress in
            self?.phase = .importing(progress)
        }
        lastImport = report
        return report
    }

    /// Nach dem Herunterziehen auf der Startseite: nur das Neue.
    @discardableResult
    func refresh() async throws -> AppleHealthIngestReport {
        let store = try await HealthPitData.shared.store()
        let report = try await ingest.runIncremental(store: store)
        lastImport = report
        return report
    }
}
