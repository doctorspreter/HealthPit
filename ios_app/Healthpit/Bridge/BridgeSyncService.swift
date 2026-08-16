//
//  BridgeSyncService.swift
//  Healthpit
//
//  Schickt die aktuellen HealthKit-Werte an die Docker-Bridge.
//

import Foundation
import CryptoKit
import HealthKit

struct BridgeMetricPayload: Encodable {
    let id: String
    let category: String
    let title: String
    let value: Double
    let unit: String
    let measuredAt: Date
    let aggregation: String
    let icon: String?
    let deviceClass: String?
    let stateClass: String?
    let displayPrecision: Int?
    /// Die zentrale Kennung aus dem Katalog (`ACT_STEPS`).
    ///
    /// `id` bleibt die Sensorkennung, die die App immer geschickt hat – sie
    /// ist in Home Assistant der Speicherschluessel, und eine Aenderung wuerde
    /// dort Entitaets-IDs samt Historie kosten. Die kanonische Kennung reist
    /// daneben mit; ohne sie muesste die Integration sie aus einer Tabelle
    /// erraten.
    var metricID: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, category, title, value, unit, aggregation, icon
        case measuredAt = "measured_at"
        case deviceClass = "device_class"
        case stateClass = "state_class"
        case displayPrecision = "display_precision"
        case metricID = "metric_id"
    }
}

/// Welche Fassung des Datenmodells die App spricht.
///
/// 1 = nur die Sensorkennung, die Integration leitet die Metrik-ID ab.
/// 2 = die App schickt die kanonische Kennung selbst mit.
enum BridgeModelVersion {
    static let current = 2
}

extension BridgeMetricPayload {
    /// Ergaenzt die kanonische Kennung aus der Zuordnungstabelle.
    ///
    /// An einer Stelle statt an jedem Bauplatz: Die Nutzlast entsteht an rund
    /// zehn Stellen, und eine vergessene waere ein Wert, der in Home Assistant
    /// ohne Kennung ankommt.
    func withCanonicalID() -> BridgeMetricPayload {
        var copy = self
        copy.metricID = BridgeMetricMapping.metricID(forBridgeID: id)?.rawValue
        return copy
    }
}

struct BridgeBatchPayload: Encodable {
    let deviceID: String
    let metrics: [BridgeMetricPayload]
    /// 2 = die Werte tragen ihre kanonische Kennung selbst bei sich.
    ///
    /// Fehlt das Feld, haelt die Integration die App fuer die alte Fassung,
    /// leitet die Kennung aus einer Tabelle ab und meldet das als Hinweis.
    let modelVersion: Int

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case metrics
        case modelVersion = "model_version"
    }
}

struct BridgeHistoryPointPayload: Encodable {
    let start: Date
    let state: Double?
    let sum: Double?
    let mean: Double?
    let min: Double?
    let max: Double?
}

struct BridgeMetricHistoryBatchPayload: Encodable {
    let deviceID: String
    let category: String
    let metricID: String
    let points: [BridgeHistoryPointPayload]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case category
        case metricID = "metric_id"
        case points
    }
}

struct BridgeMetricHistoryResponse: Decodable {
    let accepted: Int
}

struct BridgeWorkoutHistoryResponse: Decodable {
    let rows: Int
}

struct BridgeHistoryImportResult: Sendable {
    let metricCount: Int
    let pointCount: Int
    let workoutCount: Int
    let workoutRows: Int
}

struct BridgeImportedWorkoutBatchPayload: Encodable {
    let deviceID: String
    let workouts: [BridgeImportedWorkoutPayload]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case workouts
    }
}

struct BridgeWorkoutReconcilePayload: Encodable {
    let deviceID: String
    let source: String
    let workoutIDs: [String]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case source
        case workoutIDs = "workout_ids"
    }
}

struct BridgeImportedWorkoutPayload: Encodable {
    let id: String
    let source: String
    /// Anzeigename, uebersetzt. Bleibt fuer aeltere Integrationsstaende drin.
    let sport: String
    /// Sprachneutrale Sportart aus der Datenbank (`RUNNING`).
    ///
    /// Ohne sie musste Home Assistant die Sportart aus dem uebersetzten Namen
    /// zurueckraten — und „Laufen", „Running" und „Outdoor Run" wurden zu drei
    /// Sportarten.
    let sportType: String
    let title: String
    let start: Date
    let end: Date
    let distanceKm: Double?
    let energyKcal: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let notes: String
    let weather: WorkoutWeather?
    let injury: WorkoutInjury?
    let route: [BridgeRoutePointPayload]
    let exercises: [LocalStrengthExercise]

    enum CodingKeys: String, CodingKey {
        case id, source, sport, title, start, end, notes, route, exercises
        case sportType = "sport_type"
        case distanceKm = "distance_km"
        case energyKcal = "energy_kcal"
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case weather, injury
    }
}

struct BridgeRoutePointPayload: Encodable {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let timestamp: Date?
    let heartRate: Double?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, elevation, timestamp
        case heartRate = "heart_rate"
    }
}

struct BridgeImportedWorkoutListResponse: Decodable {
    let workouts: [BridgeImportedWorkoutResponse]
}

struct BridgeImportedWorkoutResponse: Decodable {
    let deviceID: String?
    let workoutID: String
    let source: String
    let sport: String
    let title: String
    let startTime: Date
    let endTime: Date
    let distanceKm: Double?
    let energyKcal: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let notes: String
    let weather: WorkoutWeather?
    let injury: WorkoutInjury?
    let route: [BridgeRoutePointResponse]?
    let exercises: [BridgeStrengthExerciseResponse]?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case workoutID = "workout_id"
        case source, sport, title, notes, weather, injury, route, exercises
        case startTime = "start_time"
        case endTime = "end_time"
        case distanceKm = "distance_km"
        case energyKcal = "energy_kcal"
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
    }
}

struct BridgeStrengthExerciseResponse: Decodable {
    let exerciseID: String?
    let id: String?
    let catalogID: String?
    let name: String?
    let title: String?
    let category: String?
    let startTime: Date?
    let endTime: Date?
    let durationSeconds: Double?
    let notes: String?
    let deviceSettings: [String: String]?
    let sets: [BridgeStrengthSetResponse]?

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case id
        case catalogID = "catalog_id"
        case name, title, category, notes
        case startTime = "start_time"
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case deviceSettings = "device_settings"
        case sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try container.decodeIfPresent(String.self, forKey: .exerciseID)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        catalogID = try container.decodeIfPresent(String.self, forKey: .catalogID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        sets = try container.decodeIfPresent([BridgeStrengthSetResponse].self, forKey: .sets)
        if let strings = try? container.decodeIfPresent([String: String].self, forKey: .deviceSettings) {
            deviceSettings = strings
        } else if let doubles = try? container.decodeIfPresent([String: Double].self, forKey: .deviceSettings) {
            deviceSettings = doubles.mapValues { String(format: "%g", $0) }
        } else if let ints = try? container.decodeIfPresent([String: Int].self, forKey: .deviceSettings) {
            deviceSettings = ints.mapValues(String.init)
        } else {
            deviceSettings = nil
        }
    }
}

struct BridgeStrengthSetResponse: Decodable {
    let setID: String?
    let id: String?
    let setIndex: Int?
    let index: Int?
    let setType: String?
    let type: String?
    let reps: Double?
    let weightKg: Double?
    let rpe: Double?
    let volumeKg: Double?
    let isPersonalRecord: Bool?

    enum CodingKeys: String, CodingKey {
        case setID = "set_id"
        case id
        case setIndex = "set_index"
        case index
        case setType = "set_type"
        case type, reps, rpe
        case weightKg = "weight_kg"
        case volumeKg = "volume_kg"
        case isPersonalRecord = "is_personal_record"
    }
}

struct BridgeRoutePointResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let timestamp: Date?
    let heartRate: Double?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, elevation, timestamp
        case heartRate = "heart_rate"
    }
}

struct BridgeSessionResponse: Decodable {
    let sessionToken: String
    let tokenType: String
    let expiresAt: String
    let deviceName: String
    let username: String
    let nodeRole: String
    let serverRole: String

    enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case deviceName = "device_name"
        case nodeRole = "node_role"
        case serverRole = "server_role"
        case username
    }

    /// Only the session token is essential.
    ///
    /// The other fields are echoes of the request or descriptive extras that
    /// older bridges do not send. Refusing a perfectly good session because a
    /// device name is absent would make the app unusable against any bridge
    /// that has not been rebuilt yet.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionToken = try container.decode(String.self, forKey: .sessionToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "bearer"
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? ""
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        nodeRole = try container.decodeIfPresent(String.self, forKey: .nodeRole) ?? "slave"
        serverRole = try container.decodeIfPresent(String.self, forKey: .serverRole) ?? "master"
    }

    /// Im Webhook-Modus stellt Home Assistant keine Sitzung aus — der
    /// Long-Lived Token ist die Anmeldung. Die Oberfläche zeigt trotzdem
    /// dieselbe Rückmeldung, deshalb wird hier eine gebaut.
    init(homeAssistantToken: String, username: String) {
        sessionToken = homeAssistantToken
        tokenType = "bearer"
        expiresAt = ""
        deviceName = "HealthPit (iPhone)"
        self.username = username
        nodeRole = "slave"
        serverRole = "master"
    }
}

private struct BridgeCredentials {
    let baseURL: URL
    let username: String
    let token: String
    let deviceID: String

    /// Pfad inklusive des Präfixes der Integration.
    func apiPath(_ path: String) -> String {
        HealthPitAPI.path(path)
    }
}

enum BridgeSyncError: LocalizedError {
    case missingURL
    case missingToken
    case invalidURL
    case serverRejected(Int)
    case serverMessage(String)
    /// Meldung für den Anwender plus technischer Rest für die Detailzeile.
    case detailed(message: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingURL: return L10n.string("Bridge-Adresse fehlt.")
        case .missingToken: return L10n.string("Bridge-Token fehlt.")
        case .invalidURL: return L10n.string("Bridge-Adresse ist ungültig. Bitte mit https:// eintragen.")
        case .serverRejected(let code):
            return L10n.format("Bridge hat die Synchronisierung abgelehnt (%lld).", Int64(code))
        case .serverMessage(let message): return message
        case .detailed(let message, _): return message
        }
    }

    /// Technischer Zusatz – nur für die aufklappbare Detailzeile, nie für die
    /// Hauptmeldung.
    var technicalDetail: String? {
        switch self {
        case .detailed(_, let detail): return detail
        case .serverRejected(let code): return "HTTP \(code)"
        case .missingURL, .missingToken, .invalidURL, .serverMessage: return nil
        }
    }
}

