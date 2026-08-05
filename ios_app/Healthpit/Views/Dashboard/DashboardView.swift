//
//  DashboardView.swift
//  Healthpit
//
//  Screen 1 – Startseite: scrollbares Raster aus Kategorie-Kacheln. Tippen auf
//  eine Kachel öffnet die Kategorie-Detailliste; die Workout-Kachel führt zur
//  Workout-Liste. Pull-to-refresh lädt die Kacheln neu.
//

import SwiftUI

struct DashboardView: View {

    private let dashboardColumnCount = 4
    private let dashboardSpacing: CGFloat = 10

    /// Wird hochgezählt, um per `.id` alle Kacheln zum Neuladen zu zwingen.
    @State private var reloadToken = 0
    @State private var showingSettings = false
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var showingSyncStatus = false
    @State private var needsHealthAccess = false
    @AppStorage(DashboardItem.storageKey) private var dashboardOrderRaw = DashboardItem.encode(DashboardItem.defaultOrder)
    @AppStorage(DashboardItem.sizeStorageKey) private var dashboardSizesRaw = ""
    @AppStorage(DashboardItem.hiddenStorageKey) private var dashboardHiddenRaw = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: dashboardSpacing) {
                    if showingSyncStatus || SyncActivity.shared.isRunning {
                        SyncRefreshStatusView()
                    }

                    if needsHealthAccess {
                        HealthAccessCard(size: .wide) {
                            Task { await refreshHealthAccessState() }
                        }
                        .frame(height: DashboardWidgetSize.wide.minHeight)
                    }

                    ForEach(Array(dashboardRows.enumerated()), id: \.offset) { _, row in
                        GeometryReader { proxy in
                            HStack(alignment: .top, spacing: dashboardSpacing) {
                                ForEach(row) { item in
                                    let size = widgetSize(for: item)
                                    dashboardTile(item)
                                        .frame(width: tileWidth(for: size, totalWidth: proxy.size.width),
                                               height: size.minHeight)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(height: rowHeight(for: row))
                    }
                }
                .padding()
            }
            .navigationTitle("Fitness")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await syncBridge() }
                    } label: {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isSyncing)
                    .accessibilityLabel("Synchronisieren")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showingSettings) {
                BridgeSettingsView()
            }
            .alert("Synchronisierung", isPresented: Binding(
                get: { syncMessage != nil },
                set: { if !$0 { syncMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncMessage ?? "")
            }
            .navigationDestination(for: HealthCategory.self) { category in
                CategoryDetailView(category: category)
            }
            .refreshable {
                await refreshLocalAppleHealth()
                SyncRefreshStatusStore.markLocalRefresh()
            }
            .task { await refreshHealthAccessState() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4).onChanged { _ in
                    showingSyncStatus = false
                }
            )
            .onChange(of: showingSettings) { _, isShowing in
                if isShowing {
                    showingSyncStatus = false
                } else {
                    Task { await refreshLocalAppleHealth() }
                }
            }
            .onDisappear { showingSyncStatus = false }
        }
    }

    @ViewBuilder
    private func dashboardTile(_ item: DashboardItem) -> some View {
        let size = DashboardItem.size(for: item, rawValue: dashboardSizesRaw)
        if let category = item.category {
            NavigationLink(value: category) {
                CategoryCard(category: category, size: size)
                    .id("\(category.id)-\(reloadToken)")
            }
            .buttonStyle(.plain)
        } else {
            switch item {
            case .workouts:
                NavigationLink {
                    WorkoutListView()
                } label: {
                    WorkoutCard(size: size)
                        .id("workouts-\(reloadToken)")
                }
                .buttonStyle(.plain)
            case .sleep:
                NavigationLink {
                    SleepDetailView()
                } label: {
                    SleepCard(size: size)
                        .id("sleep-\(reloadToken)")
                }
                .buttonStyle(.plain)
            case .cycle:
                NavigationLink {
                    CycleDetailView()
                } label: {
                    CycleCard(size: size)
                        .id("cycle-\(reloadToken)")
                }
                .buttonStyle(.plain)
            case .records:
                NavigationLink {
                    RecordsView()
                } label: {
                    RecordsCard(size: size)
                        .id("records-\(reloadToken)")
                }
                .buttonStyle(.plain)
            case .activity, .heart, .body, .nutrition, .vitals:
                EmptyView()
            }
        }
    }

    private var dashboardRows: [[DashboardItem]] {
        var rows: [[DashboardItem]] = []
        var current: [DashboardItem] = []
        var usedColumns = 0

        for item in DashboardItem.visible(from: dashboardOrderRaw, hiddenRaw: dashboardHiddenRaw) {
            let columns = widgetSize(for: item).columns
            if usedColumns + columns > dashboardColumnCount, !current.isEmpty {
                rows.append(current)
                current = []
                usedColumns = 0
            }
            current.append(item)
            usedColumns += columns
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private func widgetSize(for item: DashboardItem) -> DashboardWidgetSize {
        DashboardItem.size(for: item, rawValue: dashboardSizesRaw)
    }

    private func rowHeight(for row: [DashboardItem]) -> CGFloat {
        row.map { widgetSize(for: $0).minHeight }.max() ?? 0
    }

    private func tileWidth(for size: DashboardWidgetSize, totalWidth: CGFloat) -> CGFloat {
        let unit = (totalWidth - dashboardSpacing * CGFloat(dashboardColumnCount - 1)) / CGFloat(dashboardColumnCount)
        return unit * CGFloat(size.columns) + dashboardSpacing * CGFloat(size.columns - 1)
    }

    private func syncBridge() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let count = try await BridgeSyncService.shared.syncNow()
            reloadToken += 1
            syncMessage = L10n.format("%lld Werte synchronisiert.", count)
        } catch {
            syncMessage = BridgeErrorText.message(for: error)
        }
        showingSyncStatus = true
    }

    private func refreshLocalAppleHealth() async {
        await HealthpitPreloadService.shared.refreshLocalAppleHealthCaches()
        reloadToken += 1
    }

    private func refreshHealthAccessState() async {
        let pending = await HealthKitManager.shared.needsAuthorizationRequest()
        needsHealthAccess = pending
        if !pending {
            reloadToken += 1
        }
    }
}
