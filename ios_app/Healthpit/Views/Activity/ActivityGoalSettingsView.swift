//
//  ActivityGoalSettingsView.swift
//  Healthpit
//
//  Ziele verwalten: anlegen, aendern, loeschen. Erreichbar aus den
//  Einstellungen und direkt von der Aktivitaetsseite.
//

import SwiftUI

struct ActivityGoalSettingsView: View {
    @State private var goals: [ActivityGoal] = ActivityGoalStore.goals()
    @State private var editedGoal: ActivityGoal?
    @State private var isAddingGoal = false
    @State private var heroMetricIDs: [String] = DashboardHeroSettings.metricIDs()

    var body: some View {
        List {
            Section {
                if goals.isEmpty {
                    Text("Noch keine Ziele. Lege eines an – zum Beispiel gelaufene Kilometer im Monat.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(goals) { goal in
                        Button {
                            editedGoal = goal
                        } label: {
                            goalRow(goal)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                Text("Deine Ziele")
            } footer: {
                Text("Bis zu \(ActivityGoalStore.maximumRingCount) Ziele erscheinen als Ring auf der Aktivitätsseite, alle weiteren als Balken. Jedes Ziel geht als Zielwert und als Erfüllungsgrad in Prozent an Home Assistant.")
            }

            Section {
                ForEach(Array(heroMetricIDs.enumerated()), id: \.offset) { index, id in
                    Picker(L10n.format("Zeile %lld", Int64(index + 1)),
                           selection: heroBinding(at: index)) {
                        ForEach(HealthMetric.all) { candidate in
                            Text(candidate.title).tag(candidate.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            } header: {
                Text("Startkachel")
            } footer: {
                Text("Diese drei Werte stehen in der Kachel „Dein Tag auf einen Blick“ auf der Startseite.")
            }

            Section {
                Button {
                    isAddingGoal = true
                } label: {
                    Label("Ziel hinzufügen", systemImage: "plus.circle.fill")
                }
                Button(role: .destructive) {
                    ActivityGoalStore.resetToDefaults()
                    reload()
                } label: {
                    Label("Auf Standardziele zurücksetzen", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Ziele")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editedGoal) { goal in
            ActivityGoalEditor(goal: goal) { reload() }
        }
        .sheet(isPresented: $isAddingGoal) {
            ActivityGoalEditor(goal: nil) { reload() }
        }
        .onAppear { reload() }
    }

    private func goalRow(_ goal: ActivityGoal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: goal.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(goal.tint)
                .frame(width: 34, height: 34)
                .background(goal.tint.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(GoalFormatting.valueWithUnit(goal.target, goal: goal)) · \(goal.period.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if goal.showsAsRing {
                Image(systemName: "circle.circle.fill")
                    .foregroundStyle(goal.tint)
                    .accessibilityLabel("Als Ring")
            }
        }
        .contentShape(Rectangle())
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            ActivityGoalStore.delete(goals[index])
        }
        reload()
    }

    private func heroBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { heroMetricIDs.indices.contains(index) ? heroMetricIDs[index] : "" },
            set: { newValue in
                DashboardHeroSettings.setMetricID(newValue, at: index)
                heroMetricIDs = DashboardHeroSettings.metricIDs()
            }
        )
    }

    private func reload() {
        goals = ActivityGoalStore.goals()
        heroMetricIDs = DashboardHeroSettings.metricIDs()
    }
}

/// Blatt zum Anlegen und Aendern eines Ziels.
struct ActivityGoalEditor: View {
    @Environment(\.dismiss) private var dismiss

    /// nil = neues Ziel.
    let goal: ActivityGoal?
    let onSaved: () -> Void

    @State private var metricID: String = ""
    @State private var period: GoalPeriod = .day
    /// Zielwert in Anzeigeeinheit – so, wie der Regler ihn zeigt.
    @State private var displayTarget: Double = 0
    @State private var showsAsRing = false
    /// Die Messwertauswahl wird aufgeschoben und kehrt zurueck — ohne diese
    /// Sperre setzte das erneute Erscheinen das halb ausgefuellte Blatt zurueck.
    @State private var didPrepare = false

    private var metric: HealthMetric? { HealthMetric.metric(id: metricID) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Messwert") {
                    Picker("Messwert", selection: $metricID) {
                        ForEach(ActivityGoalStore.selectableMetrics) { candidate in
                            Text(candidate.title).tag(candidate.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Zeitraum") {
                    Picker("Zeitraum", selection: $period) {
                        ForEach(GoalPeriod.allCases) { candidate in
                            Text(candidate.title).tag(candidate)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Zielwert") {
                    targetEditor
                }

                Section {
                    Toggle("Als Ring anzeigen", isOn: $showsAsRing)
                } footer: {
                    Text("Höchstens \(ActivityGoalStore.maximumRingCount) Ziele werden als Ring gezeigt. Kommt eines dazu, weicht das älteste in die Balkenliste.")
                }
            }
            .navigationTitle(goal == nil ? "Neues Ziel" : "Ziel ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(metric == nil || displayTarget <= 0)
                }
            }
            .onAppear(perform: prepare)
            .onChange(of: metricID) { _, _ in suggestTarget() }
            .onChange(of: period) { _, _ in suggestTarget() }
        }
    }

    @ViewBuilder
    private var targetEditor: some View {
        if let metric {
            let bounds = ActivityGoalStore.editorRange(for: metric, period: period)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(metric.formattedDisplayValueWithUnit(displayTarget))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer()
                    Stepper("", value: $displayTarget, in: bounds.range, step: bounds.step)
                        .labelsHidden()
                }
                Slider(value: $displayTarget, in: bounds.range, step: bounds.step)
                    .tint(previewGoal.tint)
                Text("Zeitraum: \(period.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else {
            Text("Bitte zuerst einen Messwert wählen.")
                .foregroundStyle(.secondary)
        }
    }

    /// Nur fuer die Faerbung waehrend des Bearbeitens.
    private var previewGoal: ActivityGoal {
        ActivityGoal(metricID: metricID, period: period, target: 1)
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        if let goal {
            metricID = goal.metricID
            period = goal.period
            showsAsRing = goal.showsAsRing
            displayTarget = goal.metric?.displayValue(goal.target) ?? goal.target
        } else {
            metricID = ActivityGoalStore.selectableMetrics.first?.id ?? ""
            period = .day
            showsAsRing = false
            suggestTarget()
        }
    }

    private func suggestTarget() {
        guard let metric else { return }
        // Beim Wechsel von Messwert oder Zeitraum passt der alte Wert nicht
        // mehr — er laege ausserhalb des Reglers und liesse sich nicht fassen.
        displayTarget = metric.displayValue(ActivityGoalStore.suggestedTarget(for: metric, period: period))
    }

    private func save() {
        guard let metric else { return }
        var updated = goal ?? ActivityGoal(metricID: metricID, period: period, target: 0)
        updated.metricID = metricID
        updated.period = period
        updated.target = metric.rawValue(fromDisplay: displayTarget)
        updated.showsAsRing = showsAsRing
        ActivityGoalStore.upsert(updated)
        onSaved()
        dismiss()
    }
}
