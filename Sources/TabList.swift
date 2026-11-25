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
    private enum StickyEdge: Equatable {
        case top
        case bottom
    }

    private struct StickyRowState: Equatable {
        let item: TabItem
        let edge: StickyEdge
        let width: CGFloat
        let height: CGFloat
    }

    private static let horizontalPadding: CGFloat = 10
    private static let topPinPadding: CGFloat = 4
    private static let bottomPinPadding: CGFloat = 10

    let items: [TabItem]
    let isRefreshing: Bool
    let selectedID: TabItem.ID?
    let allProfiles: [SafariProfileGroups]
    let showAllWindowsInPopup: Bool
    @Binding var hoveredTab: TabItem?
    let onSelect: (TabItem) -> Void

    @State private var hoveredID: TabItem.ID?
    @State private var pinnedRowID: TabItem.ID?
    @State private var unhoverTask: Task<Void, Never>?
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
                            isHovered: hoveredID == item.id,
                            isPinned: false
                        ) {
                            onSelect(item)
                        }
                        .opacity(pinnedRowID == item.id ? 0 : 1)
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
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, Self.topPinPadding)
                .padding(.bottom, Self.bottomPinPadding)
            }
            .onScrollPhaseChange { _, newPhase in
                isScrolling = newPhase != .idle
            }
            .overlayPreferenceValue(RowBoundsPreferenceKey.self) { rowAnchors in
                GeometryReader { geometry in
                    let stickyRow = resolveStickyRow(rowAnchors: rowAnchors, proxy: geometry)
                    let resolvedHoverID = resolveHoveredID(
                        rowAnchors: rowAnchors,
                        stickyRow: stickyRow,
                        proxy: geometry
                    )

                    ZStack(alignment: stickyRow?.edge == .bottom ? .bottom : .top) {
                        Color.clear
                            .allowsHitTesting(false)
                            .onChange(of: resolvedHoverID) { _, newHoverID in
                                if let newHoverID, hoveredID != newHoverID {
                                    unhoverTask?.cancel()
                                    unhoverTask = nil
                                    hoveredID = newHoverID
                                }
                            }
                            .onChange(of: stickyRow?.item.id, initial: true) { _, newPinnedID in
                                pinnedRowID = newPinnedID
                            }

                        if let stickyRow {
                            TabRow(
                                item: stickyRow.item,
                                isSelected: true,
                                isHovered: hoveredID == stickyRow.item.id,
                                isPinned: true
                            ) {
                                onSelect(stickyRow.item)
                            }
                            .frame(width: stickyRow.width)
                            .padding(.top, stickyRow.edge == .top ? Self.topPinPadding : 0)
                            .padding(.bottom, stickyRow.edge == .bottom ? Self.bottomPinPadding : 0)
                            .onHover { inside in
                                handleRowHover(item: stickyRow.item, inside: inside)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
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
            .overlayPreferenceValue(OpenTabIconAnchorKey.self) { anchors in
                GeometryReader { geometry in
                    OpenTabProfilesPopupOverlay(
                        items: items,
                        activeItem: activeOpenedItem,
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
        .opacity(isRefreshing ? 0.55 : 1)
        .disabled(isRefreshing)
        .scrollDisabled(isRefreshing)
    }

    private func resolveStickyRow(
        rowAnchors: [TabItem.ID: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> StickyRowState? {
        guard !isRefreshing,
              let selectedID,
              let item = items.first(where: { $0.id == selectedID }),
              let anchor = rowAnchors[selectedID] else {
            return nil
        }
        let rect = proxy[anchor]
        if rect.minY < Self.topPinPadding - 0.5 {
            return StickyRowState(item: item, edge: .top, width: rect.width, height: rect.height)
        }
        if rect.maxY > proxy.size.height - Self.bottomPinPadding + 0.5 {
            return StickyRowState(item: item, edge: .bottom, width: rect.width, height: rect.height)
        }
        return nil
    }

    private func resolveHoveredID(
        rowAnchors: [TabItem.ID: Anchor<CGRect>],
        stickyRow: StickyRowState?,
        proxy: GeometryProxy
    ) -> TabItem.ID? {
        guard !isRefreshing else { return nil }
        if hoveredID != nil, let point = pointerLocation {
            if let stickyRow {
                let pinnedY = stickyRow.edge == .top
                    ? Self.topPinPadding
                    : proxy.size.height - Self.bottomPinPadding - stickyRow.height
                let pinnedRect = CGRect(
                    x: Self.horizontalPadding,
                    y: pinnedY,
                    width: stickyRow.width,
                    height: stickyRow.height
                )
                if pinnedRect.contains(point) {
                    return stickyRow.item.id
                }
            }
            for item in items {
                guard let anchor = rowAnchors[item.id] else { continue }
                let rect = proxy[anchor].insetBy(dx: 0, dy: -3)
                guard rect.maxY > 0 else { continue }
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
    let isPinned: Bool
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
                if isPinned {
                    StickyRowGlassSurface(contrast: contrast)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity((isHovered || isSelected) ? (contrast == .increased ? 0.18 : 0.06) : 0))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(item.title + ", " + item.subtitle)
    }
}

private struct StickyRowGlassSurface: View {
    let contrast: ColorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        if reduceTransparency {
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.22), lineWidth: 1)
                }
        } else {
            Color.clear
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(contrast == .increased ? 0.35 : 0.20), lineWidth: 0.75)
                }
        }
    }
}
