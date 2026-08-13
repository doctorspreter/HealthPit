//
//  WorkoutFileImporter.swift
//  Healthpit
//
//  Importiert GPX- und TCX-Dateien als lokale Workouts.
//

import CoreLocation
import Foundation

/// Ergebnis der Dateianalyse. `containsDate` bleibt getrennt vom Workout, weil
/// `LocalWorkout` aus Kompatibilitaetsgruenden immer einen Startwert braucht.
/// Eine GPX-Datei ohne Zeitstempel darf dadurch nicht mehr stillschweigend als
/// Training von "jetzt" gespeichert werden.
struct WorkoutFileImport: Identifiable {
    let id = UUID()
    let workout: LocalWorkout
    let containsDate: Bool
}

enum WorkoutFileImporter {
    static func analyze(from url: URL) throws -> WorkoutFileImport {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let parser = WorkoutXMLParser(source: ext == "tcx" ? .tcx : .gpx)
        let points = try parser.parse(data: data)
        // GPX/TCX-Punkte stehen bereits in Streckenreihenfolge. Das ist gerade
        // bei komplett undatierten Dateien wichtig und vermeidet, dass Punkte
        // ohne Zeitstempel vor die restliche Route sortiert werden.
        let timestamps = points.compactMap(\.timestamp)
        let containsDate = !timestamps.isEmpty || parser.documentDate != nil
        let start = timestamps.min() ?? parser.documentDate ?? .now
        let fallbackEnd = timestamps.max() ?? start
        let end = parser.totalTimeSeconds.map { start.addingTimeInterval($0) } ?? fallbackEnd
        let distanceKm = parser.distanceMeters.map { $0 / 1000 } ?? routeDistance(points)
        let heartRates = points.compactMap(\.heartRate)

        let workout = LocalWorkout(id: UUID(),
                                   source: ext == "tcx" ? .tcx : .gpx,
                                   sport: parser.detectedSport ?? inferredSport(from: url),
                                   title: url.deletingPathExtension().lastPathComponent,
                                   start: start,
                                   end: end,
                                   distanceKm: distanceKm > 0 ? distanceKm : nil,
                                   energyKcal: parser.calories,
                                   averageHeartRate: average(heartRates),
                                   maxHeartRate: heartRates.max(),
                                   notes: "",
                                   weather: nil,
                                   injury: nil,
                                   route: points)
        return WorkoutFileImport(workout: workout, containsDate: containsDate)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func routeDistance(_ points: [LocalRoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var meters = 0.0
        for index in 1..<points.count {
            let a = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
            let b = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
            meters += a.distance(from: b)
        }
        return meters / 1000
    }

    private static func inferredSport(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        if name.contains("rad") || name.contains("bike") || name.contains("cycle") || name.contains("ride") {
            return "Radfahren"
        }
        if name.contains("walk") || name.contains("gehen") {
            return "Gehen"
        }
        return "Laufen"
    }
}

final class WorkoutXMLParser: NSObject, XMLParserDelegate {
    private(set) var detectedSport: String?
    private(set) var totalTimeSeconds: Double?
    private(set) var distanceMeters: Double?
    private(set) var calories: Double?
    private(set) var documentDate: Date?
    private let source: LocalWorkout.Source
    private var points: [LocalRoutePoint] = []
    private var currentPoint: LocalRoutePoint?
    private var currentText = ""
    private var inTrackpoint = false
    private var inHeartRate = false

    init(source: LocalWorkout.Source) {
        self.source = source
    }

    func parse(data: Data) throws -> [LocalRoutePoint] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        return points
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        let name = elementName.lowercased()

        if source == .gpx, name == "trkpt" {
            currentPoint = LocalRoutePoint(latitude: Double(attributeDict["lat"] ?? "") ?? 0,
                                           longitude: Double(attributeDict["lon"] ?? "") ?? 0,
                                           elevation: nil,
                                           timestamp: nil,
                                           heartRate: nil)
        }

        if source == .tcx, name == "trackpoint" {
            inTrackpoint = true
            currentPoint = LocalRoutePoint(latitude: 0,
                                           longitude: 0,
                                           elevation: nil,
                                           timestamp: nil,
                                           heartRate: nil)
        }

        if source == .tcx, name == "activity", let sport = attributeDict["Sport"] ?? attributeDict["sport"] {
            detectedSport = normalizeSport(sport)
        }

        if source == .tcx, name == "lap",
           let value = attributeDict["StartTime"] ?? attributeDict["starttime"] {
            documentDate = documentDate ?? parseDate(value)
        }

        if name == "heartratebpm" || name == "heartrate" || name == "hr" {
            inHeartRate = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "trkpt":
            appendCurrentPoint()
        case "trackpoint":
            appendCurrentPoint()
            inTrackpoint = false
        case "time":
            if currentPoint != nil {
                currentPoint?.timestamp = parseDate(text)
            } else {
                documentDate = documentDate ?? parseDate(text)
            }
        case "id":
            if source == .tcx {
                documentDate = documentDate ?? parseDate(text)
            }
        case "ele", "altitudemeters":
            currentPoint?.elevation = Double(text)
        case "totaltimeseconds":
            totalTimeSeconds = Double(text)
        case "distancemeters":
            if let value = Double(text) {
                distanceMeters = max(distanceMeters ?? 0, value)
            }
        case "calories":
            calories = Double(text)
        case "latitudedegrees":
            if inTrackpoint { currentPoint?.latitude = Double(text) ?? 0 }
        case "longitudedegrees":
            if inTrackpoint { currentPoint?.longitude = Double(text) ?? 0 }
        case "value":
            if inHeartRate { currentPoint?.heartRate = Double(text) }
        case "type", "sport":
            if detectedSport == nil { detectedSport = normalizeSport(text) }
        case "heartratebpm", "heartrate", "hr":
            // GPX-Erweiterungen schreiben den Puls oft direkt in `<hr>`, TCX
            // dagegen in ein verschachteltes `<Value>`.
            if let value = Double(text) {
                currentPoint?.heartRate = value
            }
            inHeartRate = false
        default:
            break
        }
        currentText = ""
    }

    private func appendCurrentPoint() {
        guard let point = currentPoint,
              point.latitude != 0,
              point.longitude != 0 else {
            currentPoint = nil
            return
        }
        points.append(point)
        currentPoint = nil
    }

    private func normalizeSport(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("bik") || lower.contains("cycl") || lower.contains("rad") {
            return "Radfahren"
        }
        if lower.contains("walk") || lower.contains("geh") {
            return "Gehen"
        }
        if lower.contains("run") || lower.contains("lauf") {
            return "Laufen"
        }
        return value.isEmpty ? "Laufen" : value
    }

    private func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
