import SwiftUI

/// Displays supplied items and forwards selections without choosing their action.
struct TabList: View {
    let items: [TabItem]
    let isRefreshing: Bool
    @Binding var hoveredTab: TabItem?
    let onSelect: (TabItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(items) { item in
                    TabRow(item: item) { onSelect(item) }
                        .onHover { inside in
                            if inside && !isRefreshing {
                                hoveredTab = item
                            } else if hoveredTab?.id == item.id {
                                hoveredTab = nil
                            }
                        }
                        .onDisappear {
                            if hoveredTab?.id == item.id { hoveredTab = nil }
                        }
                }
            }
            .padding(10)
        }
        .opacity(isRefreshing ? 0.55 : 1)
        .disabled(isRefreshing)
        .scrollDisabled(isRefreshing)
    }
}

private struct TabRow: View {
    let item: TabItem
    let onSelect: () -> Void
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var icon: String {
        switch item.type {
        case .HISTORY: "clock"
        case .OPENED_TAB: "macwindow"
        case .SEARCH: "magnifyingglass"
        case .URL: "globe"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if let location = item.locationLabel {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? (contrast == .increased ? 0.18 : 0.06) : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onDisappear { isHovered = false }
        .help(item.value)
        .accessibilityLabel(item.title + ", " + item.subtitle)
    }
}
