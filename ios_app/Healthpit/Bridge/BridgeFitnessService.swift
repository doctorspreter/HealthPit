//
//  BridgeFitnessService.swift
//  Healthpit
//
//  Liest Fitness-Zusammenfassungen von der eigenen Bridge.
//

import Foundation

final class BridgeFitnessService {
    static let shared = BridgeFitnessService()

    private let defaults = UserDefaults.standard
    private let decoder = JSONDecoder()

    private init() {}

    func fetchHevySummary() async throws -> HevyFitnessSummary {
        let username = defaults.string(forKey: BridgeSettings.usernameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "healthpit"
        let sessionToken = KeychainStore.string(for: BridgeSettings.sessionTokenKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let apiToken = KeychainStore.string(for: BridgeSettings.apiTokenKey).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty else { throw BridgeSyncError.serverMessage("Bridge-Benutzername fehlt.") }
        guard !sessionToken.isEmpty || !apiToken.isEmpty else { throw BridgeSyncError.missingToken }
        let baseURL = try await BridgeSyncService.configuredBaseURL(defaults: defaults)

        var endpoint = baseURL
        endpoint.append(path: "v1/fitness/hevy")

        var request = URLRequest(url: endpoint)
        request.setValue(username, forHTTPHeaderField: "X-Healthpit-User")
        request.setValue("Bearer \(sessionToken.isEmpty ? apiToken : sessionToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let message = BridgeSyncService.bridgeErrorMessage(from: data, statusCode: statusCode) {
                throw BridgeSyncError.serverMessage(message)
            }
            throw BridgeSyncError.serverRejected(statusCode)
        }
        return try decoder.decode(HevyFitnessSummary.self, from: data)
    }
}
