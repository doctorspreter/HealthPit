//
//  ReleaseNotesView.swift
//  Healthpit
//
//  Erscheint einmal je Fassung beim Start. Der Warnhinweis steht oben und
//  bewusst nicht klein: ohne die neue Integration kommt in Home Assistant
//  nichts mehr an.
//

import SwiftUI

struct ReleaseNotesView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    warningCard
                    highlights
                }
                .padding()
            }
            .navigationTitle(L10n.format("Neu in %@", ReleaseNotes.version))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    onClose()
                } label: {
                    Text("Verstanden")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        // Der Hinweis soll bewusst bestätigt werden, nicht weggewischt.
        .interactiveDismissDisabled()
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(ReleaseNotes.warningTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(ReleaseNotes.warningParagraphs.enumerated()), id: \.offset) { _, paragraph in
                (Text(paragraph.bold).bold() + Text(" ") + Text(paragraph.rest))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(ReleaseNotes.warningSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(step)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.orange.opacity(0.45), lineWidth: 1)
        )
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Neu")
                .font(.headline)

            ForEach(ReleaseNotes.highlights) { item in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(HealthCategory.workouts.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
