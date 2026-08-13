//
//  OnboardingView.swift
//  Healthpit
//
//  Screen 0 – Verbindung mit Apple Health herstellen. Ruft die Autorisierung
//  an und meldet per Closure zurück, sobald der Dialog beantwortet wurde.
//

import SwiftUI

struct OnboardingView: View {
    /// Wird aufgerufen, sobald die Autorisierung angefragt wurde.
    var onConnected: () -> Void

    private let health = HealthKitManager.shared
    @State private var isRequesting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.2), .blue.opacity(0.08), Color(.systemBackground)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                ZStack {
                    Circle().fill(.pink.opacity(0.12)).frame(width: 142, height: 142)
                    Circle().stroke(.pink.opacity(0.2), lineWidth: 1).frame(width: 116, height: 116)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 62))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .pink)
                }

                VStack(spacing: 10) {
                    Text("HealthPit")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))

                    Text("Deine Gesundheit. Deine Daten.")
                        .font(.title3.weight(.semibold))

                    Text("HealthPit liest deine Werte aus Apple Health und synchronisiert sie direkt mit deinem Home Assistant — ohne Umweg über fremde Server.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                HStack(spacing: 18) {
                    onboardingFeature("chart.xyaxis.line", "Trends", .orange)
                    onboardingFeature("lock.shield.fill", "Privat", .green)
                    onboardingFeature("bolt.heart.fill", "Aktuell", .pink)
                }

                Spacer()

            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if isRequesting { ProgressView().tint(.white) }
                    Text("Mit Apple Health verbinden")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.pink, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .font(.headline)
            }
            .disabled(isRequesting)
            .padding(.horizontal, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            }
            .padding(20)
        }
    }

    private func onboardingFeature(_ icon: String, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(title).font(.caption.bold())
        }
        .frame(maxWidth: .infinity)
    }

    private func connect() async {
        isRequesting = true
        errorMessage = nil
        defer { isRequesting = false }
        do {
            try await health.requestAuthorization()
            onConnected()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
