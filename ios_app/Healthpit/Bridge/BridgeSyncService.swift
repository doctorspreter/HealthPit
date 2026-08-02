//
//  BridgeSyncService.swift
//  Healthpit
//
//  Schickt die aktuellen HealthKit-Werte an die Docker-Bridge.
//

import CryptoKit
import Foundation
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

    enum CodingKeys: String, CodingKey {
        case id, category, title, value, unit, aggregation, icon
        case measuredAt = "measured_at"
        case deviceClass = "device_class"
        case stateClass = "state_class"
    }
}

struct BridgeBatchPayload: Encodable {
    let deviceID: String
    let metrics: [BridgeMetricPayload]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case metrics
    }
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
    let sport: String
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
}

private struct BridgeSessionCreatePayload: Encodable {
    let username: String
    let apiToken: String
    let otpCode: String
    let deviceName: String
    let scope: String
    let clientApp: String
    let nodeRole: String
    let expiresDays: Int

    enum CodingKeys: String, CodingKey {
        case username
        case apiToken = "api_token"
        case otpCode = "otp_code"
        case deviceName = "device_name"
        case scope
        case clientApp = "client_app"
        case nodeRole = "node_role"
        case expiresDays = "expires_days"
    }
}

private struct BridgeCredentials {
    let baseURL: URL
    let username: String
    let token: String
    let deviceID: String
}

