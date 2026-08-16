//
//  InteractiveChartControls.swift
//  Healthpit
//
//  Kleine, wiederverwendbare Bedienelemente fuer interaktive Swift-Charts.
//

import SwiftUI
import Charts

struct ChartGestureHint: View {
    var body: some View {
        Label(L10n.string("Mit zwei Fingern zoomen · Wischen zum Verschieben · Tippen für Wert"),
              systemImage: "hand.draw")
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

extension View {
    /// Gemeinsame visuelle Buehne fuer alle Diagramme der Preview-App.
    func modernChartSurface(tint: Color) -> some View {
        padding(14)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.13),
                                Color(.secondarySystemBackground).opacity(0.96),
                                Color(.systemBackground),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.10), radius: 14, y: 7)
    }

    func chartPinchZoom(_ zoomLevel: Binding<Double>, maximumZoom: Double = 6) -> some View {
        modifier(ChartPinchZoomModifier(zoomLevel: zoomLevel, maximumZoom: maximumZoom))
    }

    func chartTapSelection<Value: Plottable>(value: Binding<Value?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { gesture in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                guard frame.contains(gesture.location) else { return }
                                value.wrappedValue = proxy.value(atX: gesture.location.x - frame.minX)
                            }
                    )
            }
        }
    }
}

private struct ChartPinchZoomModifier: ViewModifier {
    @Binding var zoomLevel: Double
    let maximumZoom: Double
    @State private var zoomAtGestureStart: Double?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            MagnifyGesture()
                .onChanged { gesture in
                    let start = zoomAtGestureStart ?? zoomLevel
                    if zoomAtGestureStart == nil {
                        zoomAtGestureStart = start
                    }
                    zoomLevel = min(maximumZoom,
                                    max(1, start * Double(gesture.magnification)))
                }
                .onEnded { _ in
                    zoomAtGestureStart = nil
                }
        )
    }
}

struct ChartSelectedValue: View {
    let title: String
    let values: [(color: Color, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.string(title))
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)],
                      alignment: .leading,
                      spacing: 5) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(value.color)
                            .frame(width: 7, height: 7)
                        Text(value.text)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

func compactChartAxisNumber(_ value: Double, maximumFractionDigits: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)))
}

func chartSampledValues<Element>(_ values: [Element], maximumCount: Int = 240) -> [Element] {
    guard maximumCount > 1, values.count > maximumCount else { return values }
    let lastIndex = values.count - 1
    let step = Double(lastIndex) / Double(maximumCount - 1)
    return (0..<maximumCount).map { index in
        values[Int((Double(index) * step).rounded())]
    }
}

// MARK: - Professionelles Seitensystem

struct ProfessionalPageHero: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var value: String? = nil
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string(eyebrow).uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.15)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(L10n.string(title))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(value)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    if let detail {
                        // Auch hier durch die Uebersetzung: „Messwerte" stand
                        // sonst deutsch in einer englischen App.
                        Text(L10n.string(detail))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
            }

            Text(L10n.string(subtitle))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [tint, tint.opacity(0.78), Color.indigo.opacity(0.88)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.09))
                .frame(width: 150, height: 150)
                .offset(x: 46, y: -72)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: tint.opacity(0.22), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
    }
}

struct ProfessionalSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(title))
                    .font(.title3.bold())
                if let subtitle {
                    Text(L10n.string(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle {
                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProfessionalMetricTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                if let detail {
                    Text(L10n.string(detail))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.10), in: Capsule())
                }
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(L10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(14)
        .professionalCard(tint: tint)
        .accessibilityElement(children: .combine)
    }
}

struct ProfessionalEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 62, height: 62)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(L10n.string(title))
                .font(.headline)
            Text(L10n.string(message))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .professionalCard(tint: tint)
    }
}

struct ProfessionalSettingsLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                // Beides übersetzen: Der Titel lief früher ungefiltert
                // durch, sodass die Kacheln im Menü deutsch blieben.
                Text(L10n.string(title)).font(.subheadline.weight(.semibold))
                Text(L10n.string(subtitle)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

extension View {
    func professionalCard(tint: Color = .accentColor,
                          cornerRadius: CGFloat = 20) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(colors: [tint.opacity(0.075), Color(.secondarySystemBackground), Color(.systemBackground)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.075), radius: 12, y: 6)
    }

    func professionalPageBackground(tint: Color) -> some View {
        background {
            LinearGradient(colors: [tint.opacity(0.08), Color(.systemBackground), tint.opacity(0.025)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }
}
