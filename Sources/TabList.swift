import SwiftUI

/// Displays supplied items and forwards selections without choosing their action.
struct TabList: View {
    let items: [TabItem]
    let isRefreshing: Bool
    let selectedID: TabItem.ID?
    let tabGroups: any TabGroupsInterface
    @Binding var hoveredTab: TabItem?
    let onSelect: (TabItem) -> Void

    @State private var hoveredID: TabItem.ID?
    @State private var unhoverTask: Task<Void, Never>?

    /// Hovered row always has priority over keyboard-selected row.
    private var activePopupID: TabItem.ID? {
        hoveredID ?? selectedID
    }

    private var activeOpenedItem: TabItem? {
        guard !isRefreshing, let id = activePopupID,
              let item = items.first(where: { $0.id == id }),
              item.type == .OPENED_TAB else { return nil }
        return item
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(items) { item in
                    TabRow(
                        item: item,
                        isSelected: selectedID == item.id,
                        isPopupExpanded: activePopupID == item.id
                    ) {
                        onSelect(item)
                    }
                    .onHover { inside in
                        handleRowHover(item: item, inside: inside)
                    }
                    .onDisappear {
                        if hoveredID == item.id {
                            unhoverTask?.cancel()
                            hoveredID = nil
                        }
                    }
                }
            }
            .padding(10)
        }
        .overlayPreferenceValue(OpenTabIconAnchorKey.self) { anchors in
            GeometryReader { geometry in
                OpenTabProfilesPopupOverlay(
                    items: items,
                    activeItem: activeOpenedItem,
                    anchors: anchors,
                    proxy: geometry
                )
            }
        }
        .onChange(of: selectedID) { _, id in
            if let id { proxy.scrollTo(id) }
        }
        .onChange(of: activePopupID, initial: true) { _, id in
            guard !isRefreshing else { return }
            hoveredTab = id.flatMap { targetID in items.first { $0.id == targetID } }
        }
        .onChange(of: items) { _, updatedItems in
            if let hoveredID, !updatedItems.contains(where: { $0.id == hoveredID }) {
                self.hoveredID = nil
            }
            hoveredTab = activePopupID.flatMap { targetID in updatedItems.first { $0.id == targetID } }
        }
        }
        .opacity(isRefreshing ? 0.55 : 1)
        .disabled(isRefreshing)
        .scrollDisabled(isRefreshing)
    }

    private func handleRowHover(item: TabItem, inside: Bool) {
        guard !isRefreshing else { return }
        if inside {
            unhoverTask?.cancel()
            unhoverTask = nil
            hoveredID = item.id
        } else if hoveredID == item.id {
            unhoverTask?.cancel()
            let leavingID = item.id
            unhoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(45))
                guard !Task.isCancelled, hoveredID == leavingID else { return }
                hoveredID = nil
            }
        }
    }
}

private struct TabRow: View {
    let item: TabItem
    let isSelected: Bool
    let isPopupExpanded: Bool
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
                if item.type == .OPENED_TAB {
                    OpenTabProfilesControl(itemID: item.id, isExpanded: isPopupExpanded)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity((isHovered || isSelected) ? (contrast == .increased ? 0.18 : 0.06) : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onDisappear { isHovered = false }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(item.title + ", " + item.subtitle)
    }
}

