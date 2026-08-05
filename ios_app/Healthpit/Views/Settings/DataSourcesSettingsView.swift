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
                                  subtitle: "Lesen, schreiben und Healthpit-Daten löschen",
                                  systemImage: "heart.fill",
                                  tint: .red)
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
                Text("Schnittstellen")
            } footer: {
                Text("Die Einstellungen werden auf diesem iPhone gespeichert. Zur Bridge gelangen nur Werte aus aktivierten Quellen.")
            }

            Section("Erkannte Apple-Health-Quellen") {
                if isLoading && sources.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Quellen werden gesucht …")
                        Spacer()
                    }
                } else if sources.isEmpty {
                    ContentUnavailableView("Keine Quellen gefunden",
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

            Section("Auf diesem iPhone") {
                NavigationLink {
                    LocalDataSourcesSettingsView()
                } label: {
                    DataSourceRow(title: "Lokale Daten & Bridge",
                                  subtitle: "Manuell, GPX/TCX und GymPit",
                                  systemImage: "internaldrive.fill",
                                  tint: .orange)
                }

                Button("Alle lokalen App-Daten löschen", role: .destructive) {
                    showingDeleteLocalConfirmation = true
                }
            }
        }
        .navigationTitle("Datenquellen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSources() }
        .refreshable { await loadSources() }
        .confirmationDialog("Alle lokalen App-Daten löschen?",
                            isPresented: $showingDeleteLocalConfirmation,
                            titleVisibility: .visible) {
            Button("Lokale Daten löschen", role: .destructive) {
                Task { await deleteLocalData() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Manuelle und importierte Trainings sowie lokale Zwischenspeicher werden gelöscht. Apple Health und die Docker-Bridge bleiben unverändert.")
        }
        .alert("Datenquellen", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
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
        await LocalWorkoutStore.shared.deleteAll()
        await HealthWorkoutCacheStore.shared.clear()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: BridgeSettings.hiddenHealthWorkoutIDsKey)
        actionMessage = L10n.string("Die lokalen App-Daten wurden gelöscht.")
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
                Toggle("Daten dieser Quelle verwenden", isOn: Binding(
                    get: { sourceEnabled },
                    set: setSourceEnabled
                ))
            } footer: {
                Text("Wenn die Quelle deaktiviert ist, werden ihre Werte auf dem Dashboard, in Diagrammen und bei der Bridge-Synchronisierung nicht berücksichtigt.")
            }

            if let stepCountID = HealthMetric.stepCount?.id,
               source.dataPointIDs.contains(stepCountID) {
                Section {
                    Toggle("Schritte dieser Quelle verwenden", isOn: binding(for: stepCountID))
                        .disabled(!sourceEnabled)
                } header: {
                    Text("Doppelte Schritte vermeiden")
                } footer: {
                    Text("Deaktiviere diesen Schalter zum Beispiel bei Huawei, wenn dieselben Schritte zusätzlich vom iPhone oder der Apple Watch kommen.")
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
                Button("Auswahl zurücksetzen") {
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
        Task { await HealthWorkoutCacheStore.shared.clear() }
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
                Toggle("Trainings", isOn: $writeWorkouts)
                Toggle("Aktive Kalorien", isOn: $writeEnergy)
                    .disabled(!writeWorkouts)
                Toggle("Geh- und Laufdistanz", isOn: $writeWalkingDistance)
                    .disabled(!writeWorkouts)
                Toggle("Raddistanz", isOn: $writeCyclingDistance)
                    .disabled(!writeWorkouts)
            } header: {
                Text("Healthpit darf schreiben")
            } footer: {
                Text("Diese Schalter gelten für neue Exporte. Bereits vorhandene Daten bleiben unverändert.")
            }

            Section {
                Button("Health-App-Berechtigungen öffnen") {
                    if let url = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(url)
                    }
                }
            } footer: {
                Text("Leserechte verwaltet iOS in der Health-App. Healthpit kann sie aus Datenschutzgründen nicht selbst anzeigen oder erweitern.")
            }

            Section {
                Button("Von Healthpit geschriebene Daten löschen", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(isDeleting)

                if isDeleting { ProgressView() }
            } footer: {
                Text("Es werden nur Daten gelöscht, die Healthpit selbst in Apple Health gespeichert hat. Daten von Huawei, Apple Watch oder anderen Apps bleiben erhalten.")
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Healthpit-Daten aus Apple Health löschen?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Aus Apple Health löschen", role: .destructive) {
                Task { await deleteWrittenData() }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Apple Health", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
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
            await HealthWorkoutCacheStore.shared.clear()
            message = L10n.format("%lld von Healthpit geschriebene Objekte wurden gelöscht.", count)
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
                        Label("\(source.displayName)-Trainings löschen", systemImage: "trash")
                    }
                }
            } footer: {
                Text("Gelöscht werden die lokal auf diesem iPhone gespeicherten Kopien. Daten in Apple Health oder der Docker-Bridge werden nicht verändert.")
            }
        }
        .navigationTitle("Lokale Daten")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Lokale Trainings löschen?",
                            isPresented: Binding(
                                get: { sourcePendingDeletion != nil },
                                set: { if !$0 { sourcePendingDeletion = nil } }
                            ),
                            titleVisibility: .visible) {
            if let sourcePendingDeletion {
                Button("\(sourcePendingDeletion.displayName) löschen", role: .destructive) {
                    Task { await delete(sourcePendingDeletion) }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Lokale Daten", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    @MainActor
    private func delete(_ source: LocalWorkout.Source) async {
        await LocalWorkoutStore.shared.delete(source: source)
        await HealthWorkoutCacheStore.shared.clear()
        sourcePendingDeletion = nil
        message = L10n.string("Lokale Trainings wurden gelöscht:") + " \(source.displayName)"
    }
}
