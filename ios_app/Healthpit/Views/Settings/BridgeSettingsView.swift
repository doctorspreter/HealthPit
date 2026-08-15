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
    @AppStorage(BridgeSettings.localPortKey) private var localPort = HealthPitAPI.defaultPort
    @AppStorage(BridgeSettings.usernameKey) private var username = "healthpit"
    @AppStorage(BridgeSettings.deviceIDKey) private var deviceID = UIDevice.current.name
    @AppStorage(BridgeSettings.syncEnabledKey) private var syncEnabled = true
    @AppStorage(BridgeSettings.syncIntervalKey) private var syncInterval = 3600.0
    @AppStorage(BridgeSettings.lastSyncDateKey) private var lastSyncDate = Date.distantPast
    @AppStorage(BridgeSettings.historyImportPromptHandledKey) private var historyImportPromptHandled = false
    @AppStorage(BridgeSettings.lastHistoryImportDateKey) private var lastHistoryImportDate = Date.distantPast
    @AppStorage(DashboardItem.storageKey) private var dashboardOrderRaw = DashboardItem.encode(DashboardItem.defaultOrder)
    @AppStorage(DashboardItem.sizeStorageKey) private var dashboardSizesRaw = ""
    @AppStorage(DashboardItem.hiddenStorageKey) private var dashboardHiddenRaw = ""
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage(MeasurementSystemSetting.storageKey) private var measurementSystemRawValue = MeasurementSystemSetting.automatic.rawValue

    @State private var homeAssistantToken = ""
    @State private var isSyncing = false
    @State private var isFullSyncing = false
    @State private var isImportingHistory = false
    @State private var isConnecting = false
    @State private var isBridgeConnected = false
    @State private var isShowingHistoryImportPrompt = false
    @State private var historyImportFailed = false
    @State private var historyImportMessage: String?
    @State private var historyImportDetail: String?
    @State private var connectionStatus = ""
    @State private var connectionDetail: String?
    @State private var message: String?
    @State private var messageDetail: String?
    @State private var backupDocument: HealthPitBackupDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        connectionScreen
                    } label: {
                        ProfessionalSettingsLabel(title: "Verbindung",
                                                  subtitle: "Home Assistant und Synchronisierung",
                                                  symbol: "antenna.radiowaves.left.and.right",
                                                  tint: .blue)
                    }
                    NavigationLink {
                        DataSourcesSettingsView()
                    } label: {
                        ProfessionalSettingsLabel(title: "Datenquellen",
                                                  subtitle: "Apple Health und Importe priorisieren",
                                                  symbol: "point.3.connected.trianglepath.dotted",
                                                  tint: .teal)
                    }
                    NavigationLink {
                        DuplicateSettingsView()
                    } label: {
                        ProfessionalSettingsLabel(title: "Duplikate",
                                                  subtitle: "Doppelte Trainings erkennen",
                                                  symbol: "square.on.square.dashed",
                                                  tint: .orange)
                    }
                    NavigationLink {
                        backupScreen
                    } label: {
                        ProfessionalSettingsLabel(title: "Datensicherung",
                                                  subtitle: "Exportieren und wiederherstellen",
                                                  symbol: "externaldrive.fill",
                                                  tint: .indigo)
                    }
                } header: { Text(L10n.string("Daten & Verbindung")) }

                Section {
                    NavigationLink {
                        ActivityGoalSettingsView()
                    } label: {
                        ProfessionalSettingsLabel(title: "Ziele",
                                                  subtitle: "Tages-, Wochen- und Monatsziele festlegen",
                                                  symbol: "target",
                                                  tint: .orange)
                    }
                    NavigationLink {
                        homeScreenScreen
                    } label: {
                        ProfessionalSettingsLabel(title: "Startseite",
                                                  subtitle: "Bereiche, Reihenfolge und Größen",
                                                  symbol: "square.grid.2x2.fill",
                                                  tint: .purple)
                    }
                    NavigationLink {
                        appearanceScreen
                    } label: {
                        ProfessionalSettingsLabel(title: "Sprache & Einheiten",
                                                  subtitle: "Darstellung persönlich anpassen",
                                                  symbol: "globe.europe.africa.fill",
                                                  tint: .pink)
                    }
                } header: { Text(L10n.string("Darstellung")) }

                Section(L10n.string("App")) {
                    LabeledContent(L10n.string("Version")) {
                        Text(appVersionText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .professionalPageBackground(tint: .purple)
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupDocument?.backup.suggestedFileName ?? "healthpit-backup"
            ) { result in
                switch result {
                case let .success(url):
                    backupStatus = L10n.format("Sicherung gespeichert als %@.", url.lastPathComponent)
                case .failure:
                    backupStatus = L10n.string("Die Sicherung konnte nicht gespeichert werden.")
                }
                backupDocument = nil
            }
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: [.json]
            ) { result in
                Task { await restoreBackup(from: result) }
            }
            .navigationTitle(L10n.string("Einstellungen"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                homeAssistantToken = KeychainStore.string(for: BridgeSettings.homeAssistantTokenKey)
                Task { await refreshBridgeConnectionStatus() }
            }
            .onChange(of: homeAssistantToken) { _, newValue in
                KeychainStore.set(newValue, for: BridgeSettings.homeAssistantTokenKey)
            }
            .onChange(of: syncEnabled) { _, _ in
                BackgroundSyncScheduler.schedule()
            }
            .onChange(of: syncInterval) { _, _ in
                BackgroundSyncScheduler.schedule()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("Fertig")) { dismiss() }
                }
            }
        }
    }

    // MARK: Untermenues

    private var connectionScreen: some View {
        Form {
                Section(L10n.string("Home Assistant")) {
                    TextField(L10n.string("Lokale Adresse"), text: $localHost)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField(L10n.string("Port"), text: $localPort)
                        .keyboardType(.numberPad)
                    TextField(L10n.string("Externe Adresse (optional)"), text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("Long-Lived Access Token", text: $homeAssistantToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                            Text(L10n.string("Verbindung trennen"))
                        }
                    }
                    if !connectionStatus.isEmpty {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let connectionDetail {
                        technicalDetail(connectionDetail)
                    }
                }

                Section(L10n.string("Synchronisierung")) {
                    Toggle(L10n.string("Synchronisierung aktiv"), isOn: $syncEnabled)
                    Picker(L10n.string("Intervall"), selection: $syncInterval) {
                        Text(L10n.string("30 Minuten")).tag(1800.0)
                        Text(L10n.string("1 Stunde")).tag(3600.0)
                        Text(L10n.string("3 Stunden")).tag(10800.0)
                        Text(L10n.string("6 Stunden")).tag(21600.0)
                    }
                    if lastSyncDate > .distantPast {
                        LabeledContent(L10n.string("Letzter Sync")) {
                            Text(lastSyncDate, format: .dateTime.day().month().hour().minute())
                        }
                    }
                }

                Section {
                    Button {
                        Task { await sync() }
                    } label: {
                        HStack {
                            if isSyncing { ProgressView() }
                            Text(L10n.string("Jetzt synchronisieren"))
                        }
                    }
                    .disabled(isSyncing || isFullSyncing || isImportingHistory || !syncEnabled)

                    Button(role: .destructive) {
                        Task { await fullWorkoutSync() }
                    } label: {
                        HStack {
                            if isFullSyncing { ProgressView() }
                            Text(L10n.string("Apple-Health-Workouts komplett neu laden"))
                        }
                    }
                    .disabled(isSyncing || isFullSyncing || isImportingHistory || !syncEnabled)

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let messageDetail {
                        technicalDetail(messageDetail)
                    }
                }

                Section(L10n.string("Langzeitdaten in Home Assistant")) {
                    Button {
                        Task { await importHistory() }
                    } label: {
                        HStack {
                            if isImportingHistory { ProgressView() }
                            Text(L10n.string("Bisherige Daten integrieren"))
                        }
                    }
                    // Der einmalige Import ist bewusst auch bei deaktiviertem
                    // Hintergrund-Sync verfügbar.
                    .disabled(isSyncing || isFullSyncing || isImportingHistory)

                    Text(L10n.string("Integriere auch die Daten, die vor der Verbindung mit Home Assistant aufgezeichnet wurden. Die Übertragung erfolgt einmalig und kann mehrere Minuten dauern."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 12) {
                        Text(L10n.string("Status"))
                        Spacer(minLength: 12)
                        historyImportStatus
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // `LabeledContent` can make a multiline value consume the
                    // remaining Form height. Keep this row at its intrinsic
                    // height so the import result follows directly below it.
                    .fixedSize(horizontal: false, vertical: true)

                    if let historyImportMessage {
                        Text(historyImportMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let historyImportDetail {
                        technicalDetail(historyImportDetail)
                    }
                }
        }
        .navigationTitle(L10n.string("Verbindung"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L10n.string("Bisherige Daten integrieren?"), isPresented: $isShowingHistoryImportPrompt) {
            Button(L10n.string("Jetzt integrieren")) {
                Task { await importHistory() }
            }
            Button(L10n.string("Später"), role: .cancel) {}
        } message: {
            Text(L10n.string("Möchtest du auch die Daten, die vor der Verbindung aufgezeichnet wurden, in Home Assistant integrieren? Du kannst dies auch später in den Einstellungen nachholen."))
        }
    }

    @ViewBuilder
    private var historyImportStatus: some View {
        if isImportingHistory {
            Text(L10n.string("Übertragung läuft …"))
                .foregroundStyle(.secondary)
        } else if historyImportFailed {
            Label(L10n.string("Integration fehlgeschlagen – erneut versuchen"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if lastHistoryImportDate > .distantPast {
            Label(L10n.string("Alle bisherigen Daten wurden integriert"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Text(L10n.string("Noch nicht integriert"))
                .foregroundStyle(.secondary)
        }
    }

    private var backupScreen: some View {
        Form {
                Section(L10n.string("Datensicherung")) {
                    Button {
                        Task { await prepareBackup() }
                    } label: {
                        Label(L10n.string("Daten exportieren"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isImportingBackup = true
                    } label: {
                        Label(L10n.string("Daten importieren"), systemImage: "square.and.arrow.down")
                    }
                    if !backupStatus.isEmpty {
                        Text(backupStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(L10n.string("Die Sicherung enthält alle lokalen Workouts als JSON-Datei. Beim Import wird nichts gelöscht, nur ergänzt und aktualisiert. Zugangsdaten sind aus Sicherheitsgründen nicht enthalten und müssen nach einer Wiederherstellung neu eingetragen werden."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

        }
        .navigationTitle(L10n.string("Datensicherung"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var homeScreenScreen: some View {
        Form {
            DashboardOrderSettingsSection(orderRaw: $dashboardOrderRaw,
                                          sizesRaw: $dashboardSizesRaw,
                                          hiddenRaw: $dashboardHiddenRaw)
        }
        .navigationTitle(L10n.string("Startseite"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appearanceScreen: some View {
        Form {
                Section(L10n.string("Sprache")) {
                    Picker(L10n.string("App-Sprache"), selection: $appLanguageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    Text(L10n.string("Beim Sprachwechsel wird die Oberfläche neu gestartet. Systemstandard verwendet die in iOS bevorzugte Sprache."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.string("Maßeinheiten")) {
                    Picker(L10n.string("Einheiten"), selection: $measurementSystemRawValue) {
                        ForEach(MeasurementSystemSetting.allCases) { system in
                            Text(system.title).tag(system.rawValue)
                        }
                    }
                    Text(L10n.string("„Wie in Apple Health“ übernimmt die Einheiten aus der Health-App. An die Bridge werden weiterhin metrische Werte geschickt, damit bestehende Home-Assistant-Sensoren ihre Historie behalten."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

        }
        .navigationTitle(L10n.string("Sprache und Einheiten"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Aufklappbare Zeile fuer den technischen Rest.
    ///
    /// Der rohe Antwortkoerper und Fehlercodes sind fuer die Fehlersuche
    /// unverzichtbar, gehoeren aber nicht in den Satz, den der Anwender liest.
    private func technicalDetail(_ text: String) -> some View {
        DisclosureGroup("Technische Details") {
            Text(text)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func connectBridge() async {
        let shouldOfferHistoryImport = !historyImportPromptHandled
            && lastHistoryImportDate == .distantPast
        isConnecting = true
        connectionDetail = nil
        connectionStatus = L10n.string("Verbindet …")
        do {
            _ = try await BridgeSyncService.shared.connect()
            isConnecting = false
            await refreshBridgeConnectionStatus()
            if shouldOfferHistoryImport {
                historyImportPromptHandled = true
                isShowingHistoryImportPrompt = true
            }
        } catch {
            isConnecting = false
            isBridgeConnected = BridgeSyncService.shared.hasSession
            connectionStatus = BridgeErrorText.message(for: error)
            connectionDetail = BridgeErrorText.technicalDetail(for: error)
        }
    }

    private func disconnectBridge() {
        BridgeSyncService.shared.disconnect()
        // Der Token ist die Anmeldung; „Verbindung trennen“ muss ihn deshalb
        // auch entfernen, sonst bliebe die App verbunden.
        homeAssistantToken = ""
        Task { await refreshBridgeConnectionStatus() }
    }

    /// Report the bridge actually in use, not merely that some session exists.
    ///
    /// A session issued by a different bridge is worthless, and the local
    /// address silently losing out to the external one used to be invisible.
    private func refreshBridgeConnectionStatus() async {
        let service = BridgeSyncService.shared
        isBridgeConnected = service.hasSession

        connectionDetail = nil

        let active = await BridgeSyncService.activeEndpoint()
        guard let activeURL = active.url else {
            connectionStatus = L10n.string("Keine erreichbare Bridge. Bitte Adresse und Port prüfen.")
            return
        }
        // Vollstaendige Saetze statt zusammengesetzter Fragmente: die
        // Wortstellung unterscheidet sich je Sprache, verkettete Bruchstuecke
        // ergeben ausserhalb des Deutschen Unsinn.
        let address = activeURL.absoluteString

        guard service.hasSession else {
            connectionStatus = active.isLocal
                ? L10n.format("Home Assistant ist unter %@ erreichbar, aber noch nicht verbunden.", address)
                : L10n.format("Home Assistant ist unter %@ erreichbar, aber noch nicht verbunden.", address)
            return
        }

        let sessionEndpoint = service.sessionEndpointText
        if !sessionEndpoint.isEmpty && sessionEndpoint != address {
            connectionStatus = L10n.format("Der Token wurde für %@ geprüft, aktiv ist jetzt aber %@. Bitte neu verbinden.",
                                           sessionEndpoint, address)
            return
        }

        // Ein Long-Lived Token laeuft nicht ab, es gibt also keine Restlaufzeit
        // zu melden. Widerrufen wird er im Home-Assistant-Profil.
        connectionStatus = active.isLocal
            ? L10n.format("Verbunden mit Home Assistant unter %@ (lokal).", address)
            : L10n.format("Verbunden mit Home Assistant unter %@ (extern).", address)
    }

    private func sync() async {
        isSyncing = true
        message = nil
        messageDetail = nil
        defer { isSyncing = false }
        do {
            let count = try await BridgeSyncService.shared.syncNow()
            message = L10n.format("%lld Werte synchronisiert.", count)
        } catch {
            message = BridgeErrorText.message(for: error)
            messageDetail = BridgeErrorText.technicalDetail(for: error)
        }
    }

    private func fullWorkoutSync() async {
        isFullSyncing = true
        message = nil
        messageDetail = nil
        defer { isFullSyncing = false }
        do {
            let count = try await BridgeSyncService.shared.fullResyncAppleHealthWorkouts()
            message = L10n.format("%lld Apple-Health-Workouts neu synchronisiert.", count)
        } catch {
            message = BridgeErrorText.message(for: error)
            messageDetail = BridgeErrorText.technicalDetail(for: error)
        }
    }

    private func importHistory() async {
        isImportingHistory = true
        historyImportFailed = false
        historyImportMessage = nil
        historyImportDetail = nil
        defer { isImportingHistory = false }
        do {
            let result = try await BridgeSyncService.shared.importAllHistory()
            lastHistoryImportDate = .now
            historyImportPromptHandled = true
            historyImportMessage = L10n.format(
                "%lld historische Werte aus %lld Messreihen und %lld Workouts wurden an Home Assistant gesendet.",
                result.pointCount + result.workoutRows,
                result.metricCount,
                result.workoutCount
            )
        } catch {
            historyImportFailed = true
            historyImportMessage = BridgeErrorText.message(for: error)
            historyImportDetail = BridgeErrorText.technicalDetail(for: error)
        }
    }

    private func prepareBackup() async {
        backupStatus = L10n.string("Sicherung wird erstellt …")
        let backup = await HealthPitBackupService.makeBackup(
            deviceID: deviceID,
            username: username
        )
        guard !backup.workouts.isEmpty else {
            backupStatus = L10n.string("Es sind keine lokalen Workouts vorhanden.")
            return
        }
        backupDocument = HealthPitBackupDocument(backup: backup)
        backupStatus = L10n.format("%lld Workouts vorbereitet.", backup.workouts.count)
        isExportingBackup = true
    }

    private func restoreBackup(from result: Result<URL, Error>) async {
        switch result {
        case let .success(url):
            do {
                let backup = try HealthPitBackupService.readBackup(at: url)
                let count = await HealthPitBackupService.restore(backup)
                backupStatus = L10n.format("%lld Workouts aus der Sicherung übernommen.", count)
            } catch {
                backupStatus = L10n.string("Die Datei konnte nicht gelesen werden. Ist es eine HealthPit-Sicherung?")
            }
        case .failure:
            backupStatus = L10n.string("Es wurde keine Datei ausgewählt.")
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
