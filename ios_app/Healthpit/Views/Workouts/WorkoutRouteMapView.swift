//
//  WorkoutRouteMapView.swift
//  Healthpit
//
//  Workout-Karte mit Vollbildmodus und farbiger Pace-/Tempo-Linie.
//

import MapKit
import SwiftUI

struct WorkoutRouteMapPoint: Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct WorkoutRouteMapView: View {
    let points: [WorkoutRouteMapPoint]
    let splits: [WorkoutSplit]
    let isCycling: Bool

    @State private var showingFullMap = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            routeMap
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                showingFullMap = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(10)
        }
        .sheet(isPresented: $showingFullMap) {
            NavigationStack {
                routeMap
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Karte")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") { showingFullMap = false }
                        }
                    }
            }
        }
    }

    private var routeMap: some View {
        Map(initialPosition: .region(region)) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(segment.color, lineWidth: 5)
            }
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    private var segments: [WorkoutRouteSegment] {
        guard points.count > 1 else { return [] }
        let splitValues = splits.map { splitValue($0) }
        let minValue = splitValues.min() ?? 0
        let maxValue = splitValues.max() ?? minValue
        let span = max(maxValue - minValue, 0.0001)

        let splitSegments = splits.compactMap { split -> WorkoutRouteSegment? in
            guard let start = split.start, let end = split.end else { return nil }
            let coords = points
                .filter { point in
                    guard let timestamp = point.timestamp else { return false }
                    return timestamp >= start && timestamp <= end
                }
                .map(\.coordinate)
            guard coords.count > 1 else { return nil }
            let ratio = (splitValue(split) - minValue) / span
            return WorkoutRouteSegment(coordinates: coords, color: paceColor(ratio: ratio))
        }

        if !splitSegments.isEmpty {
            return splitSegments
        }
        return [WorkoutRouteSegment(coordinates: coordinates, color: .green)]
    }

    private var region: MKCoordinateRegion {
        let coords = coordinates
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

    private func splitValue(_ split: WorkoutSplit) -> Double {
        if isCycling {
            return 1 / max(split.averageSpeedKmh, 0.1)
        }
        return split.paceSecondsPerKm
    }

    private func paceColor(ratio: Double) -> Color {
        let clamped = min(max(ratio, 0), 1)
        return Color(hue: 0.33 * (1 - clamped), saturation: 0.85, brightness: 0.9)
    }
}

private struct WorkoutRouteSegment: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
}
