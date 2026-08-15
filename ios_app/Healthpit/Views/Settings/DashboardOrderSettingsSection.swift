//
//  DashboardOrderSettingsSection.swift
//  Healthpit
//
//  Reihenfolge, Groesse und Sichtbarkeit der Startseiten-Kacheln.
//

import SwiftUI

struct DashboardOrderSettingsSection: View {
    @Binding var orderRaw: String
    @Binding var sizesRaw: String
    @Binding var hiddenRaw: String

    private var items: [DashboardItem] {
        get { DashboardItem.ordered(from: orderRaw) }
        nonmutating set { orderRaw = DashboardItem.encode(newValue) }
    }

    private var sizes: [DashboardItem: DashboardWidgetSize] {
        get { DashboardItem.sizes(from: sizesRaw) }
        nonmutating set { sizesRaw = DashboardItem.encodeSizes(newValue) }
    }

    private var hiddenItems: Set<DashboardItem> {
        DashboardItem.hidden(from: hiddenRaw)
    }

    private var visibleItems: [DashboardItem] {
        items.filter { !hiddenItems.contains($0) }
    }

    var body: some View {
        Section(L10n.string("Startseite")) {
            ForEach(visibleItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(item.title, systemImage: item.systemImage)
                        Spacer()
                        Button {
                            move(item, offset: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(visibleItems.first == item)

                        Button {
                            move(item, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(visibleItems.last == item)

                        // Bewusst ein Knopf und keine Wischgeste: Wischen gibt es
                        // auf dem Mac nicht, dort waere die Kachel sonst nicht zu
                        // entfernen.
                        Button {
                            setHidden(item, true)
                        } label: {
                            Image(systemName: "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.string("Kachel ausblenden"))
                    }

                    Picker(L10n.string("Größe"), selection: sizeBinding(for: item)) {
                        ForEach(DashboardWidgetSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Button(L10n.string("Standard wiederherstellen")) {
                orderRaw = DashboardItem.encode(DashboardItem.defaultOrder)
                sizesRaw = ""
                hiddenRaw = ""
            }
        }

        if !hiddenItems.isEmpty {
            Section(L10n.string("Ausgeblendete Kacheln")) {
                ForEach(items.filter(hiddenItems.contains)) { item in
                    HStack {
                        Label(item.title, systemImage: item.systemImage)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            setHidden(item, false)
                        } label: {
                            Image(systemName: "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.string("Kachel einblenden"))
                    }
                }
            }
        }
    }

    /// Verschiebt innerhalb der sichtbaren Kacheln, damit ein Klick eine
    /// sichtbare Bewegung ergibt und nicht an einer ausgeblendeten haengen bleibt.
    private func move(_ item: DashboardItem, offset: Int) {
        let visible = visibleItems
        guard let position = visible.firstIndex(of: item) else { return }
        let targetPosition = position + offset
        guard visible.indices.contains(targetPosition) else { return }

        var values = items
        guard let index = values.firstIndex(of: item),
              let target = values.firstIndex(of: visible[targetPosition]) else { return }
        values.swapAt(index, target)
        items = values
    }

    private func setHidden(_ item: DashboardItem, _ isHidden: Bool) {
        var updated = hiddenItems
        if isHidden {
            updated.insert(item)
        } else {
            updated.remove(item)
        }
        hiddenRaw = DashboardItem.encodeHidden(updated)
    }

    private func sizeBinding(for item: DashboardItem) -> Binding<DashboardWidgetSize> {
        Binding {
            DashboardItem.size(for: item, rawValue: sizesRaw)
        } set: { newValue in
            var updated = sizes
            updated[item] = newValue
            sizes = updated
        }
    }
}