enum BridgeSyncError: LocalizedError {
    case missingURL
    case missingToken
    case invalidURL
    case serverRejected(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingURL: return L10n.string("Bridge-Adresse fehlt.")
        case .missingToken: return L10n.string("Bridge-Token fehlt.")
        case .invalidURL: return L10n.string("Bridge-Adresse ist ungültig. Bitte mit https:// eintragen.")
        case .serverRejected(let code):
            return L10n.format("Bridge hat die Synchronisierung abgelehnt (%lld).", Int64(code))
        case .serverMessage(let message): return message
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
            defaults.set("peter", forKey: BridgeSettings.usernameKey)
        }
        KeychainStore.set("", for: BridgeSettings.otpCodeKey)
    }

    var hasSession: Bool {
        !Self.trimmedKeychainValue(for: BridgeSettings.sessionTokenKey).isEmpty
    }

    var sessionExpiresAtText: String {
        defaults.string(forKey: BridgeSettings.sessionExpiresAtKey) ?? ""
    }

    @discardableResult
    func connect(otpCode: String) async throws -> BridgeSessionResponse {
        let apiToken = Self.trimmedKeychainValue(for: BridgeSettings.apiTokenKey)
        let username = defaults.string(forKey: BridgeSettings.usernameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "peter"
        guard !username.isEmpty else { throw BridgeSyncError.serverMessage("Bridge-Benutzername fehlt.") }
        guard !apiToken.isEmpty else { throw BridgeSyncError.missingToken }

        let baseURL = try await Self.configuredBaseURL(defaults: defaults)
        var endpoint = baseURL
        endpoint.append(path: "v1/auth/session")

        let payload = BridgeSessionCreatePayload(
            username: username,
            apiToken: apiToken,
            otpCode: Self.normalizedOTPCode(otpCode),
            deviceName: "Healthpit (iPhone)",
            scope: "home_assistant",
            clientApp: "healthpit",
            nodeRole: "slave",
            expiresDays: 1825
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let message = Self.bridgeErrorMessage(from: data, statusCode: statusCode) {
                throw BridgeSyncError.serverMessage(message)
            }
            throw BridgeSyncError.serverRejected(statusCode)
        }

        let session = try decoder.decode(BridgeSessionResponse.self, from: data)
        guard session.nodeRole == "slave", session.serverRole == "master" else {
            throw BridgeSyncError.serverMessage(
                "Verbindung abgelehnt: Docker muss Master und Healthpit muss Slave sein."
            )
        }
        KeychainStore.set(session.sessionToken, for: BridgeSettings.sessionTokenKey)
        KeychainStore.set("", for: BridgeSettings.otpCodeKey)
        defaults.set(session.expiresAt, forKey: BridgeSettings.sessionExpiresAtKey)
        return session
    }

    func disconnect() {
        KeychainStore.set("", for: BridgeSettings.sessionTokenKey)
        KeychainStore.set("", for: BridgeSettings.otpCodeKey)
        defaults.removeObject(forKey: BridgeSettings.sessionExpiresAtKey)
    }

    @discardableResult
    func syncNow() async throws -> Int {
        let credentials = try await bridgeCredentials()

        var endpoint = credentials.baseURL
        endpoint.append(path: "v1/health/batch")

        let metrics = await collectMetrics()
        let payload = BridgeBatchPayload(deviceID: credentials.deviceID, metrics: metrics)

        var request = authorizedRequest(url: endpoint, method: "POST", credentials: credentials)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let message = Self.bridgeErrorMessage(from: data, statusCode: statusCode) {
                throw BridgeSyncError.serverMessage(message)
            }
            throw BridgeSyncError.serverRejected(statusCode)
        }
        let uploadedAppleHealthWorkouts = try await uploadAppleHealthWorkoutDelta(credentials: credentials)
        let deletedAppleHealthWorkouts = try await reconcileAppleHealthWorkouts(credentials: credentials)
        let uploadedWorkouts = try await uploadLocalWorkouts(credentials: credentials)
        let downloadedAppleHealthWorkouts = try await downloadChangedAppleHealthWorkouts(credentials: credentials)
        let downloadedWorkouts = try await downloadImportedWorkouts(credentials: credentials)
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
        let credentials = try await bridgeCredentials()
        let workouts = try await health.fetchAllWorkouts()
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

    func deleteImportedWorkout(id: UUID) async throws {
        try await deleteImportedWorkout(id: id, credentials: try await bridgeCredentials())
    }

    private func collectMetrics() async -> [BridgeMetricPayload] {
        let now = Date()
        var out: [BridgeMetricPayload] = []

        for metric in HealthMetric.all {
            guard let value = try? await health.currentValue(for: metric) else { continue }
            out.append(metric.payload(value: value, measuredAt: now))
        }

        if let sleep = (try? await health.fetchSleep(in: .week))?.first {
            let sleepMeasuredAt = sleep.end
            out.append(.duration(id: "sleep_duration",
                                 category: .sleep,
                                 title: "Schlafdauer",
                                 seconds: sleep.asleep,
                                 measuredAt: sleepMeasuredAt))
            out.append(.duration(id: "sleep_time_in_bed",
                                 category: .sleep,
                                 title: "Zeit im Bett",
                                 seconds: sleep.timeInBed,
                                 measuredAt: sleepMeasuredAt))
            out.append(.percentage(id: "sleep_efficiency",
                                   category: .sleep,
                                   title: "Schlafeffizienz",
                                   value: sleep.efficiency * 100,
                                   measuredAt: sleepMeasuredAt))
            out.append(.duration(id: "sleep_deep_duration",
                                 category: .sleep,
                                 title: "Tiefschlaf",
                                 seconds: sleep.deep,
                                 measuredAt: sleepMeasuredAt))
            out.append(.duration(id: "sleep_core_duration",
                                 category: .sleep,
                                 title: "Core-Schlaf",
                                 seconds: sleep.core,
                                 measuredAt: sleepMeasuredAt))
            out.append(.duration(id: "sleep_rem_duration",
                                 category: .sleep,
                                 title: "REM-Schlaf",
                                 seconds: sleep.rem,
                                 measuredAt: sleepMeasuredAt))
            out.append(.duration(id: "sleep_awake_duration",
                                 category: .sleep,
                                 title: "Wachzeit",
                                 seconds: sleep.awake,
                                 measuredAt: sleepMeasuredAt))
        }

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
                                       stateClass: "total"))
        return out
    }

    static func bridgeErrorMessage(from data: Data, statusCode: Int) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] as? String else {
            return nil
        }
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
            return L10n.string("Zwei Master dürfen nicht verbunden werden. Die Docker-Bridge ist bereits der Master.")
        }
        return L10n.format("Bridge hat abgelehnt (%lld): %@", Int64(statusCode), detail)
    }

    private static func trimmedKeychainValue(for key: String) -> String {
        KeychainStore.string(for: key).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedOTPCode(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    static func otpCode(secret: String, date: Date = Date()) -> String {
        guard let keyData = base32Decode(secret) else { return "" }
        let step = UInt64(date.timeIntervalSince1970 / 30)
        var counter = step.bigEndian
        let key = SymmetricKey(data: keyData)
        let digest = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(bytes: &counter, count: MemoryLayout<UInt64>.size),
            using: key
        )
        let bytes = Array(digest)
        let offset = Int(bytes.last ?? 0) & 0x0f
        let truncated = (UInt32(bytes[offset] & 0x7f) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        return String(format: "%06d", truncated % 1_000_000)
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
        let workouts = await LocalWorkoutStore.shared.load()
            .filter { [.manual, .gpx, .tcx].contains($0.source) }
        guard !workouts.isEmpty else { return 0 }
        let enrichedWorkouts = await enrichedForUpload(workouts)
        await LocalWorkoutStore.shared.saveMany(enrichedWorkouts)

        var endpoint = credentials.baseURL
        endpoint.append(path: "v1/workouts/imports")

        let payload = BridgeImportedWorkoutBatchPayload(
            deviceID: credentials.deviceID,
            workouts: enrichedWorkouts.map(BridgeImportedWorkoutPayload.init)
        )
        var request = authorizedRequest(url: endpoint, method: "POST", credentials: credentials)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let message = Self.bridgeErrorMessage(from: data, statusCode: statusCode) {
                throw BridgeSyncError.serverMessage(message)
            }
            throw BridgeSyncError.serverRejected(statusCode)
        }
        return enrichedWorkouts.count
    }

    private func uploadAppleHealthWorkoutDelta(credentials: BridgeCredentials) async throws -> Int {
        let cutoff = appleHealthUploadCutoff()
        let workouts: [WorkoutSummary]
        if let cutoff {
            workouts = (try? await health.fetchWorkouts(start: cutoff.addingTimeInterval(-3600))) ?? []
        } else {
            let fallback = Calendar.healthApp.date(byAdding: .day, value: -7, to: .now) ?? .now
            workouts = (try? await health.fetchWorkouts(start: fallback)) ?? []
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
        var uploaded = 0
        let batchSize = 500
        for start in stride(from: 0, to: workouts.count, by: batchSize) {
            let end = min(start + batchSize, workouts.count)
            let batch = workouts[start..<end].map(BridgeImportedWorkoutPayload.init)

            var endpoint = credentials.baseURL
            endpoint.append(path: "v1/workouts/imports")

            let payload = BridgeImportedWorkoutBatchPayload(deviceID: credentials.deviceID,
                                                            workouts: Array(batch))
            var request = authorizedRequest(url: endpoint, method: "POST", credentials: credentials)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                if let message = Self.bridgeErrorMessage(from: data, statusCode: statusCode) {
                    throw BridgeSyncError.serverMessage(message)
                }
                throw BridgeSyncError.serverRejected(statusCode)
            }
            uploaded += batch.count
        }
        return uploaded
    }

    private func reconcileAppleHealthWorkouts(credentials: BridgeCredentials) async throws -> Int {
        let workouts = try await health.fetchAllWorkouts()
        await HealthWorkoutCacheStore.shared.saveAllTime(workouts)
        return try await reconcileAppleHealthWorkouts(workouts: workouts, credentials: credentials)
    }

    private func reconcileAppleHealthWorkouts(workouts: [WorkoutSummary],
                                             credentials: BridgeCredentials) async throws -> Int {
        var endpoint = credentials.baseURL
        endpoint.append(path: "v1/workouts/imports/reconcile")

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
            if let message = Self.bridgeErrorMessage(from: data, statusCode: statusCode) {
                throw BridgeSyncError.serverMessage(message)
            }
            throw BridgeSyncError.serverRejected(statusCode)
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
        rememberAppleHealthUploadCutoff(from: workouts)
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
            endpoint.append(path: "v1/workouts/imports")
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
                if let message = Self.bridgeErrorMessage(from: data, statusCode: statusCode) {
                    throw BridgeSyncError.serverMessage(message)
                }
                throw BridgeSyncError.serverRejected(statusCode)
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
        let bridgeManagedSources: Set<LocalWorkout.Source> = [.garmin, .gympit]
        for source in [LocalWorkout.Source.manual, .gpx, .tcx, .garmin, .gympit] {
            var endpoint = credentials.baseURL
            endpoint.append(path: "v1/workouts/imports")
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
                if let message = Self.bridgeErrorMessage(from: data, statusCode: statusCode) {
                    throw BridgeSyncError.serverMessage(message)
                }
                throw BridgeSyncError.serverRejected(statusCode)
            }
            let responseBody = try decoder.decode(BridgeImportedWorkoutListResponse.self, from: data)
            downloaded.append(contentsOf: responseBody.workouts.compactMap(LocalWorkout.init))
        }
        await LocalWorkoutStore.shared.saveMany(
            downloaded.filter { !bridgeManagedSources.contains($0.source) }
        )
        await LocalWorkoutStore.shared.replaceBridgeManaged(
            sources: bridgeManagedSources,
            with: downloaded.filter { bridgeManagedSources.contains($0.source) }
        )
        return downloaded.count
    }

    private func deleteImportedWorkout(id: UUID, credentials: BridgeCredentials) async throws {
        var endpoint = credentials.baseURL
        endpoint.append(path: "v1/workouts/imports/\(id.uuidString)")
        endpoint.append(queryItems: [URLQueryItem(name: "device_id", value: credentials.deviceID)])

        let request = authorizedRequest(url: endpoint, method: "DELETE", credentials: credentials)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let message = Self.bridgeErrorMessage(from: data, statusCode: statusCode) {
                throw BridgeSyncError.serverMessage(message)
            }
            throw BridgeSyncError.serverRejected(statusCode)
        }
    }

    private func bridgeCredentials() async throws -> BridgeCredentials {
        let sessionToken = Self.trimmedKeychainValue(for: BridgeSettings.sessionTokenKey)
        let username = defaults.string(forKey: BridgeSettings.usernameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "peter"
        let deviceID = defaults.string(forKey: BridgeSettings.deviceIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "iPhone"

        guard !username.isEmpty else { throw BridgeSyncError.serverMessage("Bridge-Benutzername fehlt.") }
        guard !sessionToken.isEmpty else {
            throw BridgeSyncError.serverMessage(
                "Healthpit ist nicht als Slave verbunden. Bitte zuerst mit der Docker-Bridge verbinden."
            )
        }
        let baseURL = try await Self.configuredBaseURL(defaults: defaults)
        return BridgeCredentials(baseURL: baseURL,
                                 username: username,
                                 token: sessionToken,
                                 deviceID: deviceID)
    }

    static func configuredBaseURL(defaults: UserDefaults = .standard) async throws -> URL {
        let localHost = defaults.string(forKey: BridgeSettings.localHostKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localPort = defaults.string(forKey: BridgeSettings.localPortKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "8088"

        if !localHost.isEmpty {
            let localURL = try localBaseURL(host: localHost, port: localPort)
            if await isBridgeReachable(at: localURL) {
                return localURL
            }
        }

        return try externalBaseURL(defaults: defaults)
    }

    private static func externalBaseURL(defaults: UserDefaults) throws -> URL {
        let baseURLText = defaults.string(forKey: BridgeSettings.baseURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !baseURLText.isEmpty else { throw BridgeSyncError.missingURL }
        guard let baseURL = URL(string: baseURLText) else { throw BridgeSyncError.invalidURL }
        guard baseURL.scheme?.lowercased() == "https" else {
            throw BridgeSyncError.serverMessage("Bitte die externe Cloudflare-Adresse mit https:// eintragen.")
        }
        return baseURL
    }

    private static func localBaseURL(host: String, port: String) throws -> URL {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPort = port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "8088"
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

    private static func isBridgeReachable(at baseURL: URL) async -> Bool {
        var endpoint = baseURL
        endpoint.append(path: "health")

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 1.2

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            let healthy = object["status"] as? String == "ok"
                || object["ok"] as? Bool == true
            return healthy && object["node_role"] as? String == "master"
        } catch {
            return false
        }
    }

    private func authorizedRequest(url: URL, method: String, credentials: BridgeCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.username, forHTTPHeaderField: "X-Healthpit-User")
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func base32Decode(_ value: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let lookup = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, UInt8($0.offset)) })
        let cleaned = value
            .uppercased()
            .filter { $0 != "=" && !$0.isWhitespace }

        var buffer = 0
        var bitsLeft = 0
        var output = Data()

        for character in cleaned {
            guard let decoded = lookup[character] else { return nil }
            buffer = (buffer << 5) | Int(decoded)
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                output.append(UInt8((buffer >> bitsLeft) & 0xff))
            }
        }
        return output
    }
}

private extension HealthMetric {
    func payload(value: Double, measuredAt: Date) -> BridgeMetricPayload {
        BridgeMetricPayload(id: bridgeID,
                            category: category.rawValue,
                            title: title,
                            value: value * displayScale,
                            unit: unitSymbol,
                            measuredAt: measuredAt,
                            aggregation: aggregation == .cumulativeSum ? "sum" : "average",
                            icon: mdiIcon,
                            deviceClass: deviceClass,
                            stateClass: aggregation == .cumulativeSum ? "total" : "measurement")
    }

    var bridgeID: String {
        let raw = quantityTypeIdentifier.rawValue
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
        return raw.snakeCased()
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
                            stateClass: "measurement")
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
                            stateClass: "measurement")
    }
}

private extension BridgeImportedWorkoutPayload {
    init(_ workout: WorkoutSummary) {
        self.init(id: workout.uuid.uuidString,
                  source: LocalWorkout.Source.appleHealth.rawValue,
                  sport: workout.activityName,
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
