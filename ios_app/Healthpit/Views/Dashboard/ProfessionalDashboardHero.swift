import HealthKit
import SwiftUI

/// Verdichtete Tageszusammenfassung: echte Cache-Werte statt einer weiteren
/// frei konfigurierbaren Kachel. Sie schafft eine klare Startseiten-Hierarchie.
struct ProfessionalDashboardHero: View {
    @State private var values: [String: DashboardMetricCacheEntry] = [:]
    /// Die drei Werte der Kachel — einstellbar unter Einstellungen ▸ Ziele.
    @State private var heroMetrics: [HealthMetric] = DashboardHeroSettings.metrics()

    private var stepsMetric: HealthMetric? { HealthMetric.metric(.stepCount) }

    private var steps: Double { value(for: stepsMetric) ?? 0 }

    /// Das eingestellte Schrittziel — nicht mehr die feste Zehntausend, sonst
    /// widerspraeche der Ring hier der Aktivitaetsseite.
    private var stepGoal: Double {
        ActivityGoalStore.goals()
            .first { $0.metricID == stepsMetric?.id && $0.period == .day }?
            .target ?? 10_000
    }

    private var progress: Double {
        guard stepGoal > 0 else { return 0 }
        return min(max(steps / stepGoal, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("Dein Tag auf einen Blick")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(insightText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.16), lineWidth: 9)
                    // Bewusst ein linearer Verlauf: der Winkelverlauf legte
                    // seine Farbkante quer ueber den Ring, sodass unter dem
                    // gelben Bogen ein zweiter, gruener zu liegen schien.
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(colors: [.orange, .yellow],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int((progress * 100).rounded())) %")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text("Ziel")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 82, height: 82)
                .accessibilityLabel("Schrittziel zu \(Int((progress * 100).rounded())) Prozent erreicht")
            }

            HStack(spacing: 8) {
                ForEach(heroMetrics) { metric in
                    heroMetric(metric: metric)
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.075, green: 0.07, blue: 0.15))
                .overlay {
                    LinearGradient(
                        colors: [.purple.opacity(0.55), .blue.opacity(0.25), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
        }
        .shadow(color: .indigo.opacity(0.24), radius: 20, y: 10)
        .task { await load() }
        // Die Einstellungen liegen als Blatt ueber der Startseite – ohne diesen
        // Anstoss zeigte die Kachel bis zum naechsten Start die alten Werte.
        .onReceive(NotificationCenter.default.publisher(for: DashboardHeroSettings.didChangeNotification)) { _ in
            Task { await load() }
        }
    }

    private func heroMetric(metric: HealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: metric.systemImage)
                .font(.caption.bold())
                .foregroundStyle(metric.category.tint)
            Text(formatted(metric) ?? "–")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(metric.title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func value(for metric: HealthMetric?) -> Double? {
        guard let metric else { return nil }
        return values[metric.id]?.value
    }

    private func formatted(_ metric: HealthMetric?) -> String? {
        guard let metric, let value = value(for: metric) else { return nil }
        return metric.formattedValueWithUnit(value)
    }

    private var insightText: String {
        if steps >= stepGoal { return "Stark: Dein Schrittziel ist für heute erreicht." }
        if steps > 0 { return "Noch \(max(0, Int(stepGoal.rounded()) - Int(steps.rounded())).formatted()) Schritte bis zu deinem Tagesziel." }
        return "Deine wichtigsten Werte erscheinen hier, sobald Apple Health aktualisiert wurde."
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Guten Morgen"
        case 12..<18: return "Guten Tag"
        default: return "Guten Abend"
        }
    }

    private func load() async {
        heroMetrics = DashboardHeroSettings.metrics()
        // Das Schrittziel im Ring braucht den Schrittwert, auch wenn Schritte
        // gar nicht mehr in der Kachel stehen.
        let ids = Set(heroMetrics.map(\.id) + [stepsMetric?.id].compactMap { $0 })
        values = await DashboardMetricCacheStore.shared.loadEntries(metricIDs: Array(ids))
    }
}
