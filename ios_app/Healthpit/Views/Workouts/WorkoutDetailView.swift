//
//  WorkoutDetailView.swift
//  Healthpit
//
//  Detail eines Workouts: GPS-Route auf der Karte (falls vorhanden) plus alle
//  verfügbaren Kennzahlen (Distanz, Kalorien, Puls Ø/Max/Min, Schritte …).
//

import SwiftUI
import MapKit
import Charts

struct WorkoutDetailView: View {
    let workout: WorkoutSummary
    private let health = HealthKitManager.shared

    @State private var detail: WorkoutDetail?
    @State private var isLoading = false
    @State private var showingSplitTable = false

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if routeMapPoints.count > 1 {
                    WorkoutRouteMapView(points: routeMapPoints,
                                        splits: detail?.splits ?? [],
                                        isCycling: isCycling)
                }

                if isLoading && detail == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let stats = detail?.stats, !stats.isEmpty {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(stats) { statTile($0) }
                    }
                } else if !isLoading {
                    Text("Keine weiteren Kennzahlen verfügbar.")
                        .foregroundStyle(.secondary)
                }

                if let weather = workout.weather, !weather.summary.isEmpty {
                    Label(weather.summary, systemImage: "cloud.sun.fill")
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let splits = detail?.splits, !splits.isEmpty {
                    splitSection(splits)
                }

                if let heartRate = detail?.heartRate, detail?.splits.isEmpty != false {
                    heartRateSection(heartRate)
                }
            }
            .padding()
        }
        .navigationTitle(workout.activityName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
            SyncRefreshStatusStore.markLocalRefresh()
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.symbol)
                .font(.largeTitle)
                .foregroundStyle(HealthCategory.workouts.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityName).font(.title2.bold())
                Text(workout.start, format: .dateTime.weekday().day().month().year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func routeMap(_ coords: [CLLocationCoordinate2D]) -> some View {
        Map(initialPosition: .region(region(for: coords))) {
            MapPolyline(coordinates: coords)
                .stroke(HealthCategory.workouts.tint, lineWidth: 4)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
    }

    private func statTile(_ stat: WorkoutStat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: stat.systemImage)
                .foregroundStyle(HealthCategory.workouts.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(stat.value).font(.headline)
                Text(stat.localizedLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func splitSection(_ splits: [WorkoutSplit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trainingsverlauf")
                .font(.headline)
            WorkoutSampleTimelineChartView(samples: timelineSamples,
                                           heartRate: detail?.heartRate,
                                           isCycling: isCycling)

            DisclosureGroup("Kilometer anzeigen", isExpanded: $showingSplitTable) {
                VStack(spacing: 0) {
                    ForEach(splits) { split in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("km \(split.id)")
                                    .font(.subheadline.bold())
                                Text(splitDurationText(split.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(isCycling ? speedText(split.averageSpeedKmh) : paceText(split.paceSecondsPerKm))
                                    .font(.subheadline.bold())
                                Text(splitHeartRate(split).map { "Ø \(Int($0.rounded())) bpm" } ?? "Puls -")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 9)
                        if split.id != splits.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func heartRateSection(_ heartRate: HeartRateSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Puls")
                .font(.headline)
            HStack(spacing: 12) {
                statTile(WorkoutStat(label: "Min Puls", value: "\(Int(heartRate.minimum.rounded())) bpm", systemImage: "heart"))
                statTile(WorkoutStat(label: "Max Puls", value: "\(Int(heartRate.maximum.rounded())) bpm", systemImage: "heart.fill"))
            }
            if !heartRate.samples.isEmpty {
                Chart(heartRate.samples) { point in
                    LineMark(
                        x: .value("Zeit", point.date),
                        y: .value("bpm", point.bpm)
                    )
                }
                .frame(height: 180)
                .chartYAxisLabel("bpm")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private var routeCoordinates: [CLLocationCoordinate2D]? {
        detail?.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var routeMapPoints: [WorkoutRouteMapPoint] {
        (detail?.route ?? []).map {
            WorkoutRouteMapPoint(latitude: $0.latitude,
                                 longitude: $0.longitude,
                                 timestamp: $0.timestamp)
        }
    }

    private var timelineSamples: [WorkoutTimelineSample] {
        (detail?.route ?? []).map {
            WorkoutTimelineSample(timestamp: $0.timestamp,
                                  latitude: $0.latitude,
                                  longitude: $0.longitude,
                                  elevation: $0.elevation,
                                  heartRate: nil)
        }
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.005))
        return MKCoordinateRegion(center: center, span: span)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await health.workoutDetail(for: workout.uuid)
    }

    private var isCycling: Bool {
        workout.activityName.localizedCaseInsensitiveContains("rad")
            || workout.activityName.localizedCaseInsensitiveContains("cycling")
    }

    private func paceText(_ secondsPerKm: TimeInterval) -> String {
        let total = Int(secondsPerKm.rounded())
        return "\(total / 60):" + String(format: "%02d /km", total % 60)
    }

    private func speedText(_ value: Double) -> String {
        String(format: "%.1f km/h", value)
    }

    private func splitDurationText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private func splitHeartRate(_ split: WorkoutSplit) -> Double? {
        guard let start = split.start,
              let end = split.end,
              let samples = detail?.heartRate?.samples,
              !samples.isEmpty else {
            return nil
        }
        let values = samples
            .filter { $0.date >= start && $0.date <= end }
            .map(\.bpm)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func elevationGainBySplit(for splits: [WorkoutSplit]) -> [Int: Double] {
        Dictionary(uniqueKeysWithValues: splits.compactMap { split in
            guard let gain = elevationGain(for: split), gain > 0 else { return nil }
            return (split.id, gain)
        })
    }

    private func elevationGain(for split: WorkoutSplit) -> Double? {
        guard let route = detail?.route,
              let start = split.start,
              let end = split.end else {
            return nil
        }
        let points = route
            .filter { point in
                guard let timestamp = point.timestamp else { return false }
                return timestamp >= start && timestamp <= end && point.elevation != nil
            }
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        guard points.count > 1 else { return nil }
        var gain = 0.0
        var previous = points[0].elevation ?? 0
        for point in points.dropFirst() {
            guard let elevation = point.elevation else { continue }
            gain += max(elevation - previous, 0)
            previous = elevation
        }
        return gain
    }
}
