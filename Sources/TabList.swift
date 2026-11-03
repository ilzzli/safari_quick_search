import SwiftUI

/// Displays supplied items and forwards selections without choosing their action.
struct TabList: View {
    let items: [TabItem]
    let isRefreshing: Bool
    let onSelect: (TabItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.value)
                }
            }
        }
        .opacity(isRefreshing ? 0.55 : 1)
        .disabled(isRefreshing)
        .scrollDisabled(isRefreshing)
    }
}
