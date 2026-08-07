//
//  HealthAccessCard.swift
//  Healthpit
//
//  Kachel, die erscheint, solange die Apple-Health-Freigabe aussteht.
//  Ohne sie bleibt die Startseite nach einem abgelehnten Onboarding leer,
//  ohne zu sagen warum.
//

import SwiftUI

struct HealthAccessCard: View {
    let size: DashboardWidgetSize
    /// Wird nach einer beantworteten Anfrage aufgerufen, damit die Startseite
    /// die Kacheln neu laedt und diese hier wieder verschwinden kann.
    let onGranted: () -> Void

    private let health = HealthKitManager.shared

    @State private var isRequesting = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await request() }
        } label: {
            content
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.red)
                if size != .small {
                    Text("Apple Health")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isRequesting {
                    ProgressView().controlSize(.mini)
                }
            }

            Text("Zugriff erlauben")
                .font(size == .small ? .caption.weight(.semibold) : .headline)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if size != .small {
                Text(errorMessage ?? L10n.string("HealthPit braucht die Freigabe, um deine Werte zu lesen."))
                    .font(.caption2)
                    .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.red.opacity(0.35), lineWidth: 1)
        )
    }

    private func request() async {
        isRequesting = true
        errorMessage = nil
        defer { isRequesting = false }
        do {
            try await health.requestAuthorization()
            onGranted()
        } catch {
            // iOS zeigt den Dialog nur einmal. Wurde er abgelehnt, hilft nur
            // noch die Health-App, deshalb steht das hier statt eines
            // technischen Fehlertexts.
            errorMessage = L10n.string("Freigabe in der Health-App unter „Datenzugriff und Geräte“ erteilen.")
        }
    }
}
