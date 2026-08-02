//
//  DashboardItem.swift
//  Healthpit
//
//  Konfigurierbare Kacheln der Startseite.
//

import CoreGraphics
import Foundation

enum DashboardItem: String, CaseIterable, Identifiable {
    case activity
    case heart
    case body
    case nutrition
    case vitals
    case workouts
    case sleep
    case records

    var id: String { rawValue }

    static let storageKey = "dashboardCardOrder"
    static let sizeStorageKey = "dashboardCardSizes"

    static var defaultOrder: [DashboardItem] {
        [.activity, .workouts, .sleep, .heart, .records, .body, .nutrition, .vitals]
    }

    static func ordered(from rawValue: String) -> [DashboardItem] {
        let stored = rawValue
            .split(separator: ",")
            .compactMap { DashboardItem(rawValue: String($0)) }
        let missing = defaultOrder.filter { !stored.contains($0) }
        let combined = stored + missing
        return combined.isEmpty ? defaultOrder : combined
    }

    static func encode(_ items: [DashboardItem]) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }

    static func sizes(from rawValue: String) -> [DashboardItem: DashboardWidgetSize] {
        var out: [DashboardItem: DashboardWidgetSize] = [:]
        for part in rawValue.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2,
                  let item = DashboardItem(rawValue: pair[0]),
                  let size = DashboardWidgetSize(rawValue: pair[1]) else {
                continue
            }
            out[item] = size
        }
        return out
    }

    static func encodeSizes(_ sizes: [DashboardItem: DashboardWidgetSize]) -> String {
        DashboardItem.allCases.compactMap { item in
            guard let size = sizes[item] else { return nil }
            return "\(item.rawValue)=\(size.rawValue)"
        }
        .joined(separator: ",")
    }

    static func size(for item: DashboardItem, rawValue: String) -> DashboardWidgetSize {
        sizes(from: rawValue)[item] ?? .medium
    }

    var title: String {
        switch self {
        case .activity: return HealthCategory.activity.title
        case .heart: return HealthCategory.heart.title
        case .body: return HealthCategory.body.title
        case .nutrition: return HealthCategory.nutrition.title
        case .vitals: return HealthCategory.vitals.title
        case .workouts: return L10n.string("Workouts")
        case .sleep: return L10n.string("Schlaf")
        case .records: return L10n.string("Rekorde")
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return HealthCategory.activity.systemImage
        case .heart: return HealthCategory.heart.systemImage
        case .body: return HealthCategory.body.systemImage
        case .nutrition: return HealthCategory.nutrition.systemImage
        case .vitals: return HealthCategory.vitals.systemImage
        case .workouts: return "figure.run"
        case .sleep: return "bed.double.fill"
        case .records: return "trophy.fill"
        }
    }

    var category: HealthCategory? {
        switch self {
        case .activity: return .activity
        case .heart: return .heart
        case .body: return .body
        case .nutrition: return .nutrition
        case .vitals: return .vitals
        case .workouts, .sleep, .records: return nil
        }
    }
}

enum DashboardWidgetSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "1x1"
        case .medium: return "2x2"
        case .wide: return "4x2"
        }
    }

    var columns: Int {
        switch self {
        case .small: return 1
        case .medium: return 2
        case .wide: return 4
        }
    }

    var rows: Int {
        switch self {
        case .small, .wide: return 1
        case .medium: return 2
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .small: return 88
        case .medium: return 170
        case .wide: return 150
        }
    }

    var isCompact: Bool { self == .small || self == .wide }
}
