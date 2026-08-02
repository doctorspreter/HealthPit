//
//  DashboardOrderSettingsSection.swift
//  Healthpit
//
//  Reihenfolge der Startseiten-Kacheln.
//

import SwiftUI

struct DashboardOrderSettingsSection: View {
    @Binding var orderRaw: String
    @Binding var sizesRaw: String

    private var items: [DashboardItem] {
        get { DashboardItem.ordered(from: orderRaw) }
        nonmutating set { orderRaw = DashboardItem.encode(newValue) }
    }

    private var sizes: [DashboardItem: DashboardWidgetSize] {
        get { DashboardItem.sizes(from: sizesRaw) }
        nonmutating set { sizesRaw = DashboardItem.encodeSizes(newValue) }
    }

    var body: some View {
        Section("Startseite") {
            ForEach(items) { item in
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
                        .disabled(items.first == item)

                        Button {
                            move(item, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(items.last == item)
                    }

                    Picker("Größe", selection: sizeBinding(for: item)) {
                        ForEach(DashboardWidgetSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Button("Standard wiederherstellen") {
                orderRaw = DashboardItem.encode(DashboardItem.defaultOrder)
                sizesRaw = ""
            }
        }
    }

    private func move(_ item: DashboardItem, offset: Int) {
        var values = items
        guard let index = values.firstIndex(of: item) else { return }
        let target = index + offset
        guard values.indices.contains(target) else { return }
        values.swapAt(index, target)
        items = values
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
