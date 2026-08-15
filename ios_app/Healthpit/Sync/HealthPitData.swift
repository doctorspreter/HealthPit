//
//  HealthPitData.swift
//  Healthpit
//
//  Der eine Zugang zur Datenbank.
//
//  Alles, was HealthPit anzeigt, steht in dieser Datenbank. Quellen liefern
//  hinein, Bildschirme lesen heraus – und zwar ausschliesslich. Der Vorgaenger
//  hatte beides parallel: die Anzeige las Zwischenspeicher, die Datenbank
//  wurde nebenher von Stapellaeufen gefuellt. Daraus kam jedes Problem, von
//  doppelten Naechten bis zu Sicherungen, die leer blieben, waehrend der
//  Bildschirm voll war.
//

import Foundation

@MainActor
final class HealthPitData {
    static let shared = HealthPitData()

    private var opened: HealthPitStore?

    private init() {}

    /// Die Datenbank. Beim ersten Aufruf wird sie geoeffnet und die
    /// Anbieter-Zuordnungen eingespielt.
    func store() async throws -> HealthPitStore {
        if let opened { return opened }
        let store = try HealthPitStore(path: HealthPitStore.defaultDatabaseURL().path)
        try await Self.seedMappings(into: store)
        opened = store
        return store
    }

    /// Welcher Anbieter nennt welchen Wert wie. Die Tabellen kosten nichts und
    /// zeigen zugleich, was eine spaetere Anbindung braucht.
    private static func seedMappings(into store: HealthPitStore) async throws {
        for mapping in AppleHealthMapping.providerMappings() {
            try await store.upsertMapping(mapping)
        }
        for mapping in GarminMapping.mappings + HuaweiMapping.mappings + GymPitMapping.mappings {
            try await store.upsertMapping(mapping)
        }
    }

    /// Merker in der Datenbank statt in den Benutzereinstellungen: Sie
    /// verschwinden mit ihr, wenn sie geleert wird. Ein Merker, der die
    /// Datenbank ueberlebt, behauptet spaeter Dinge, die nicht mehr stimmen.
    func flag(_ key: String) async -> String? {
        guard let store = try? await store() else { return nil }
        return try? await store.migrationFlag(key)
    }

    func setFlag(_ key: String, to value: String) async {
        guard let store = try? await store() else { return }
        try? await store.setMigrationFlag(key, value: value)
    }
}
