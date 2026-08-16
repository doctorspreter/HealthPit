//
//  DataSourcesSettingsView.swift
//  Healthpit
//
//  Quellen-, Schreib- und Loeschverwaltung direkt auf dem iPhone.
//

import SwiftUI

struct DataSourcesSettingsView: View {
    @State private var sources: [HealthSourceDescriptor] = []
    @State private var isLoading = false
    @State private var loadMessage: String?
    @State private var showingDeleteLocalConfirmation = false
    @State private var actionMessage: String?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AppleHealthWriteSettingsView()
                } label: {
                    DataSourceRow(title: "Apple Health",
                                  subtitle: "Lesen, schreiben und HealthPit-Daten löschen",
                                  systemImage: "heart.fill",
                                  tint: .red)
                }

                NavigationLink {
                    BridgeDataSharingSettingsView()
                } label: {
                    DataSourceRow(title: "Daten mit HealthPit teilen",
                                  subtitle: "Auswählen, was übertragen werden darf",
                                  systemImage: "checklist",
                                  tint: .blue)
                }

                NavigationLink {
                    WorkoutListView()
                } label: {
                    DataSourceRow(title: "Trainings verwalten",
                                  subtitle: "Einzelne Trainings ansehen oder entfernen",
                                  systemImage: "figure.run",
                                  tint: .green)
                }
            } header: {
                Text(L10n.string("Schnittstellen"))
            } footer: {
                Text(L10n.string("Die Einstellungen werden auf diesem iPhone gespeichert. Zur Bridge gelangen nur Werte aus aktivierten Quellen."))
            }

            Section(L10n.string("Erkannte Apple-Health-Quellen")) {
                if isLoading && sources.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView(L10n.string("Quellen werden gesucht …"))
                        Spacer()
                    }
                } else if sources.isEmpty {
                    ContentUnavailableView(L10n.string("Keine Quellen gefunden"),
                                           systemImage: "tray",
                                           description: Text(loadMessage ?? L10n.string("Apple Health enthält noch keine freigegebenen Datenquellen.")))
                } else {
                    ForEach(sources) { source in
                        NavigationLink {
                            HealthSourceSettingsView(source: source)
                        } label: {
                            DataSourceRow(title: source.name,
                                          subtitle: sourceSubtitle(source),
                                          systemImage: source.isHealthpit ? "heart.text.square.fill" : "app.connected.to.app.below.fill",
                                          tint: source.isHealthpit ? .pink : .blue)
                        }
                    }
                }
            }

            Section(L10n.string("Auf diesem iPhone")) {
                NavigationLink {
                    LocalDataSourcesSettingsView()
                } label: {
                    DataSourceRow(title: "Lokale Daten & Bridge",
                                  subtitle: "Manuell, GPX/TCX und GymPit",
                                  systemImage: "internaldrive.fill",
                                  tint: .orange)
                }

                Button(L10n.string("Alle lokalen App-Daten löschen"), role: .destructive) {
                    showingDeleteLocalConfirmation = true
                }
            }
        }
        .navigationTitle(L10n.string("Datenquellen"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSources() }
        .refreshable { await loadSources() }
        .confirmationDialog(L10n.string("Alle lokalen App-Daten löschen?"),
                            isPresented: $showingDeleteLocalConfirmation,
                            titleVisibility: .visible) {
            Button(L10n.string("Lokale Daten löschen"), role: .destructive) {
                Task { await deleteLocalData() }
            }
            Button(L10n.string("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L10n.string("Manuelle und importierte Trainings sowie lokale Zwischenspeicher werden gelöscht. Apple Health und die Docker-Bridge bleiben unverändert."))
        }
        .alert(L10n.string("Datenquellen"), isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button(L10n.string("OK"), role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private func sourceSubtitle(_ source: HealthSourceDescriptor) -> String {
        let count = source.dataPointIDs.count
        let status = L10n.string(HealthDataSourceSettings.isSourceEnabled(source.id) ? "Aktiv" : "Deaktiviert")
        let type = L10n.string(count == 1 ? "Datentyp" : "Datentypen")
        return "\(status) · \(count) \(type)"
    }

    @MainActor
    private func loadSources() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sources = try await HealthKitManager.shared.discoverDataSources()
            loadMessage = nil
        } catch {
            loadMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteLocalData() async {
        // Zuerst die Datenbank. Sie ist der Bestand; die Dateien daneben sind
        // nur Zwischenspeicher. Sie allein zu leeren hiess: Es sieht geloescht
        // aus, bis die Ansicht das naechste Mal nachfragt.
        if let store = try? await HealthPitData.shared.store() {
            try? await store.resetObservationData()
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: BridgeSettings.hiddenHealthWorkoutIDsKey)
        actionMessage = L10n.string("Die lokalen App-Daten wurden gelöscht.")
    }
}

private struct BridgeDataSharingSettingsView: View {
    @State private var searchText = ""
    @State private var enabledIDs: Set<String>

    init() {
        _enabledIDs = State(initialValue: Set(
            BridgeDataTypeDescriptor.all
                .filter { BridgeDataSharingSettings.isEnabled($0.id) }
                .map(\.id)
        ))
    }

    var body: some View {
        List {
            Section {
                LabeledContent(L10n.string("Freigegeben")) {
                    Text("\(enabledIDs.count) / \(BridgeDataTypeDescriptor.all.count)")
                        .monospacedDigit()
                }
            } footer: {
                Text(L10n.string("Nur ausgewählte Daten werden bei neuen Synchronisierungen an Home Assistant übertragen. Bereits übertragene Daten bleiben unverändert."))
            }

            if groupedDataTypes.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(groupedDataTypes, id: \.category) { group in
                    Section(group.category.title) {
                        ForEach(group.dataTypes) { dataType in
                            Toggle(isOn: binding(for: dataType.id)) {
                                Label(L10n.string(dataType.title), systemImage: dataType.systemImage)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.string("Datenfreigabe"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Daten durchsuchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.string("Alle auswählen")) { setAll(enabled: true) }
                    Button(L10n.string("Alle abwählen")) { setAll(enabled: false) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Auswahl bearbeiten")
            }
        }
    }

    private var groupedDataTypes: [(category: HealthCategory, dataTypes: [BridgeDataTypeDescriptor])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = BridgeDataTypeDescriptor.all.filter { dataType in
            query.isEmpty
                || L10n.string(dataType.title).localizedCaseInsensitiveContains(query)
                || dataType.category.title.localizedCaseInsensitiveContains(query)
        }
        let grouped = Dictionary(grouping: filtered, by: \.category)
        return HealthCategory.allCases.compactMap { category in
            guard let dataTypes = grouped[category], !dataTypes.isEmpty else { return nil }
            return (
                category,
                dataTypes.sorted {
                    L10n.string($0.title).localizedCaseInsensitiveCompare(L10n.string($1.title)) == .orderedAscending
                }
            )
        }
    }

    private func binding(for dataTypeID: String) -> Binding<Bool> {
        Binding(
            get: { enabledIDs.contains(dataTypeID) },
            set: { enabled in
                if enabled {
                    enabledIDs.insert(dataTypeID)
                } else {
                    enabledIDs.remove(dataTypeID)
                }
                BridgeDataSharingSettings.setEnabled(enabled, for: dataTypeID)
            }
        )
    }

    private func setAll(enabled: Bool) {
        enabledIDs = enabled ? Set(BridgeDataTypeDescriptor.all.map(\.id)) : []
        BridgeDataSharingSettings.setEnabledIDs(enabledIDs)
    }
}

private struct DataSourceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(title))
                Text(L10n.string(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}

private struct HealthSourceSettingsView: View {
    let source: HealthSourceDescriptor

    @State private var sourceEnabled: Bool
    @State private var enabledDataPoints: Set<String>

    init(source: HealthSourceDescriptor) {
        self.source = source
        _sourceEnabled = State(initialValue: HealthDataSourceSettings.isSourceEnabled(source.id))
        _enabledDataPoints = State(initialValue: Set(source.dataPointIDs.filter {
            HealthDataSourceSettings.isDataPointEnabled($0, for: source.id)
        }))
    }

    var body: some View {
        List {
            Section {
                Toggle(L10n.string("Daten dieser Quelle verwenden"), isOn: Binding(
                    get: { sourceEnabled },
                    set: setSourceEnabled
                ))
            } footer: {
                Text(L10n.string("Wenn die Quelle deaktiviert ist, werden ihre Werte auf dem Dashboard, in Diagrammen und bei der Bridge-Synchronisierung nicht berücksichtigt."))
            }

            if let stepCountID = HealthMetric.stepCount?.id,
               source.dataPointIDs.contains(stepCountID) {
                Section {
                    Toggle(L10n.string("Schritte dieser Quelle verwenden"), isOn: binding(for: stepCountID))
                        .disabled(!sourceEnabled)
                } header: {
                    Text(L10n.string("Doppelte Schritte vermeiden"))
                } footer: {
                    Text(L10n.string("Deaktiviere diesen Schalter zum Beispiel bei Huawei, wenn dieselben Schritte zusätzlich vom iPhone oder der Apple Watch kommen."))
                }
            }

            ForEach(groupedDataPoints, id: \.section) { group in
                Section(group.section) {
                    ForEach(group.points) { point in
                        Toggle(isOn: binding(for: point.id)) {
                            Label(point.title, systemImage: point.systemImage)
                        }
                        .disabled(!sourceEnabled)
                    }
                }
            }

            if source.dataPointIDs.contains(HealthDataPointDescriptor.workoutsID) {
                Section {
                    NavigationLink("Einzelne Trainings verwalten") {
                        WorkoutListView()
                    }
                }
            }

            Section {
                Button(L10n.string("Auswahl zurücksetzen")) {
                    sourceEnabled = true
                    HealthDataSourceSettings.setSource(source.id, enabled: true)
                    for id in source.dataPointIDs {
                        HealthDataSourceSettings.setDataPoint(id, for: source.id, enabled: true)
                    }
                    enabledDataPoints = source.dataPointIDs
                    invalidateCaches()
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groupedDataPoints: [(section: String, points: [HealthDataPointDescriptor])] {
        let stepCountID = HealthMetric.stepCount?.id
        let points = source.dataPointIDs
            .filter { $0 != stepCountID }
            .compactMap(HealthDataPointDescriptor.descriptor(id:))
        let sections = Dictionary(grouping: points, by: \.section)
        return sections.map { (section: $0.key, points: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.section < $1.section }
    }

    private func binding(for dataPointID: String) -> Binding<Bool> {
        Binding(
            get: { enabledDataPoints.contains(dataPointID) },
            set: { enabled in
                if enabled { enabledDataPoints.insert(dataPointID) }
                else { enabledDataPoints.remove(dataPointID) }
                HealthDataSourceSettings.setDataPoint(dataPointID, for: source.id, enabled: enabled)
                invalidateCaches()
            }
        )
    }

    private func setSourceEnabled(_ enabled: Bool) {
        sourceEnabled = enabled
        HealthDataSourceSettings.setSource(source.id, enabled: enabled)
        invalidateCaches()
    }

    private func invalidateCaches() {
    }
}

private struct AppleHealthWriteSettingsView: View {
    @AppStorage(HealthDataSourceSettings.writeWorkoutsKey) private var writeWorkouts = true
    @AppStorage(HealthDataSourceSettings.writeActiveEnergyKey) private var writeEnergy = true
    @AppStorage(HealthDataSourceSettings.writeWalkingDistanceKey) private var writeWalkingDistance = true
    @AppStorage(HealthDataSourceSettings.writeCyclingDistanceKey) private var writeCyclingDistance = true

    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("Trainings"), isOn: $writeWorkouts)
                Toggle(L10n.string("Aktive Kalorien"), isOn: $writeEnergy)
                    .disabled(!writeWorkouts)
                Toggle(L10n.string("Geh- und Laufdistanz"), isOn: $writeWalkingDistance)
                    .disabled(!writeWorkouts)
                Toggle(L10n.string("Raddistanz"), isOn: $writeCyclingDistance)
                    .disabled(!writeWorkouts)
            } header: {
                Text(L10n.string("HealthPit darf schreiben"))
            } footer: {
                Text(L10n.string("Diese Schalter gelten für neue Exporte. Bereits vorhandene Daten bleiben unverändert."))
            }

            Section {
                Button(L10n.string("Health-App-Berechtigungen öffnen")) {
                    if let url = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(url)
                    }
                }
            } footer: {
                Text(L10n.string("Leserechte verwaltet iOS in der Health-App. HealthPit kann sie aus Datenschutzgründen nicht selbst anzeigen oder erweitern."))
            }

            Section {
                Button(L10n.string("Von HealthPit geschriebene Daten löschen"), role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(isDeleting)

                if isDeleting { ProgressView() }
            } footer: {
                Text(L10n.string("Es werden nur Daten gelöscht, die HealthPit selbst in Apple Health gespeichert hat. Daten von Huawei, Apple Watch oder anderen Apps bleiben erhalten."))
            }
        }
        .navigationTitle(L10n.string("Apple Health"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L10n.string("HealthPit-Daten aus Apple Health löschen?"),
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button(L10n.string("Aus Apple Health löschen"), role: .destructive) {
                Task { await deleteWrittenData() }
            }
            Button(L10n.string("Abbrechen"), role: .cancel) {}
        }
        .alert(L10n.string("Apple Health"), isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button(L10n.string("OK"), role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    @MainActor
    private func deleteWrittenData() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let count = try await HealthKitManager.shared.deleteDataWrittenByHealthpit()
            message = L10n.format("%lld von HealthPit geschriebene Objekte wurden gelöscht.", count)
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct LocalDataSourcesSettingsView: View {
    @State private var sourcePendingDeletion: LocalWorkout.Source?
    @State private var message: String?

    // Garmin fehlt hier absichtlich: es holt nichts mehr ab, seit die Bridge
    // weg ist. Der Enum-Fall bleibt, damit frueher importierte Workouts
    // weiterhin dekodierbar sind und ihre Herkunft behalten.
    private let sources: [LocalWorkout.Source] = [.manual, .gpx, .tcx, .gympit, .appleHealth]

    var body: some View {
        List {
            Section {
                ForEach(sources, id: \.rawValue) { source in
                    Button(role: .destructive) {
                        sourcePendingDeletion = source
                    } label: {
                        Label(L10n.string("\(source.displayName)-Trainings löschen"), systemImage: "trash")
                    }
                }
            } footer: {
                Text(L10n.string("Gelöscht werden die lokal auf diesem iPhone gespeicherten Kopien. Daten in Apple Health oder der Docker-Bridge werden nicht verändert."))
            }
        }
        .navigationTitle(L10n.string("Lokale Daten"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L10n.string("Lokale Trainings löschen?"),
                            isPresented: Binding(
                                get: { sourcePendingDeletion != nil },
                                set: { if !$0 { sourcePendingDeletion = nil } }
                            ),
                            titleVisibility: .visible) {
            if let sourcePendingDeletion {
                Button(L10n.string("\(sourcePendingDeletion.displayName) löschen"), role: .destructive) {
                    Task { await delete(sourcePendingDeletion) }
                }
            }
            Button(L10n.string("Abbrechen"), role: .cancel) {}
        }
        .alert(L10n.string("Lokale Daten"), isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button(L10n.string("OK"), role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    @MainActor
    private func delete(_ source: LocalWorkout.Source) async {
        await ManualWorkoutWriter.delete(source: source)
        sourcePendingDeletion = nil
        message = L10n.string("Lokale Trainings wurden gelöscht:") + " \(source.displayName)"
    }
}
