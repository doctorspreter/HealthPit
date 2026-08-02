//
//  BridgeSettingsView.swift
//  Healthpit
//
//  Einstellungen fuer die Home-Assistant-Bridge.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BridgeSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(BridgeSettings.baseURLKey) private var baseURL = ""
    @AppStorage(BridgeSettings.localHostKey) private var localHost = ""
    @AppStorage(BridgeSettings.localPortKey) private var localPort = "8088"
    @AppStorage(BridgeSettings.usernameKey) private var username = "healthpit"
    @AppStorage(BridgeSettings.deviceIDKey) private var deviceID = UIDevice.current.name
    @AppStorage(BridgeSettings.syncEnabledKey) private var syncEnabled = true
    @AppStorage(BridgeSettings.syncIntervalKey) private var syncInterval = 3600.0
    @AppStorage(BridgeSettings.lastSyncDateKey) private var lastSyncDate = Date.distantPast
    @AppStorage(DashboardItem.storageKey) private var dashboardOrderRaw = DashboardItem.encode(DashboardItem.defaultOrder)
    @AppStorage(DashboardItem.sizeStorageKey) private var dashboardSizesRaw = ""
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    @State private var apiToken = ""
    @State private var otpCode = ""
    @State private var isSyncing = false
    @State private var isFullSyncing = false
    @State private var isConnecting = false
    @State private var isBridgeConnected = false
    @State private var connectionStatus = ""
    @State private var message: String?
    @State private var backupDocument: HealthpitBackupDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Bridge") {
                    TextField("Lokale Verbindung", text: $localHost)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Port", text: $localPort)
                        .keyboardType(.numberPad)
                    TextField("Externe Verbindung (optional)", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Benutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Token", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("OTP-Code (optional)", text: $otpCode)
                        .keyboardType(.numberPad)
                    Button {
                        Task { await connectBridge() }
                    } label: {
                        HStack {
                            if isConnecting { ProgressView() }
                            Text(isBridgeConnected ? "Neu verbinden" : "Verbinden")
                        }
                    }
                    .disabled(isConnecting)
                    if isBridgeConnected {
                        Button(role: .destructive) {
                            disconnectBridge()
                        } label: {
                            Text("Verbindung trennen")
                        }
                    }
                    if !connectionStatus.isEmpty {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Die Bridge ist der Master — das kann die Home-Assistant-App oder der Docker-Container sein. Die lokale Adresse wird bevorzugt; die externe ist nur nötig, wenn die lokale nicht antwortet. Den OTP-Code nur eintragen, wenn 2FA in der Bridge aktiv ist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Synchronisierung") {
                    Toggle("Synchronisierung aktiv", isOn: $syncEnabled)
                    Picker("Intervall", selection: $syncInterval) {
                        Text("30 Minuten").tag(1800.0)
                        Text("1 Stunde").tag(3600.0)
                        Text("3 Stunden").tag(10800.0)
                        Text("6 Stunden").tag(21600.0)
                    }
                    if lastSyncDate > .distantPast {
                        LabeledContent("Letzter Sync") {
                            Text(lastSyncDate, format: .dateTime.day().month().hour().minute())
                        }
                    }
                }

                Section("Daten") {
                    NavigationLink {
                        DataSourcesSettingsView()
                    } label: {
                        Label("Datenquellen", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    Text("Quellen auswählen, doppelte Werte vermeiden, Schreibzugriffe festlegen und Daten löschen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Datensicherung") {
                    Button {
                        Task { await prepareBackup() }
                    } label: {
                        Label("Daten exportieren", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isImportingBackup = true
                    } label: {
                        Label("Daten importieren", systemImage: "square.and.arrow.down")
                    }
                    if !backupStatus.isEmpty {
                        Text(backupStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Die Sicherung enthält alle lokalen Workouts als JSON-Datei. Beim Import wird nichts gelöscht, nur ergänzt und aktualisiert. Zugangsdaten sind aus Sicherheitsgründen nicht enthalten und müssen nach einer Wiederherstellung neu eingetragen werden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DashboardOrderSettingsSection(orderRaw: $dashboardOrderRaw,
                                              sizesRaw: $dashboardSizesRaw)

                Section("Sprache") {
                    Picker("App-Sprache", selection: $appLanguageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    Text("Beim Sprachwechsel wird die Oberfläche neu gestartet. Systemstandard verwendet die in iOS bevorzugte Sprache.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("App") {
                    LabeledContent("Version") {
                        Text(appVersionText)
                    }
                }

                Section {
                    Button {
                        Task { await sync() }
                    } label: {
                        HStack {
                            if isSyncing { ProgressView() }
                            Text("Jetzt synchronisieren")
                        }
                    }
                    .disabled(isSyncing || !syncEnabled)

                    Button(role: .destructive) {
                        Task { await fullWorkoutSync() }
                    } label: {
                        HStack {
                            if isFullSyncing { ProgressView() }
                            Text("Apple-Health-Workouts komplett neu laden")
                        }
                    }
                    .disabled(isSyncing || isFullSyncing || !syncEnabled)

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupDocument?.backup.suggestedFileName ?? "healthpit-backup"
            ) { result in
                switch result {
                case let .success(url):
                    backupStatus = L10n.string("Sicherung gespeichert:") + " \(url.lastPathComponent)"
                case let .failure(error):
                    backupStatus = L10n.string("Export fehlgeschlagen:") + " \(error.localizedDescription)"
                }
                backupDocument = nil
            }
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: [.json]
            ) { result in
                Task { await restoreBackup(from: result) }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                apiToken = KeychainStore.string(for: BridgeSettings.apiTokenKey)
                otpCode = ""
                Task { await refreshBridgeConnectionStatus() }
            }
            .onChange(of: apiToken) { _, newValue in
                KeychainStore.set(newValue, for: BridgeSettings.apiTokenKey)
            }
            .onChange(of: syncEnabled) { _, _ in
                BackgroundSyncScheduler.schedule()
            }
            .onChange(of: syncInterval) { _, _ in
                BackgroundSyncScheduler.schedule()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func connectBridge() async {
        isConnecting = true
        connectionStatus = L10n.string("Bridge verbindet …")
        do {
            _ = try await BridgeSyncService.shared.connect(otpCode: otpCode)
            otpCode = ""
            isConnecting = false
            await refreshBridgeConnectionStatus()
        } catch {
            isConnecting = false
            isBridgeConnected = BridgeSyncService.shared.hasSession
            connectionStatus = L10n.string("Bridge-Verbindungsfehler:") + " \(error.localizedDescription)"
        }
    }

    private func disconnectBridge() {
        BridgeSyncService.shared.disconnect()
        otpCode = ""
        Task { await refreshBridgeConnectionStatus() }
    }

    /// Report the bridge actually in use, not merely that some session exists.
    ///
    /// A session issued by a different bridge is worthless, and the local
    /// address silently losing out to the external one used to be invisible.
    private func refreshBridgeConnectionStatus() async {
        let service = BridgeSyncService.shared
        isBridgeConnected = service.hasSession

        let active = await BridgeSyncService.activeEndpoint()
        guard let activeURL = active.url else {
            connectionStatus = L10n.string("Keine erreichbare Bridge. Adresse und Port prüfen.")
            return
        }
        let scope = active.isLocal ? L10n.string("lokal") : L10n.string("extern")

        guard service.hasSession else {
            connectionStatus = L10n.string("Bridge erreichbar unter")
                + " \(activeURL.absoluteString) (\(scope)) — "
                + L10n.string("noch nicht verbunden")
            return
        }

        let sessionEndpoint = service.sessionEndpointText
        if !sessionEndpoint.isEmpty && sessionEndpoint != activeURL.absoluteString {
            connectionStatus = L10n.string("Die gespeicherte Sitzung gehört zu")
                + " \(sessionEndpoint). "
                + L10n.string("Jetzt aktiv ist") + " \(activeURL.absoluteString) (\(scope)). "
                + L10n.string("Bitte neu verbinden.")
            return
        }

        let expiresAt = service.sessionExpiresAtText
        let base = L10n.string("Verbunden mit") + " \(activeURL.absoluteString) (\(scope))"
        connectionStatus = expiresAt.isEmpty ? base : base + " " + L10n.string("bis") + " \(expiresAt)"
    }

    private func sync() async {
        isSyncing = true
        message = nil
        defer { isSyncing = false }
        do {
            let count = try await BridgeSyncService.shared.syncNow()
            message = L10n.format("%lld Werte synchronisiert.", count)
        } catch {
            message = error.localizedDescription
        }
    }

    private func fullWorkoutSync() async {
        isFullSyncing = true
        message = nil
        defer { isFullSyncing = false }
        do {
            let count = try await BridgeSyncService.shared.fullResyncAppleHealthWorkouts()
            message = L10n.format("%lld Apple-Health-Workouts neu synchronisiert.", count)
        } catch {
            message = error.localizedDescription
        }
    }

    private func prepareBackup() async {
        backupStatus = L10n.string("Sicherung wird erstellt …")
        let backup = await HealthpitBackupService.makeBackup(
            deviceID: deviceID,
            username: username
        )
        guard !backup.workouts.isEmpty else {
            backupStatus = L10n.string("Es sind keine lokalen Workouts vorhanden.")
            return
        }
        backupDocument = HealthpitBackupDocument(backup: backup)
        backupStatus = L10n.format("%lld Workouts vorbereitet.", backup.workouts.count)
        isExportingBackup = true
    }

    private func restoreBackup(from result: Result<URL, Error>) async {
        switch result {
        case let .success(url):
            do {
                let backup = try HealthpitBackupService.readBackup(at: url)
                let count = await HealthpitBackupService.restore(backup)
                backupStatus = L10n.format("%lld Workouts aus der Sicherung übernommen.", count)
            } catch {
                backupStatus = L10n.string("Import fehlgeschlagen:") + " \(error.localizedDescription)"
            }
        case let .failure(error):
            backupStatus = L10n.string("Import fehlgeschlagen:") + " \(error.localizedDescription)"
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (version?.isEmpty == false ? version : nil,
                build?.isEmpty == false ? build : nil) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (_, build?):
            return build
        default:
            return "-"
        }
    }
}

#Preview {
    BridgeSettingsView()
}
