//
//  EquipmentCard.swift
//  Healthpit
//
//  Startseiten-Kachel der Ausrüstung.
//
//  Zeigt, was als Nächstes ansteht: fälliges zuerst, sonst das Stück mit der
//  höchsten Laufleistung. Eine Kachel, die nur „3 Stück" sagt, hätte niemand
//  je angesehen.
//

import SwiftUI

struct EquipmentCard: View {
    let size: DashboardWidgetSize

    @State private var items: [Equipment] = []
    @State private var workouts: [UnifiedWorkout] = []
    @State private var overrides: [String: String?] = [:]
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shoe.fill")
                    .foregroundStyle(.brown)
                Text(L10n.string("Ausrüstung"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(headline)
                .font(.title2.bold())
                .foregroundStyle(isOverdue ? Color.red : Color.brown)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if size != .small {
                Text(subline)
                    .font(.caption2)
                    .foregroundStyle(isOverdue ? .red : .secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .professionalCard(tint: .brown)
        .task { await reload() }
    }

    /// Das Stück, das am dringendsten dran ist – sonst das meistgelaufene.
    private var highlight: (item: Equipment, usage: EquipmentUsage)? {
        let inUse = items.filter { !$0.isRetired }
        let measured = inUse.map { item in
            (item: item,
             usage: EquipmentRegistry.usage(of: item,
                                            workouts: workouts,
                                            allEquipment: items,
                                            overrides: overrides))
        }
        let due = measured.filter {
            ($0.usage.replacementProgress($0.item) ?? 0) >= 0.9
                || ($0.usage.serviceProgress($0.item) ?? 0) >= 1
        }
        if let worst = due.max(by: { ($0.usage.replacementProgress($0.item) ?? 0)
                                     < ($1.usage.replacementProgress($1.item) ?? 0) }) {
            return worst
        }
        return measured.max { $0.usage.distanceKm < $1.usage.distanceKm }
    }

    private var isOverdue: Bool {
        guard let highlight else { return false }
        return (highlight.usage.replacementProgress(highlight.item) ?? 0) >= 0.9
            || (highlight.usage.serviceProgress(highlight.item) ?? 0) >= 1
    }

    private var headline: String {
        guard let highlight, highlight.item.kind.tracksDistance,
              highlight.usage.distanceKm > 0 else {
            return items.isEmpty ? "–" : "\(items.filter { !$0.isRetired }.count)"
        }
        return WorkoutUnits.distance(km: highlight.usage.distanceKm, fractionDigits: 0)
    }

    private var subline: String {
        guard let highlight else {
            return isLoading ? "" : L10n.string("Noch nichts hinterlegt")
        }
        if isOverdue {
            return L10n.format("%@ · fällig", highlight.item.displayName)
        }
        return highlight.item.displayName
    }

    private func reload() async {
        items = await EquipmentRegistry.load()
        workouts = await HealthQuery.shared.unifiedWorkouts()
        if let store = try? await HealthPitData.shared.store(),
           let map = try? await store.equipmentOverrides() {
            overrides = map
        }
        isLoading = false
    }
}