final class BridgeSyncService {
    static let shared = BridgeSyncService()
    private static let sqliteDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private let health = HealthKitManager.shared
    private let defaults = UserDefaults.standard
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if defaults.string(forKey: BridgeSettings.deviceIDKey)?.isEmpty != false {
            defaults.set("iPhone", forKey: BridgeSettings.deviceIDKey)
        }
        if defaults.string(forKey: BridgeSettings.usernameKey)?.isEmpty != false {
            defaults.set("healthpit", forKey: BridgeSettings.usernameKey)
        }
    }

    var hasSession: Bool {
        !Self.trimmedKeychainValue(for: BridgeSettings.homeAssistantTokenKey).isEmpty
    }

    /// The bridge the stored session was issued by, empty when there is none.
    var sessionEndpointText: String {
        defaults.string(forKey: BridgeSettings.sessionEndpointKey) ?? ""
    }

    /// Resolve the bridge that would be used right now, without connecting.
    static func activeEndpoint(defaults: UserDefaults = .standard) async -> (url: URL?, isLocal: Bool) {
        do {
            let resolved = try await resolveEndpoint(defaults: defaults)
            return (resolved.url, resolved.isLocal)
        } catch {
            return (nil, false)
        }
    }

    /// Verbindet mit Home Assistant.
    ///
    /// Es gibt keinen Sitzungsaustausch mehr: der Long-Lived Token *ist* die
    /// Anmeldung, und Home Assistant erkennt an ihm, welchem Benutzer die Daten
    /// gehoeren. Geprueft wird er einmal gegen den Statusendpunkt.
    @discardableResult
    func connect() async throws -> BridgeSessionResponse {
        let token = Self.trimmedKeychainValue(for: BridgeSettings.homeAssistantTokenKey)
        guard !token.isEmpty else { throw BridgeSyncError.missingToken }

        let baseURL = try await Self.configuredBaseURL(defaults: defaults)
        var endpoint = baseURL
        endpoint.append(path: HealthPitAPI.probePath)

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw Self.homeAssistantError(from: data, statusCode: statusCode)
        }

        let status = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        defaults.set(baseURL.absoluteString, forKey: BridgeSettings.sessionEndpointKey)

        // Nach dem Verbinden gleich einmal senden. Sonst steht in Home Assistant
        // bis zum naechsten Hintergrundlauf nichts, und der Anwender haelt die
        // Verbindung fuer kaputt.
        if defaults.object(forKey: BridgeSettings.lastSyncDateKey) == nil {
            Task { try? await self.syncNow() }
        }

        return BridgeSessionResponse(
            homeAssistantToken: token,
            username: status?["user"] as? String ?? ""
        )
    }

    /// Uebersetzt die Antwortcodes, die beim Verbinden wirklich vorkommen.
    private static func homeAssistantError(from data: Data, statusCode: Int) -> BridgeSyncError {
        switch statusCode {
        case 401, 403:
            return .serverMessage(
                L10n.string("Home Assistant hat den Token abgelehnt. Bitte einen neuen Long-Lived Access Token anlegen.")
            )
        case 404:
            return .serverMessage(
                L10n.string("Home Assistant antwortet, aber die HealthPit-Integration ist dort nicht eingerichtet.")
            )
        default:
            return bridgeError(from: data, statusCode: statusCode)
        }
    }

    func disconnect() {
        KeychainStore.set("", for: BridgeSettings.homeAssistantTokenKey)
        defaults.removeObject(forKey: BridgeSettings.sessionEndpointKey)
    }

    @discardableResult
    func syncNow() async throws -> Int {
        await SyncActivity.shared.begin()
        do {
            let total = try await runSync()
            await SyncActivity.shared.succeed(count: total)
            return total
        } catch {
            await SyncActivity.shared.fail(BridgeErrorText.message(for: error))
            throw error
        }
    }

    private func runSync() async throws -> Int {
        let credentials = try await bridgeCredentials()

        await SyncActivity.shared.enter(.metrics)
        let metrics = await collectMetrics()
        try await uploadMetrics(metrics, credentials: credentials)

        await SyncActivity.shared.enter(.uploadWorkouts)
        let uploadedAppleHealthWorkouts = try await uploadAppleHealthWorkoutDelta(credentials: credentials)

        await SyncActivity.shared.enter(.reconcile)
        let deletedAppleHealthWorkouts = try await reconcileAppleHealthWorkouts(credentials: credentials)
        let uploadedWorkouts = try await uploadLocalWorkouts(credentials: credentials)

        await SyncActivity.shared.enter(.downloadWorkouts)
        let downloadedAppleHealthWorkouts = try await downloadChangedAppleHealthWorkouts(credentials: credentials)
        let downloadedWorkouts = try await downloadImportedWorkouts(credentials: credentials)

        await SyncActivity.shared.enter(.records)
        defaults.set(Date(), forKey: BridgeSettings.lastSyncDateKey)
        BackgroundSyncScheduler.schedule()
        await WorkoutRecordRefreshService.shared.refreshFromLocalCaches()
        return metrics.count
            + uploadedAppleHealthWorkouts
            + deletedAppleHealthWorkouts
            + downloadedAppleHealthWorkouts
            + uploadedWorkouts
            + downloadedWorkouts
    }

    @discardableResult
    func uploadLocalWorkouts() async throws -> Int {
        let uploaded = try await uploadLocalWorkouts(credentials: try await bridgeCredentials())
        await WorkoutRecordRefreshService.shared.refreshFromLocalCaches()
        return uploaded
    }

    @discardableResult
    func downloadImportedWorkouts() async throws -> Int {
        let downloaded = try await downloadImportedWorkouts(credentials: try await bridgeCredentials())
        await WorkoutRecordRefreshService.shared.refreshFromLocalCaches()
        return downloaded
    }

    @discardableResult
    func refreshAppleHealthWorkoutCacheFromBridge() async throws -> Int {
        try await downloadChangedAppleHealthWorkouts(credentials: try await bridgeCredentials())
    }

    @discardableResult
    func fullResyncAppleHealthWorkouts() async throws -> Int {
        guard isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) else { return 0 }
        let credentials = try await bridgeCredentials()
        let workouts = await databaseWorkouts()
        let uploadableWorkouts = visibleAppleHealthWorkouts(workouts)
        let uploaded = try await uploadAppleHealthWorkouts(uploadableWorkouts, credentials: credentials)
        _ = try await reconcileAppleHealthWorkouts(workouts: workouts, credentials: credentials)
        await HealthWorkoutCacheStore.shared.saveAllTime(workouts)
        rememberAppleHealthUploadCutoff(from: workouts)
        defaults.set(Date().addingTimeInterval(-30), forKey: BridgeSettings.appleHealthWorkoutPackageCursorKey)
        BackgroundSyncScheduler.schedule()
        await WorkoutRecordRefreshService.shared.refreshFromLocalCaches()
        return uploaded
    }

    /// One explicit, repeatable backfill. HealthKit is aggregated by hour
    /// before upload because Home Assistant stores long-term statistics at
    /// hourly resolution too.
    @discardableResult
    func importAllHistory() async throws -> BridgeHistoryImportResult {
        let credentials = try await bridgeCredentials()

        // Establish all current entities first. Historical chunks attach to
        // those entity IDs; they never create detached external statistics.
        _ = try await runSync()

        var uploadedWorkouts = 0
        if isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) {
            let workouts = await databaseWorkouts()
            let visibleWorkouts = visibleAppleHealthWorkouts(workouts)
            uploadedWorkouts = try await uploadAppleHealthWorkouts(
                visibleWorkouts,
                credentials: credentials
            )
            _ = try await reconcileAppleHealthWorkouts(
                workouts: workouts,
                credentials: credentials
            )
            await HealthWorkoutCacheStore.shared.saveAllTime(workouts)
            rememberAppleHealthUploadCutoff(from: workouts)
        }

        var metricCount = 0
        var pointCount = 0
        for metric in HealthMetric.all {
            guard isSharingEnabled(metric.id) else { continue }
            guard let history = try? await health.fetchHourlyHistory(for: metric),
                  !history.isEmpty else { continue }

            let seed: BridgeMetricPayload
            if let latest = try? await health.latestValueWithDate(for: metric) {
                seed = metric.payload(value: latest.value,
                                      measuredAt: latest.measuredAt ?? .now)
            } else {
                // A cumulative type with older data but nothing today still
                // needs an entity; zero is its correct current daily value.
                seed = metric.payload(value: 0, measuredAt: .now)
            }
            try await uploadMetrics([seed], credentials: credentials)

            let points = history.map { point in
                BridgeHistoryPointPayload(
                    start: point.date,
                    state: point.state.map { $0 * metric.healthKitScale },
                    sum: point.sum.map { $0 * metric.healthKitScale },
                    mean: point.mean.map { $0 * metric.healthKitScale },
                    min: point.minimum.map { $0 * metric.healthKitScale },
                    max: point.maximum.map { $0 * metric.healthKitScale }
                )
            }
            pointCount += try await uploadHistory(
                points,
                metricID: metric.bridgeID,
                category: metric.category.rawValue,
                credentials: credentials
            )
            metricCount += 1
        }

        let sleepResult = try await importSleepHistory(credentials: credentials)
        metricCount += sleepResult.metrics
        pointCount += sleepResult.points

        let cycleResult = try await importCycleHistory(credentials: credentials)
        metricCount += cycleResult.metrics
        pointCount += cycleResult.points

        let workoutRows = try await importWorkoutHistory(credentials: credentials)
        defaults.set(Date(), forKey: BridgeSettings.lastSyncDateKey)
        BackgroundSyncScheduler.schedule()
        await WorkoutRecordRefreshService.shared.refreshFromLocalCaches()
        return BridgeHistoryImportResult(metricCount: metricCount,
                                         pointCount: pointCount,
                                         workoutCount: uploadedWorkouts,
                                         workoutRows: workoutRows)
    }

    private func uploadMetrics(_ metrics: [BridgeMetricPayload],
                               credentials: BridgeCredentials) async throws {
        guard !metrics.isEmpty else { return }
        var endpoint = credentials.baseURL
        endpoint.append(path: credentials.apiPath("health/batch"))
        let payload = BridgeBatchPayload(deviceID: credentials.deviceID,
                                         metrics: metrics.map { $0.withCanonicalID() },
                                         modelVersion: BridgeModelVersion.current)
        var request = authorizedRequest(url: endpoint,
                                        method: "POST",
                                        credentials: credentials)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw Self.bridgeError(from: data, statusCode: statusCode)
        }
    }

    private func uploadHistory(_ points: [BridgeHistoryPointPayload],
                               metricID: String,
                               category: String,
                               credentials: BridgeCredentials) async throws -> Int {
        let chunkSize = 4_000
        var accepted = 0
        var offset = 0
        while offset < points.count {
            let end = min(offset + chunkSize, points.count)
            let chunk = Array(points[offset..<end])
            let payload = BridgeMetricHistoryBatchPayload(deviceID: credentials.deviceID,
                                                          category: category,
                                                          metricID: metricID,
                                                          points: chunk)
            var endpoint = credentials.baseURL
            endpoint.append(path: credentials.apiPath("history/metrics"))

            var attempts = 0
            while true {
                var request = authorizedRequest(url: endpoint,
                                                method: "POST",
                                                credentials: credentials)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try encoder.encode(payload)
                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(statusCode) {
                    let result = try decoder.decode(BridgeMetricHistoryResponse.self,
                                                    from: data)
                    accepted += result.accepted
                    break
                }
                // A freshly seeded entity is added asynchronously by Home
                // Assistant. Give its registry a brief moment, then retry the
                // exact same idempotent chunk.
                if statusCode == 409 && attempts < 4 {
                    attempts += 1
                    try await Task.sleep(for: .milliseconds(250))
                    continue
                }
                throw Self.bridgeError(from: data, statusCode: statusCode)
            }
            offset = end
        }
        return accepted
    }

    private func importWorkoutHistory(credentials: BridgeCredentials) async throws -> Int {
        guard isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) else { return 0 }
        var endpoint = credentials.baseURL
        endpoint.append(path: credentials.apiPath("history/workouts"))
        let request = authorizedRequest(url: endpoint,
                                        method: "POST",
                                        credentials: credentials)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw Self.bridgeError(from: data, statusCode: statusCode)
        }
        return try decoder.decode(BridgeWorkoutHistoryResponse.self, from: data).rows
    }

    private func importSleepHistory(
        credentials: BridgeCredentials
    ) async throws -> (metrics: Int, points: Int) {
        let sessions = try await health.fetchSleep(
            interval: DateInterval(start: Date(timeIntervalSince1970: 0), end: .now)
        )
        guard let latest = sessions.first else { return (0, 0) }
        let measuredAt = latest.end

        let series: [(BridgeMetricPayload, [(Date, Double)])] = [
            (.duration(id: "sleep_duration", category: .sleep, title: "Schlafdauer",
                       seconds: latest.asleep, measuredAt: measuredAt),
             sessions.map { ($0.end, $0.asleep / 3600) }),
            (.duration(id: "sleep_time_in_bed", category: .sleep, title: "Zeit im Bett",
                       seconds: latest.timeInBed, measuredAt: measuredAt),
             sessions.map { ($0.end, $0.timeInBed / 3600) }),
            (.percentage(id: "sleep_efficiency", category: .sleep, title: "Schlafeffizienz",
                         value: latest.efficiency * 100, measuredAt: measuredAt),
             sessions.map { ($0.end, $0.efficiency * 100) }),
            (.duration(id: "sleep_deep_duration", category: .sleep, title: "Tiefschlaf",
                       seconds: latest.deep, measuredAt: measuredAt),
             sessions.map { ($0.end, $0.deep / 3600) }),
            (.duration(id: "sleep_core_duration", category: .sleep, title: "Core-Schlaf",
                       seconds: latest.core, measuredAt: measuredAt),
             sessions.map { ($0.end, $0.core / 3600) }),
            (.duration(id: "sleep_rem_duration", category: .sleep, title: "REM-Schlaf",
                       seconds: latest.rem, measuredAt: measuredAt),
             sessions.map { ($0.end, $0.rem / 3600) }),
            (.duration(id: "sleep_awake_duration", category: .sleep, title: "Wachzeit",
                       seconds: latest.awake, measuredAt: measuredAt),
             sessions.map { ($0.end, $0.awake / 3600) }),
        ]

        var metricCount = 0
        var pointCount = 0
        for (seed, values) in series {
            guard isSharingEnabled(seed.id) else { continue }
            let points = Self.measurementHistoryPoints(values)
            guard !points.isEmpty else { continue }
            try await uploadMetrics([seed], credentials: credentials)
            pointCount += try await uploadHistory(points,
                                                  metricID: seed.id,
                                                  category: seed.category,
                                                  credentials: credentials)
            metricCount += 1
        }
        return (metricCount, pointCount)
    }

    private static func measurementHistoryPoints(
        _ values: [(Date, Double)]
    ) -> [BridgeHistoryPointPayload] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var buckets: [Date: [Double]] = [:]
        for (date, value) in values where value.isFinite {
            guard let hour = utc.dateInterval(of: .hour, for: date)?.start else { continue }
            buckets[hour, default: []].append(value)
        }
        return buckets.keys.sorted().compactMap { start in
            guard let bucket = buckets[start], !bucket.isEmpty else { return nil }
            return BridgeHistoryPointPayload(start: start,
                                             state: nil,
                                             sum: nil,
                                             mean: bucket.reduce(0, +) / Double(bucket.count),
                                             min: bucket.min(),
                                             max: bucket.max())
        }
    }

    private func importCycleHistory(
        credentials: BridgeCredentials
    ) async throws -> (metrics: Int, points: Int) {
        let calendar = Calendar.healthApp
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: .now)
        let days = try await health.fetchCycleDays(interval: interval)
        let cycles = HealthKitManager.cycles(from: days)
        guard !cycles.isEmpty else { return (0, 0) }

        var cycleDayValues: [(Date, Double)] = []
        var bleedingDayValues: [(Date, Double)] = []
        var averageLengthValues: [(Date, Double)] = []
        var averagePeriodValues: [(Date, Double)] = []
        var completedLengths: [Int] = []
        var completedPeriods: [Int] = []

        for cycle in cycles {
            let lastDay: Date
            if let nextStart = cycle.nextStart {
                lastDay = calendar.date(byAdding: .day, value: -1, to: nextStart)
                    ?? nextStart
            } else {
                lastDay = calendar.startOfDay(for: .now)
            }

            var date = calendar.startOfDay(for: cycle.start)
            var cycleDay = 1
            while date <= lastDay {
                cycleDayValues.append((date, Double(cycleDay)))
                guard let next = calendar.date(byAdding: .day, value: 1, to: date),
                      next > date else { break }
                date = next
                cycleDay += 1
            }

            bleedingDayValues.append((cycle.periodEnd, Double(cycle.bleedingDays)))
            if let length = cycle.lengthInDays,
               let completedAt = cycle.nextStart {
                completedLengths.append(length)
                completedPeriods.append(cycle.periodLengthInDays)
                averageLengthValues.append(
                    (completedAt,
                     Double(completedLengths.reduce(0, +)) / Double(completedLengths.count))
                )
                averagePeriodValues.append(
                    (completedAt,
                     Double(completedPeriods.reduce(0, +)) / Double(completedPeriods.count))
                )
            }
        }

        let rawSeries: [(id: String, title: String, values: [(Date, Double)])] = [
            ("cycle_current_day", "Zyklustag", cycleDayValues),
            ("cycle_average_length", "Ø Zykluslänge", averageLengthValues),
            ("cycle_average_period_length", "Ø Periodendauer", averagePeriodValues),
            ("cycle_bleeding_days", "Blutungstage", bleedingDayValues),
        ]

        var metricCount = 0
        var pointCount = 0
        for item in rawSeries {
            guard isSharingEnabled(item.id) else { continue }
            let points = Self.measurementHistoryPoints(item.values)
            guard let latest = item.values.max(by: { $0.0 < $1.0 }),
                  !points.isEmpty else { continue }
            let seed = BridgeMetricPayload.count(id: item.id,
                                                 category: .cycle,
                                                 title: item.title,
                                                 value: latest.1,
                                                 measuredAt: latest.0)
            try await uploadMetrics([seed], credentials: credentials)
            pointCount += try await uploadHistory(points,
                                                  metricID: item.id,
                                                  category: HealthCategory.cycle.rawValue,
                                                  credentials: credentials)
            metricCount += 1
        }
        return (metricCount, pointCount)
    }

    func deleteImportedWorkout(id: UUID) async throws {
        try await deleteImportedWorkout(id: id, credentials: try await bridgeCredentials())
    }

    private func collectMetrics() async -> [BridgeMetricPayload] {
        let now = Date()
        var out: [BridgeMetricPayload] = []

        for metric in HealthMetric.all {
            guard isSharingEnabled(metric.id) else { continue }
            guard let value = try? await health.currentValue(for: metric) else { continue }
            out.append(metric.payload(value: value, measuredAt: now))
        }

        if let sleep = (try? await health.fetchSleep(in: .week))?.first {
            let sleepMeasuredAt = sleep.end
            let sleepMetrics: [BridgeMetricPayload] = [
                .duration(id: "sleep_duration",
                          category: .sleep,
                          title: "Schlafdauer",
                          seconds: sleep.asleep,
                          measuredAt: sleepMeasuredAt),
                .duration(id: "sleep_time_in_bed",
                          category: .sleep,
                          title: "Zeit im Bett",
                          seconds: sleep.timeInBed,
                          measuredAt: sleepMeasuredAt),
                .percentage(id: "sleep_efficiency",
                            category: .sleep,
                            title: "Schlafeffizienz",
                            value: sleep.efficiency * 100,
                            measuredAt: sleepMeasuredAt),
                .duration(id: "sleep_deep_duration",
                          category: .sleep,
                          title: "Tiefschlaf",
                          seconds: sleep.deep,
                          measuredAt: sleepMeasuredAt),
                .duration(id: "sleep_core_duration",
                          category: .sleep,
                          title: "Core-Schlaf",
                          seconds: sleep.core,
                          measuredAt: sleepMeasuredAt),
                .duration(id: "sleep_rem_duration",
                          category: .sleep,
                          title: "REM-Schlaf",
                          seconds: sleep.rem,
                          measuredAt: sleepMeasuredAt),
                .duration(id: "sleep_awake_duration",
                          category: .sleep,
                          title: "Wachzeit",
                          seconds: sleep.awake,
                          measuredAt: sleepMeasuredAt),
            ]
            out.append(contentsOf: sleepMetrics.filter { isSharingEnabled($0.id) })
        }

        if let cycle = try? await health.fetchCycleOverview(), cycle.hasData {
            let measuredAt = cycle.currentCycle?.start ?? now
            if isSharingEnabled("cycle_current_day"),
               let day = cycle.currentCycleDay {
                out.append(.count(id: "cycle_current_day",
                                  category: .cycle,
                                  title: "Zyklustag",
                                  value: Double(day),
                                  measuredAt: now))
            }
            if isSharingEnabled("cycle_average_length"),
               let average = cycle.averageCycleLength {
                out.append(.count(id: "cycle_average_length",
                                  category: .cycle,
                                  title: "Ø Zykluslänge",
                                  value: Double(average),
                                  measuredAt: measuredAt))
            }
            if isSharingEnabled("cycle_average_period_length"),
               let period = cycle.averagePeriodLength {
                out.append(.count(id: "cycle_average_period_length",
                                  category: .cycle,
                                  title: "Ø Periodendauer",
                                  value: Double(period),
                                  measuredAt: measuredAt))
            }
            if isSharingEnabled("cycle_bleeding_days"),
               let current = cycle.currentCycle {
                out.append(.count(id: "cycle_bleeding_days",
                                  category: .cycle,
                                  title: "Blutungstage",
                                  value: Double(current.bleedingDays),
                                  measuredAt: measuredAt))
            }
        }

        // Ziele: Zielwert und Erfuellungsgrad. Beides gehoert nach drueben,
        // sonst laesst sich in Home Assistant nicht automatisieren ("Ring
        // geschlossen"), ohne das Ziel dort ein zweites Mal zu pflegen.
        for goal in ActivityGoalStore.goals(defaults: defaults) {
            let syncID = ActivityGoalStore.syncID(for: goal)
            guard isSharingEnabled(syncID) else { continue }
            guard let metric = goal.metric else { continue }
            let title = ActivityGoalStore.syncTitle(for: goal)
            out.append(BridgeMetricPayload(id: syncID,
                                           category: metric.category.rawValue,
                                           title: title,
                                           value: goal.target * metric.healthKitScale,
                                           unit: metric.unitSymbol,
                                           measuredAt: now,
                                           aggregation: "latest",
                                           icon: "mdi:target",
                                           deviceClass: nil,
                                           stateClass: "measurement",
                                           displayPrecision: metric.fractionDigits))
            let reached = await health.progressValue(for: goal, referenceDate: now)
            let progress = goal.target > 0 ? min(reached / goal.target * 100, 999) : 0
            out.append(BridgeMetricPayload(id: "\(syncID)_progress",
                                           category: metric.category.rawValue,
                                           title: L10n.format("%@ erreicht", title),
                                           value: progress,
                                           unit: "%",
                                           measuredAt: now,
                                           aggregation: "average",
                                           icon: "mdi:target",
                                           deviceClass: nil,
                                           stateClass: "measurement",
                                           displayPrecision: 0))
        }

        if isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) {
            let workoutCount = await HealthWorkoutCacheStore.shared.countAllTime()
            out.append(BridgeMetricPayload(id: "workout_count_all_time",
                                           category: HealthCategory.workouts.rawValue,
                                           title: "Workouts gesamt",
                                           value: Double(workoutCount),
                                           unit: "",
                                           measuredAt: now,
                                           aggregation: "sum",
                                           icon: "mdi:run",
                                           deviceClass: nil,
                                           stateClass: "total",
                                           displayPrecision: 0))
        }
        return out
    }

    private func isSharingEnabled(_ dataTypeID: String) -> Bool {
        BridgeDataSharingSettings.isEnabled(dataTypeID, defaults: defaults)
    }

    static func bridgeErrorMessage(from data: Data, statusCode: Int) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Die Bridge nannte den Grund "detail", die Integration "error".
        // Beides lesen, sonst bleibt vom Fehler nur die nackte Statusnummer.
        let detail = (object["detail"] as? String) ?? (object["error"] as? String) ?? ""
        guard !detail.isEmpty else {
            return nil
        }
        if detail == "Invalid bridge token" {
            return L10n.string("Bridge API Token stimmt nicht. Bitte Token in App und Bridge vergleichen.")
        }
        if detail == "Invalid bridge username" {
            return L10n.string("Bridge Benutzername stimmt nicht. Bitte Benutzername in App und Bridge vergleichen.")
        }
        if detail == "Invalid bridge OTP" {
            return L10n.string("Bridge OTP stimmt nicht. Bitte aktuellen 6-stelligen Code eingeben.")
        }
        if detail.contains("Master-to-master") {
            return L10n.string("Diese Bridge ist selbst als Master eingerichtet und kann sich nicht mit einer zweiten Bridge verbinden.")
        }
        // Alles Weitere ist der englische Klartext des Servers. Ihn an einen
        // uebersetzten Satz zu kleben ergibt einen Sprachmix, deshalb bekommt
        // der Anwender hier nur den Status – der Rest steht im Detail.
        switch statusCode {
        case 401, 403:
            return L10n.string("Die Bridge hat die Anmeldung abgelehnt. Bitte Benutzernamen, API-Token und – falls aktiv – den OTP-Code prüfen.")
        case 404:
            return L10n.string("Die Bridge kennt diesen Endpunkt nicht. Vermutlich läuft dort eine ältere Bridge-Version.")
        case 409:
            return L10n.string("Die Bridge hat die Daten als Konflikt abgelehnt.")
        case 429:
            return L10n.string("Die Bridge hat zu viele Anfragen erhalten. Bitte später erneut versuchen.")
        case 500...599:
            return L10n.format("Die Bridge meldet einen internen Fehler (%lld).", Int64(statusCode))
        default:
            return L10n.format("Die Bridge hat die Anfrage abgelehnt (%lld).", Int64(statusCode))
        }
    }

    /// Der Fehler zu einer abgelehnten Antwort: uebersetzter Satz fuer den
    /// Anwender, Serverklartext fuer die Detailzeile.
    static func bridgeError(from data: Data, statusCode: Int) -> BridgeSyncError {
        guard let message = bridgeErrorMessage(from: data, statusCode: statusCode) else {
            return .serverRejected(statusCode)
        }
        guard let detail = bridgeErrorDetail(from: data) else {
            return .serverMessage(message)
        }
        return .detailed(message: message, detail: "HTTP \(statusCode): \(detail)")
    }

    /// Der englische Klartext des Servers – nur fuer die Detailzeile.
    static func bridgeErrorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let detail = (object["detail"] as? String) ?? (object["error"] as? String) ?? ""
        return detail.isEmpty ? nil : detail
    }

    private static func trimmedKeychainValue(for key: String) -> String {
        KeychainStore.string(for: key).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func secret(fromOTPURI value: String) -> String? {
        guard let components = URLComponents(string: value),
              components.scheme == "otpauth" else {
            return nil
        }
        return components.queryItems?
            .first(where: { $0.name.lowercased() == "secret" })?
            .value?
            .uppercased()
            .filter { $0 != "=" && !$0.isWhitespace }
    }

    private func uploadLocalWorkouts(credentials: BridgeCredentials) async throws -> Int {
        guard isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) else { return 0 }
        let workouts = await LocalWorkoutStore.shared.load()
            .filter { [.manual, .gpx, .tcx].contains($0.source) }
        guard !workouts.isEmpty else { return 0 }
        let enrichedWorkouts = await enrichedForUpload(workouts)
        await ManualWorkoutWriter.saveMany(enrichedWorkouts)
        return try await uploadWorkouts(enrichedWorkouts, credentials: credentials)
    }


    /// Die Trainings, die nach Home Assistant gehen — aus der Datenbank.
    ///
    /// Frueher stand hier `health.fetchAllWorkouts()`, also HealthKit
    /// unmittelbar. Damit ging alles verloren, was die Datenbank vorher
    /// entschieden hatte: dieselbe Einheit aus drei Apps war wieder drei
    /// Trainings, die Sportart reiste als uebersetzter Anzeigename, und
    /// abgeschaltete Quellen wurden trotzdem hochgeladen.
    ///
    /// Die Datenbank ist die Quelle. Was hier herauskommt, ist genau das, was
    /// auch die Bildschirme der App zeigen.
    private func databaseWorkouts(since start: Date? = nil) async -> [WorkoutSummary] {
        let interval = start.map { DateInterval(start: $0, end: .now.addingTimeInterval(86_400)) }
        return await HealthQuery.shared.workouts(in: interval)
    }

    private func uploadAppleHealthWorkoutDelta(credentials: BridgeCredentials) async throws -> Int {
        guard isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) else { return 0 }
        let cutoff = appleHealthUploadCutoff()
        let workouts: [WorkoutSummary]
        if let cutoff {
            workouts = await databaseWorkouts(since: cutoff.addingTimeInterval(-3600))
        } else {
            let fallback = Calendar.healthApp.date(byAdding: .day, value: -7, to: .now) ?? .now
            workouts = await databaseWorkouts(since: fallback)
        }
        guard !workouts.isEmpty else { return 0 }
        let uploadableWorkouts = visibleAppleHealthWorkouts(workouts)
        guard !uploadableWorkouts.isEmpty else {
            rememberAppleHealthUploadCutoff(from: workouts)
            return 0
        }
        let uploaded = try await uploadAppleHealthWorkouts(uploadableWorkouts, credentials: credentials)
        rememberAppleHealthUploadCutoff(from: uploadableWorkouts)
        return uploaded
    }

    private func uploadAppleHealthWorkouts(_ workouts: [WorkoutSummary],
                                           credentials: BridgeCredentials) async throws -> Int {
        guard isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) else { return 0 }
        var uploaded = 0
        let batchSize = 500
        for start in stride(from: 0, to: workouts.count, by: batchSize) {
            let end = min(start + batchSize, workouts.count)
            let batch = workouts[start..<end].map(BridgeImportedWorkoutPayload.init)

            var endpoint = credentials.baseURL
            endpoint.append(path: credentials.apiPath("workouts/imports"))

            let payload = BridgeImportedWorkoutBatchPayload(deviceID: credentials.deviceID,
                                                            workouts: Array(batch))
            var request = authorizedRequest(url: endpoint, method: "POST", credentials: credentials)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                throw Self.bridgeError(from: data, statusCode: statusCode)
            }
            uploaded += batch.count
        }
        return uploaded
    }

    private func reconcileAppleHealthWorkouts(credentials: BridgeCredentials) async throws -> Int {
        let workouts = await databaseWorkouts()
        await HealthWorkoutCacheStore.shared.saveAllTime(workouts)
        return try await reconcileAppleHealthWorkouts(workouts: workouts, credentials: credentials)
    }

    private func reconcileAppleHealthWorkouts(workouts: [WorkoutSummary],
                                             credentials: BridgeCredentials) async throws -> Int {
        guard isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) else { return 0 }
        var endpoint = credentials.baseURL
        endpoint.append(path: credentials.apiPath("workouts/imports/reconcile"))

        let payload = BridgeWorkoutReconcilePayload(
            deviceID: credentials.deviceID,
            source: LocalWorkout.Source.appleHealth.rawValue,
            workoutIDs: visibleAppleHealthWorkouts(workouts).map { $0.uuid.uuidString }
        )
        var request = authorizedRequest(url: endpoint, method: "POST", credentials: credentials)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw Self.bridgeError(from: data, statusCode: statusCode)
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return body?["deleted"] as? Int ?? 0
    }

    private func downloadChangedAppleHealthWorkouts(credentials: BridgeCredentials) async throws -> Int {
        let syncStartedAt = Date()
        let cursor = appleHealthPackageCursor(defaultDate: syncStartedAt.addingTimeInterval(-7 * 24 * 3600))
        let workouts = try await downloadAppleHealthWorkouts(credentials: credentials, updatedAfter: cursor)
        guard !workouts.isEmpty else {
            defaults.set(syncStartedAt.addingTimeInterval(-30), forKey: BridgeSettings.appleHealthWorkoutPackageCursorKey)
            return 0
        }
        await HealthWorkoutCacheStore.shared.mergeAllTime(workouts)
        if isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) {
            rememberAppleHealthUploadCutoff(from: workouts)
        }
        defaults.set(syncStartedAt.addingTimeInterval(-30), forKey: BridgeSettings.appleHealthWorkoutPackageCursorKey)
        return workouts.count
    }

    private func appleHealthPackageCursor(defaultDate: Date) -> Date {
        if let cursor = defaults.object(forKey: BridgeSettings.appleHealthWorkoutPackageCursorKey) as? Date {
            return cursor
        }
        if let lastSync = defaults.object(forKey: BridgeSettings.lastSyncDateKey) as? Date {
            return lastSync
        }
        return defaultDate
    }

    private func downloadAppleHealthWorkouts(credentials: BridgeCredentials,
                                             updatedAfter: Date?) async throws -> [WorkoutSummary] {
        let pageSize = 1000
        var offset = 0
        var out: [WorkoutSummary] = []
        let updatedAfterText = updatedAfter.map(Self.sqliteDateTimeFormatter.string(from:))

        while true {
            var endpoint = credentials.baseURL
            endpoint.append(path: credentials.apiPath("workouts/imports"))
            var queryItems = [
                URLQueryItem(name: "device_id", value: credentials.deviceID),
                URLQueryItem(name: "include_apple_health", value: "true"),
                URLQueryItem(name: "source", value: LocalWorkout.Source.appleHealth.rawValue),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
            ]
            if let updatedAfterText {
                queryItems.append(URLQueryItem(name: "updated_after", value: updatedAfterText))
            }
            endpoint.append(queryItems: queryItems)

            let request = authorizedRequest(url: endpoint, method: "GET", credentials: credentials)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                throw Self.bridgeError(from: data, statusCode: statusCode)
            }
            let responseBody = try decoder.decode(BridgeImportedWorkoutListResponse.self, from: data)
            out.append(contentsOf: responseBody.workouts.compactMap(WorkoutSummary.init))
            if responseBody.workouts.count < pageSize { break }
            offset += pageSize
        }
        return out
    }

    private func appleHealthUploadCutoff() -> Date? {
        defaults.object(forKey: BridgeSettings.appleHealthWorkoutUploadCutoffKey) as? Date
    }

    private func visibleAppleHealthWorkouts(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        let hiddenIDs = Set(
            (defaults.string(forKey: BridgeSettings.hiddenHealthWorkoutIDsKey) ?? "")
                .split(separator: ",")
                .map(String.init)
        )
        return workouts.filter {
            !hiddenIDs.contains($0.uuid.uuidString)
                && !$0.isBridgeManagedAppleHealthSource
        }
    }

    private func rememberAppleHealthUploadCutoff(from workouts: [WorkoutSummary]) {
        guard let newest = workouts.map(\.start).max() else { return }
        let current = defaults.object(forKey: BridgeSettings.appleHealthWorkoutUploadCutoffKey) as? Date
        if current == nil || newest > current! {
            defaults.set(newest, forKey: BridgeSettings.appleHealthWorkoutUploadCutoffKey)
        }
    }

    private func enrichedForUpload(_ workouts: [LocalWorkout]) async -> [LocalWorkout] {
        var out: [LocalWorkout] = []
        for var workout in workouts {
            if workout.averageHeartRate == nil,
               let summary = try? await health.heartRateSummary(start: workout.start, end: workout.end) {
                workout.averageHeartRate = summary.average
                workout.maxHeartRate = workout.maxHeartRate ?? summary.maximum
            }
            out.append(workout)
        }
        return out
    }

    private func downloadImportedWorkouts(credentials: BridgeCredentials) async throws -> Int {
        var downloaded: [LocalWorkout] = []
        let bridgeManagedSources: Set<LocalWorkout.Source> = [.gympit]
        for source in [LocalWorkout.Source.manual, .gpx, .tcx, .gympit] {
            var endpoint = credentials.baseURL
            endpoint.append(path: credentials.apiPath("workouts/imports"))
            var queryItems = [
                URLQueryItem(name: "include_apple_health", value: "false"),
                URLQueryItem(name: "source", value: source.rawValue),
            ]
            // Bridge-managed imports and separate apps use their own device
            // IDs. Query them user-wide; locally uploaded files remain scoped
            // to this Healthpit iPhone.
            if !bridgeManagedSources.contains(source) {
                queryItems.append(URLQueryItem(name: "device_id", value: credentials.deviceID))
            }
            endpoint.append(queryItems: queryItems)

            let request = authorizedRequest(url: endpoint, method: "GET", credentials: credentials)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                throw Self.bridgeError(from: data, statusCode: statusCode)
            }
            let responseBody = try decoder.decode(BridgeImportedWorkoutListResponse.self, from: data)
            downloaded.append(contentsOf: responseBody.workouts.compactMap(LocalWorkout.init))
        }
        await ManualWorkoutWriter.saveMany(downloaded)

        // Frueher wurde hier alles wieder hochgeladen, was lokal lag, aber nicht
        // zurueckkam: gegenueber der Bridge war eine Luecke ein Verlust, den nur
        // dieses Geraet noch fuellen konnte.
        //
        // Mit der direkten Verbindung gehoeren GymPit-Trainings GymPit. Die App
        // hat sie nur zur Anzeige. Ihre Kopien tragen die IDs aus der
        // Bridge-Zeit, GymPit sendet dieselben Einheiten unter seinen eigenen
        // Session-IDs — die treffen sich nie, also galt jede Einheit als
        // fehlend und wurde bei jedem Sync erneut hochgeladen. Das Ergebnis
        // waren zwei Eintraege je Training, die Home Assistant nicht
        // zusammenfuehren kann, weil beide dieselbe Quelle nennen.
        return downloaded.count
    }

    /// Push a set of workouts to the bridge, keeping their own source.
    ///
    /// The bridge only rewrites the source for GymPit clients, so Healthpit may
    /// hand back workouts that originally came from GymPit.
    @discardableResult
    private func uploadWorkouts(
        _ workouts: [LocalWorkout],
        credentials: BridgeCredentials
    ) async throws -> Int {
        guard isSharingEnabled(BridgeDataTypeDescriptor.workoutsID) else { return 0 }
        guard !workouts.isEmpty else { return 0 }

        var endpoint = credentials.baseURL
        endpoint.append(path: credentials.apiPath("workouts/imports"))

        let payload = BridgeImportedWorkoutBatchPayload(
            deviceID: credentials.deviceID,
            workouts: workouts.map(BridgeImportedWorkoutPayload.init)
        )
        var request = authorizedRequest(url: endpoint, method: "POST", credentials: credentials)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw Self.bridgeError(from: data, statusCode: statusCode)
        }
        return workouts.count
    }

    private func deleteImportedWorkout(id: UUID, credentials: BridgeCredentials) async throws {
        var endpoint = credentials.baseURL
        endpoint.append(path: credentials.apiPath("workouts/imports/\(id.uuidString)"))
        endpoint.append(queryItems: [URLQueryItem(name: "device_id", value: credentials.deviceID)])

        let request = authorizedRequest(url: endpoint, method: "DELETE", credentials: credentials)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw Self.bridgeError(from: data, statusCode: statusCode)
        }
    }

    // MARK: - Duplikate

    /// Vorschlaege und bereits getroffene Entscheidungen abholen.
    func loadDuplicates() async throws -> WorkoutDuplicateReport {
        let credentials = try await bridgeCredentials()
        var endpoint = credentials.baseURL
        endpoint.append(path: credentials.apiPath("duplicates"))

        let request = authorizedRequest(url: endpoint, method: "GET", credentials: credentials)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if statusCode == 404 {
                throw BridgeSyncError.serverMessage(
                    L10n.string("Diese Home-Assistant-Integration kennt noch keine Duplikate. Bitte die Integration in HACS aktualisieren.")
                )
            }
            throw Self.bridgeError(from: data, statusCode: statusCode)
        }
        return try decoder.decode(WorkoutDuplicateReport.self, from: data)
    }

    /// Festhalten, dass zwei Aufzeichnungen dieselbe Einheit sind — oder eben nicht.
    func decideDuplicate(
        primary: String,
        linked: String,
        action: WorkoutDuplicateAction
    ) async throws {
        try await sendDuplicateDecision(
            method: "POST",
            body: ["primary": primary, "linked": linked, "action": action.rawValue]
        )
    }

    /// Eine Entscheidung zuruecknehmen; das Paar wird danach wieder vorgeschlagen.
    func undoDuplicateDecision(primary: String, linked: String) async throws {
        try await sendDuplicateDecision(
            method: "DELETE",
            body: ["primary": primary, "linked": linked]
        )
    }

    private func sendDuplicateDecision(method: String, body: [String: String]) async throws {
        let credentials = try await bridgeCredentials()
        var endpoint = credentials.baseURL
        endpoint.append(path: credentials.apiPath("duplicates/decision"))

        var request = authorizedRequest(url: endpoint, method: method, credentials: credentials)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw Self.bridgeError(from: data, statusCode: statusCode)
        }
    }

    private func bridgeCredentials() async throws -> BridgeCredentials {
        let token = Self.trimmedKeychainValue(for: BridgeSettings.homeAssistantTokenKey)
        let deviceID = defaults.string(forKey: BridgeSettings.deviceIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "iPhone"

        guard !token.isEmpty else {
            throw BridgeSyncError.serverMessage(
                L10n.string("HealthPit ist nicht verbunden. Bitte zuerst in den Einstellungen den Home-Assistant-Token eintragen.")
            )
        }
        let baseURL = try await Self.configuredBaseURL(defaults: defaults)
        // Der Benutzername wird nicht mehr mitgeschickt: Home Assistant leitet
        // ihn aus dem Token ab. Er dient nur noch der Anzeige.
        return BridgeCredentials(baseURL: baseURL,
                                 username: defaults.string(forKey: BridgeSettings.usernameKey) ?? "",
                                 token: token,
                                 deviceID: deviceID)
    }

    static func configuredBaseURL(defaults: UserDefaults = .standard) async throws -> URL {
        try await resolveEndpoint(defaults: defaults).url
    }

    /// Pick the bridge to talk to and report whether it is the local one.
    ///
    /// The local address wins when it answers. Falling back to the external
    /// address silently would leave the app talking to a different bridge than
    /// the one just configured, so callers are told which one was chosen.
    static func resolveEndpoint(
        defaults: UserDefaults = .standard
    ) async throws -> (url: URL, isLocal: Bool) {
        let localHost = defaults.string(forKey: BridgeSettings.localHostKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localPort = defaults.string(forKey: BridgeSettings.localPortKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? HealthPitAPI.defaultPort

        if !localHost.isEmpty {
            let localURL = try localBaseURL(host: localHost, port: localPort)
            let reason = await bridgeUnreachableReason(at: localURL)
            if reason == nil {
                return (localURL, true)
            }
            let external = defaults.string(forKey: BridgeSettings.baseURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if external.isEmpty {
                throw BridgeSyncError.detailed(
                    message: L10n.format("Die lokale Bridge unter %@ antwortet nicht, und es ist keine externe Adresse hinterlegt.",
                                         localURL.absoluteString),
                    detail: reason ?? "-"
                )
            }
        }

        return (try externalBaseURL(defaults: defaults), false)
    }

    private static func externalBaseURL(defaults: UserDefaults) throws -> URL {
        let baseURLText = defaults.string(forKey: BridgeSettings.baseURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !baseURLText.isEmpty else { throw BridgeSyncError.missingURL }
        guard let baseURL = URL(string: baseURLText) else { throw BridgeSyncError.invalidURL }
        guard baseURL.scheme?.lowercased() == "https" else {
            throw BridgeSyncError.serverMessage(L10n.string("Die externe Adresse muss mit https:// beginnen."))
        }
        return baseURL
    }

    private static func localBaseURL(host: String, port: String) throws -> URL {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPort = port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? HealthPitAPI.defaultPort
            : port.trimmingCharacters(in: .whitespacesAndNewlines)

        let localText: String
        if trimmedHost.contains("://") {
            guard var components = URLComponents(string: trimmedHost) else {
                throw BridgeSyncError.invalidURL
            }
            components.scheme = "http"
            if components.port == nil {
                components.port = Int(normalizedPort)
            }
            components.path = components.path == "/" ? "" : components.path
            guard let normalized = components.url?.absoluteString else {
                throw BridgeSyncError.invalidURL
            }
            localText = normalized
        } else if trimmedHost.contains(":") {
            localText = "http://\(trimmedHost)"
        } else {
            localText = "http://\(trimmedHost):\(normalizedPort)"
        }
        guard let localURL = URL(string: localText),
              localURL.scheme?.lowercased() == "http" else {
            throw BridgeSyncError.invalidURL
        }
        return localURL
    }

    /// Why a bridge could not be used, or nil when it answered properly.
    private static func bridgeUnreachableReason(at baseURL: URL) async -> String? {
        var endpoint = baseURL
        endpoint.append(path: HealthPitAPI.probePath)

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 4
        // Der Statusendpunkt ist authentifiziert, ein Probelauf ohne Token
        // waere also immer 401.
        let token = trimmedKeychainValue(for: BridgeSettings.homeAssistantTokenKey)
        guard !token.isEmpty else {
            return L10n.string("Es ist kein Home-Assistant-Token hinterlegt.")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                if statusCode == 401 || statusCode == 403 {
                    return L10n.string("Home Assistant hat den Token abgelehnt.")
                }
                if statusCode == 404 {
                    return L10n.string("Die HealthPit-Integration ist dort nicht eingerichtet.")
                }
                return L10n.format("Sie hat mit HTTP %lld geantwortet.", Int64(statusCode))
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return L10n.string("Unter dieser Adresse antwortet zwar etwas, aber keine HealthPit-Bridge.")
            }
            let healthy = object["status"] as? String == "ok"
                || object["ok"] as? Bool == true
            guard healthy else {
                return L10n.string("Die Bridge ist erreichbar, meldet sich aber nicht als betriebsbereit.")
            }
            // An older bridge does not report a role at all. Only a role that
            // is present and wrong disqualifies it.
            if let role = object["node_role"] as? String, role != "master" {
                return L10n.format("Unter dieser Adresse läuft eine Bridge in der Rolle „%@“ statt als Master.", role)
            }
            return nil
        } catch let urlError as URLError {
            return BridgeErrorText.transportFailure(urlError)
        } catch {
            return L10n.string("Die Bridge ist nicht erreichbar.")
        }
    }

    private static func isBridgeReachable(at baseURL: URL) async -> Bool {
        await bridgeUnreachableReason(at: baseURL) == nil
    }

    private func authorizedRequest(url: URL, method: String, credentials: BridgeCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        return request
    }

}

// Nicht fileprivate: die Ziele leiten ihre Kennung fuer Home Assistant aus
// derselben Regel ab und muessen dieselbe Schreibweise treffen.
extension HealthMetric {
    var bridgeID: String {
        let raw = quantityTypeIdentifier.rawValue
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
        return raw.snakeCased()
    }
}

private extension HealthMetric {
    func payload(value: Double, measuredAt: Date) -> BridgeMetricPayload {
        BridgeMetricPayload(id: bridgeID,
                            category: category.rawValue,
                            title: title,
                            value: value * healthKitScale,
                            unit: unitSymbol,
                            measuredAt: measuredAt,
                            aggregation: aggregation == .cumulativeSum ? "sum" : "average",
                            icon: mdiIcon,
                            deviceClass: deviceClass,
                            // HealthKit sends today's running total. It resets
                            // at midnight, so HA must detect the new cycle.
                            stateClass: aggregation == .cumulativeSum
                                ? "total_increasing"
                                : "measurement",
                            displayPrecision: fractionDigits)
    }

    var deviceClass: String? {
        switch unitSymbol {
        case "°C": return "temperature"
        case "%": return nil
        default: return nil
        }
    }

    var mdiIcon: String? {
        switch category {
        case .activity: return "mdi:walk"
        case .workouts: return "mdi:run"
        case .heart: return "mdi:heart-pulse"
        case .sleep: return "mdi:sleep"
        case .body: return "mdi:human"
        case .nutrition: return "mdi:food-apple"
        case .vitals: return "mdi:lungs"
        case .cycle: return "mdi:water"
        }
    }
}

private extension BridgeMetricPayload {
    static func duration(id: String,
                         category: HealthCategory,
                         title: String,
                         seconds: TimeInterval,
                         measuredAt: Date) -> BridgeMetricPayload {
        BridgeMetricPayload(id: id,
                            category: category.rawValue,
                            title: title,
                            value: seconds / 3600,
                            unit: "h",
                            measuredAt: measuredAt,
                            aggregation: "latest",
                            icon: "mdi:sleep",
                            deviceClass: "duration",
                            stateClass: "measurement",
                            displayPrecision: 1)
    }

    static func percentage(id: String,
                           category: HealthCategory,
                           title: String,
                           value: Double,
                           measuredAt: Date) -> BridgeMetricPayload {
        BridgeMetricPayload(id: id,
                            category: category.rawValue,
                            title: title,
                            value: value,
                            unit: "%",
                            measuredAt: measuredAt,
                            aggregation: "average",
                            icon: "mdi:sleep",
                            deviceClass: nil,
                            stateClass: "measurement",
                            displayPrecision: 0)
    }

    /// Ganze Tage o. Ae. – einheitenlose Zaehlwerte.
    static func count(id: String,
                      category: HealthCategory,
                      title: String,
                      value: Double,
                      measuredAt: Date) -> BridgeMetricPayload {
        BridgeMetricPayload(id: id,
                            category: category.rawValue,
                            title: title,
                            value: value,
                            unit: L10n.string("Tage"),
                            measuredAt: measuredAt,
                            aggregation: "latest",
                            icon: "mdi:water",
                            deviceClass: nil,
                            stateClass: "measurement",
                            displayPrecision: 0)
    }
}

private extension BridgeImportedWorkoutPayload {
    init(_ workout: WorkoutSummary) {
        self.init(id: workout.uuid.uuidString,
                  source: LocalWorkout.Source.appleHealth.rawValue,
                  sport: workout.activityName,
                  sportType: workout.sportType,
                  title: workout.activityName,
                  start: workout.start,
                  end: workout.end,
                  distanceKm: workout.distanceKm,
                  energyKcal: workout.energyKcal,
                  averageHeartRate: nil,
                  maxHeartRate: nil,
                  notes: "",
                  weather: workout.weather,
                  injury: workout.injury,
                  route: [],
                  exercises: [])
    }

    init(_ workout: LocalWorkout) {
        self.init(id: workout.id.uuidString,
                  source: workout.source.rawValue,
                  sport: workout.sport,
                  sportType: workout.sport.uppercased(),
                  title: workout.title,
                  start: workout.start,
                  end: workout.end,
                  distanceKm: workout.distanceKm,
                  energyKcal: workout.energyKcal,
                  averageHeartRate: workout.averageHeartRate,
                  maxHeartRate: workout.maxHeartRate,
                  notes: workout.notes,
                  weather: workout.weather,
                  injury: workout.injury,
                  route: workout.route.map(BridgeRoutePointPayload.init),
                  exercises: workout.exercises)
    }
}

private extension BridgeRoutePointPayload {
    init(_ point: LocalRoutePoint) {
        self.init(latitude: point.latitude,
                  longitude: point.longitude,
                  elevation: point.elevation,
                  timestamp: point.timestamp,
                  heartRate: point.heartRate)
    }
}

private extension LocalWorkout {
    init?(_ response: BridgeImportedWorkoutResponse) {
        guard let decodedSource = LocalWorkout.Source(rawValue: response.source) else {
            return nil
        }
        let source = response.deviceID?.localizedCaseInsensitiveContains("gympit") == true
            ? LocalWorkout.Source.gympit
            : decodedSource
        let uuid = UUID(uuidString: response.workoutID) ?? UUID.healthAppStableID(from: response.workoutID)
        self.init(id: uuid,
                  source: source,
                  sport: response.sport,
                  title: response.title,
                  start: response.startTime,
                  end: response.endTime,
                  distanceKm: response.distanceKm,
                  energyKcal: response.energyKcal,
                  averageHeartRate: response.averageHeartRate,
                  maxHeartRate: response.maxHeartRate,
                  notes: response.notes,
                  weather: response.weather,
                  injury: response.injury,
                  route: (response.route ?? []).map(LocalRoutePoint.init),
                  exercises: (response.exercises ?? []).map(LocalStrengthExercise.init))
    }
}

private extension LocalStrengthExercise {
    init(_ response: BridgeStrengthExerciseResponse) {
        let exerciseID = response.exerciseID ?? response.id ?? response.catalogID ?? response.name ?? response.title ?? UUID().uuidString
        self.init(id: exerciseID,
                  catalogID: response.catalogID ?? "",
                  name: response.name ?? response.title ?? "Übung",
                  category: response.category ?? "",
                  start: response.startTime,
                  end: response.endTime,
                  durationSeconds: response.durationSeconds,
                  notes: response.notes ?? "",
                  deviceSettings: response.deviceSettings ?? [:],
                  sets: (response.sets ?? []).map(LocalStrengthSet.init))
    }
}

private extension LocalStrengthSet {
    init(_ response: BridgeStrengthSetResponse) {
        let setIndex = response.setIndex ?? response.index ?? 0
        self.init(id: response.setID ?? response.id ?? "set-\(setIndex)",
                  index: setIndex,
                  type: response.setType ?? response.type ?? "Satz",
                  reps: response.reps,
                  weightKg: response.weightKg,
                  rpe: response.rpe,
                  volumeKg: response.volumeKg,
                  isPersonalRecord: response.isPersonalRecord ?? false)
    }
}

private extension UUID {
    static func healthAppStableID(from text: String) -> UUID {
        let digest = SHA256.hash(data: Data(text.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return bytes.withUnsafeBufferPointer { buffer in
            let value = NSUUID(uuidBytes: buffer.baseAddress!)
            return UUID(uuidString: value.uuidString)!
        }
    }
}

private extension WorkoutSummary {
    init?(_ response: BridgeImportedWorkoutResponse) {
        guard response.source == LocalWorkout.Source.appleHealth.rawValue,
              let uuid = UUID(uuidString: response.workoutID) else {
            return nil
        }
        self.init(uuid: uuid,
                  activityName: response.sport,
                  symbol: Self.symbol(for: response.sport),
                  start: response.startTime,
                  end: response.endTime,
                  duration: max(response.endTime.timeIntervalSince(response.startTime), 0),
                  energyKcal: response.energyKcal,
                  distanceKm: response.distanceKm,
                  weather: response.weather,
                  injury: response.injury)
    }

    static func symbol(for sport: String) -> String {
        let lower = sport.lowercased()
        if lower.contains("rad") || lower.contains("cycl") || lower.contains("bike") {
            return "bicycle"
        }
        if lower.contains("schwimm") || lower.contains("swim") {
            return "figure.pool.swim"
        }
        if lower.contains("kraft") || lower.contains("strength") {
            return "figure.strengthtraining.traditional"
        }
        if lower.contains("geh") || lower.contains("walk") {
            return "figure.walk"
        }
        return "figure.run"
    }
}

private extension LocalRoutePoint {
    init(_ response: BridgeRoutePointResponse) {
        self.init(latitude: response.latitude,
                  longitude: response.longitude,
                  elevation: response.elevation,
                  timestamp: response.timestamp,
                  heartRate: response.heartRate)
    }
}

private extension String {
    func snakeCased() -> String {
        unicodeScalars.reduce(into: "") { result, scalar in
            let character = Character(scalar)
            if CharacterSet.uppercaseLetters.contains(scalar) {
                if !result.isEmpty { result.append("_") }
                result.append(String(character).lowercased())
            } else if CharacterSet.alphanumerics.contains(scalar) {
                result.append(String(character).lowercased())
            } else if !result.hasSuffix("_") {
                result.append("_")
            }
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}
