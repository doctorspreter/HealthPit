//
//  FirstImportOverlay.swift
//  Healthpit
//
//  Der erste Start liest den gesamten Bestand aus Apple Health. Das dauert,
//  und ohne Anzeige sieht es aus, als haenge die App. Gezeigt wird, was
//  gerade gelesen wird – nicht bloss ein Kreisel.
//

import SwiftUI

struct FirstImportOverlay: View {
    let progress: IngestProgress

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)

                VStack(spacing: 6) {
                    Text(L10n.string("Daten werden übernommen"))
                        .font(.headline)
                    Text(progress.step)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                        // Feste Hoehe, sonst springt der Kasten bei jedem
                        // Schritt, und das liest sich unruhig.
                        .frame(height: 34, alignment: .top)
                }

                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .frame(width: 220)
                } else {
                    ProgressView()
                }

                Text(L10n.string("Das passiert nur beim ersten Mal."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
