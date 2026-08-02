//
//  HevyFitnessCacheStore.swift
//  Healthpit
//
//  Persistenter Cache fuer Bridge-/Hevy-Fitnessdaten.
//

import Foundation

actor HevyFitnessCacheStore {
    static let shared = HevyFitnessCacheStore()

    private init() {}

    func load() async -> HevyFitnessSummary? {
        await HealthpitDatabase.shared.load(HevyFitnessSummary.self, key: "hevy.summary")
    }

    func save(_ summary: HevyFitnessSummary) async {
        await HealthpitDatabase.shared.save(summary, key: "hevy.summary")
    }
}
