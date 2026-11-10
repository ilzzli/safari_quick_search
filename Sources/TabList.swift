import AppKit
import SwiftUI

struct RowBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: [TabItem.ID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TabItem.ID: Anchor<CGRect>],
        nextValue: () -> [TabItem.ID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Displays supplied items and forwards selections without choosing their action.
struct TabList: View {
    let items: [TabItem]
    let isRefreshing: Bool
    let selectedID: TabItem.ID?
    let tabGroups: any TabGroupsInterface
    let showAllWindowsInPopup: Bool
    let refreshID: UUID
    @Binding var hoveredTab: TabItem?
    let onSelect: (TabItem) -> Void

    @State private var hoveredID: TabItem.ID?
    @State private var unhoverTask: Task<Void, Never>?
    @State private var allProfiles: [SafariProfileGroups] = []
    @State private var isScrolling = false
    @State private var pointerLocation: CGPoint?

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
                VStack(spacing: 5) {
                    ForEach(items) { item in
                        TabRow(
                            item: item,
                            isSelected: selectedID == item.id,
                            isHovered: hoveredID == item.id
                        ) {
                            onSelect(item)
                        }
                        .anchorPreference(key: RowBoundsPreferenceKey.self, value: .bounds) {
                            [item.id: $0]
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
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    pointerLocation = location
                case .ended:
                    pointerLocation = nil
                    unhoverTask?.cancel()
                    hoveredID = nil
                }
            }
            .onScrollPhaseChange { _, newPhase in
                isScrolling = newPhase != .idle
            }
            .overlayPreferenceValue(RowBoundsPreferenceKey.self) { rowAnchors in
                GeometryReader { geometry in
                    let resolvedHoverID = resolveHoveredID(rowAnchors: rowAnchors, proxy: geometry)
                    Color.clear
                        .onChange(of: resolvedHoverID) { _, newHoverID in
                            if let newHoverID, hoveredID != newHoverID {
                                unhoverTask?.cancel()
                                unhoverTask = nil
                                hoveredID = newHoverID
                            }
                        }
                }
                .allowsHitTesting(false)
            }
            .overlayPreferenceValue(OpenTabIconAnchorKey.self) { anchors in
                GeometryReader { geometry in
                    OpenTabProfilesPopupOverlay(
                        items: items,
                        activeItem: activeOpenedItem,
                        selectedItemID: selectedID,
                        hoveredItemID: hoveredID,
                        pointerLocation: pointerLocation,
                        allProfiles: allProfiles,
                        showAllWindows: showAllWindowsInPopup,
                        isPointerHovered: hoveredID != nil,
                        isScrolling: isScrolling,
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
        .task(id: refreshID) {
            if let loaded = try? await tabGroups.profiles(), !Task.isCancelled {
                allProfiles = loaded
            }
        }
        .opacity(isRefreshing ? 0.55 : 1)
        .disabled(isRefreshing)
        .scrollDisabled(isRefreshing)
    }

    private func resolveHoveredID(
        rowAnchors: [TabItem.ID: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> TabItem.ID? {
        guard !isRefreshing else { return nil }
        if hoveredID != nil, let point = pointerLocation {
            for item in items {
                guard let anchor = rowAnchors[item.id] else { continue }
                let rect = proxy[anchor].insetBy(dx: 0, dy: -3)
                if rect.contains(point) {
                    return item.id
                }
            }
        }
        return hoveredID
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
            let delayMs = isScrolling ? 200 : 45
            unhoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled, hoveredID == leavingID else { return }
                hoveredID = nil
            }
        }
    }
}

private struct TabRow: View {
    let item: TabItem
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
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
                    OpenTabProfilesControl(itemID: item.id)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(item.title + ", " + item.subtitle)
    }
}

