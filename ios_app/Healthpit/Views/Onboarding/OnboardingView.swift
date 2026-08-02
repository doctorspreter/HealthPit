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
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 72))
                .foregroundStyle(.pink)

            Text("Healthpit")
                .font(.largeTitle.bold())

            Text("Verbinde dich mit Apple Health, um deine Gesundheitsdaten übersichtlich darzustellen. Die Daten verlassen dein Gerät nicht.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
            .padding(.horizontal)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
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
