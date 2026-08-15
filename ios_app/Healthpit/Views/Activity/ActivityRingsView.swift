//
//  ActivityRingsView.swift
//  Healthpit
//
//  Die Ringe und Zielkarten der Aktivitaetsseite. Bewusst nachgebaut statt aus
//  Apple Health uebernommen: die Ringziele gibt Apple nicht heraus, die Ziele
//  hier gehoeren der App — und damit auch Home Assistant.
//

import SwiftUI

struct ActivityRingsView: View {
    let goals: [ActivityGoal]
    /// Erreichter Wert je Ziel, in HealthKit-Einheit.
    let values: [UUID: Double]
    var lineWidth: CGFloat = 13
    var diameter: CGFloat = 148

    var body: some View {
        ZStack {
            ForEach(Array(goals.prefix(ActivityGoalStore.maximumRingCount).enumerated()),
                    id: \.element.id) { index, goal in
                ring(for: goal, index: index)
            }
            centerLabel
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.55), value: values)
    }

    private func ring(for goal: ActivityGoal, index: Int) -> some View {
        let inset = CGFloat(index) * (lineWidth + 6)
        let size = diameter - inset * 2
        let progress = progress(for: goal)
        return ZStack {
            Circle()
                .stroke(goal.tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(
                    AngularGradient(colors: [goal.tint.opacity(0.75), goal.tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            // Ueber dem Ziel wird der Ring nicht laenger, sondern bekommt einen
            // zweiten, helleren Bogen — sonst waere "geschafft" und "weit
            // uebererfuellt" nicht zu unterscheiden.
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(.white.opacity(0.55),
                            style: StrokeStyle(lineWidth: lineWidth * 0.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }

    private var centerLabel: some View {
        let ringGoals = Array(goals.prefix(ActivityGoalStore.maximumRingCount))
        let done = ringGoals.filter { progress(for: $0) >= 1 }.count
        return VStack(spacing: 1) {
            Text("\(done)/\(ringGoals.count)")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(L10n.string("Ziele"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func progress(for goal: ActivityGoal) -> Double {
        guard goal.target > 0 else { return 0 }
        return (values[goal.id] ?? 0) / goal.target
    }
}

/// Ringe plus Legende und die uebrigen Ziele als Balken.
struct ActivityGoalSummary: View {
    let goals: [ActivityGoal]
    let values: [UUID: Double]
    let onEditGoals: () -> Void

    private var ringGoals: [ActivityGoal] {
        Array(goals.filter(\.showsAsRing).prefix(ActivityGoalStore.maximumRingCount))
    }

    private var listGoals: [ActivityGoal] {
        let ringIDs = Set(ringGoals.map(\.id))
        return goals.filter { !ringIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 16) {
            if ringGoals.isEmpty && listGoals.isEmpty {
                emptyState
            } else {
                if !ringGoals.isEmpty {
                    HStack(alignment: .center, spacing: 18) {
                        ActivityRingsView(goals: ringGoals, values: values)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(ringGoals) { goal in
                                legendRow(goal)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ForEach(listGoals) { goal in
                    GoalProgressRow(goal: goal, value: values[goal.id] ?? 0)
                }
            }

            Button(action: onEditGoals) {
                Label(L10n.string("Ziele verwalten"), systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .professionalCard(tint: .orange)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "target")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(L10n.string("Noch keine Ziele"))
                .font(.subheadline.weight(.semibold))
            Text(L10n.string("Lege fest, was du dir für Tag, Woche, Monat oder Jahr vornimmst."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func legendRow(_ goal: ActivityGoal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: goal.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(goal.tint)
                Text(goal.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(GoalFormatting.valueWithUnit(values[goal.id] ?? 0, goal: goal))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // Die Einheit steht schon am Wert – am Ziel waere sie nur
                // Wiederholung und triebe die Zeile in den Umbruch.
                Text("/ \(GoalFormatting.plainValue(goal.target, goal: goal))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Ein Ziel ohne Ring: Balken mit Zeitraum und Restwert.
struct GoalProgressRow: View {
    let goal: ActivityGoal
    let value: Double

    private var progress: Double {
        guard goal.target > 0 else { return 0 }
        return min(value / goal.target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: goal.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(goal.tint)
                Text(goal.title)
                    .font(.subheadline.weight(.semibold))
                Text(goal.period.shortTitle)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(goal.tint.opacity(0.14),
                                in: Capsule())
                Spacer(minLength: 4)
                Text("\(Int((progress * 100).rounded())) %")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(goal.tint.opacity(0.16))
                    Capsule()
                        .fill(goal.tint)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)

            Text("\(GoalFormatting.valueWithUnit(value, goal: goal)) / \(GoalFormatting.valueWithUnit(goal.target, goal: goal))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum GoalFormatting {
    static func valueWithUnit(_ value: Double, goal: ActivityGoal) -> String {
        guard let metric = goal.metric else { return String(Int(value.rounded())) }
        return metric.formattedValueWithUnit(value)
    }

    static func plainValue(_ value: Double, goal: ActivityGoal) -> String {
        guard let metric = goal.metric else { return String(Int(value.rounded())) }
        return metric.formattedValue(value)
    }
}
