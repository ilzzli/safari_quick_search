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

private struct StickyRowBoundsPreferenceKey: PreferenceKey {
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

    private static let horizontalPadding: CGFloat = 12
    private static let topPinPadding: CGFloat = 4
    private static let bottomPinPadding: CGFloat = 12

    let items: [TabItem]
    let isRefreshing: Bool
    let selectedID: TabItem.ID?
    let allProfiles: [SafariProfileGroups]
    let showAllWindowsInPopup: Bool
    @Binding var hoveredTab: TabItem?
    let onSelect: (TabItem) -> Void

    @State private var hoveredID: TabItem.ID?
    @State private var pinnedRowID: TabItem.ID?
    @State private var pinnedRowFrame: CGRect?
    @State private var unhoverTask: Task<Void, Never>?
    @State private var isScrolling = false
    @State private var pointerLocation: CGPoint?

    private var isPointerInsidePinnedRow: Bool {
        guard let point = pointerLocation, let frame = pinnedRowFrame else { return false }
        return frame.insetBy(dx: 0, dy: -2).contains(point)
    }

    /// Hovered row always has priority over keyboard-selected row.
    private var activePopupID: TabItem.ID? {
        if isPointerInsidePinnedRow, let pinnedRowID {
            return pinnedRowID
        }
        return hoveredID ?? selectedID
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
                VStack(spacing: 3) {
                    ForEach(items) { item in
                        TabRow(
                            item: item,
                            isSelected: selectedID == item.id,
                            isHovered: !isPointerInsidePinnedRow && hoveredID == item.id,
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
                    let stickyRect = stickyRow.map { row in
                        let pinnedY = row.edge == .top
                            ? Self.topPinPadding
                            : geometry.size.height - Self.bottomPinPadding - row.height
                        return CGRect(
                            x: Self.horizontalPadding,
                            y: pinnedY,
                            width: row.width,
                            height: row.height
                        )
                    }
                    let resolvedHoverID = resolveHoveredID(
                        rowAnchors: rowAnchors,
                        stickyRow: stickyRow,
                        stickyRect: stickyRect,
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
                            .onChange(of: stickyRect, initial: true) { _, newStickyRect in
                                pinnedRowFrame = newStickyRect
                            }

                        if let stickyRow {
                            TabRow(
                                item: stickyRow.item,
                                isSelected: true,
                                isHovered: isPointerInsidePinnedRow || hoveredID == stickyRow.item.id,
                                isPinned: true,
                                onSelect: nil
                            )
                            .frame(width: stickyRow.width)
                            .anchorPreference(key: StickyRowBoundsPreferenceKey.self, value: .bounds) {
                                [stickyRow.item.id: $0]
                            }
                            .padding(.top, stickyRow.edge == .top ? Self.topPinPadding : 0)
                            .padding(.bottom, stickyRow.edge == .bottom ? Self.bottomPinPadding : 0)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let frame = pinnedRowFrame,
                              frame.contains(value.location),
                              let pinnedRowID,
                              let item = items.first(where: { $0.id == pinnedRowID }) else {
                            return
                        }
                        onSelect(item)
                    }
            )
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
                Color.clear
                    .overlayPreferenceValue(RowBoundsPreferenceKey.self) { rowAnchors in
                        Color.clear
                            .overlayPreferenceValue(StickyRowBoundsPreferenceKey.self) { stickyRowAnchors in
                                GeometryReader { geometry in
                                    OpenTabProfilesPopupOverlay(
                                        items: items,
                                        activeItem: activeOpenedItem,
                                        pointerLocation: pointerLocation,
                                        allProfiles: allProfiles,
                                        showAllWindows: showAllWindowsInPopup,
                                        isPointerHovered: hoveredID != nil || isPointerInsidePinnedRow,
                                        isPointerInsidePinnedRow: isPointerInsidePinnedRow,
                                        isScrolling: isScrolling,
                                        anchors: anchors,
                                        rowAnchors: rowAnchors.merging(
                                            stickyRowAnchors,
                                            uniquingKeysWith: { _, sticky in sticky }
                                        ),
                                        pinnedRowID: pinnedRowID,
                                        proxy: geometry
                                    )
                                }
                            }
                    }
            }
            .onChange(of: selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .onChange(of: activePopupID, initial: true) { _, id in
                guard !isRefreshing else { return }
                hoveredTab = id.flatMap { targetID in items.first { $0.id == targetID } }
            }
            .onChange(of: isRefreshing) { _, refreshing in
                guard !refreshing else { return }
                hoveredTab = activePopupID.flatMap { targetID in items.first { $0.id == targetID } }
            }
            .onChange(of: items) { _, updatedItems in
                if let hoveredID, !updatedItems.contains(where: { $0.id == hoveredID }) {
                    self.hoveredID = nil
                }
                guard !isRefreshing else { return }
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
        stickyRect: CGRect?,
        proxy: GeometryProxy
    ) -> TabItem.ID? {
        guard !isRefreshing else { return nil }
        if let point = pointerLocation {
            if let stickyRow, let stickyRect, stickyRect.insetBy(dx: 0, dy: -2).contains(point) {
                return stickyRow.item.id
            }
            if hoveredID != nil {
                for item in items {
                    guard item.id != stickyRow?.item.id else { continue }
                    guard let anchor = rowAnchors[item.id] else { continue }
                    let rect = proxy[anchor].insetBy(dx: 0, dy: -3)
                    guard rect.maxY > 0 else { continue }
                    if rect.contains(point) {
                        return item.id
                    }
                }
            }
        }
        return hoveredID
    }

    private func handleRowHover(item: TabItem, inside: Bool) {
        guard !isRefreshing else { return }
        if inside {
            if isPointerInsidePinnedRow, let pinnedRowID {
                unhoverTask?.cancel()
                unhoverTask = nil
                hoveredID = pinnedRowID
                return
            }
            unhoverTask?.cancel()
            unhoverTask = nil
            hoveredID = item.id
        } else if hoveredID == item.id {
            if isPointerInsidePinnedRow, pinnedRowID == item.id {
                return
            }
            unhoverTask?.cancel()
            let leavingID = item.id
            let delayMs = isScrolling ? 200 : 45
            unhoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled, hoveredID == leavingID, !isPointerInsidePinnedRow else { return }
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
    let onSelect: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var icon: String {
        switch item.type {
        case .HISTORY: "clock"
        case .OPENED_TAB: "safari"
        case .SEARCH: "magnifyingglass"
        case .URL: "arrow.up.right.square"
        }
    }

    private var iconTint: Color {
        if isSelected || isHovered || item.type == .OPENED_TAB || item.type == .URL {
            return .accentColor
        }
        return .secondary
    }

    private var iconBadgeBackground: Color {
        if isSelected || isHovered || item.type == .OPENED_TAB || item.type == .URL {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
    }

    private var rowFillColor: Color {
        if isSelected {
            return Color.accentColor.opacity(contrast == .increased ? 0.24 : (colorScheme == .dark ? 0.17 : 0.12))
        }
        if isHovered {
            return Color.primary.opacity(contrast == .increased ? 0.14 : (colorScheme == .dark ? 0.08 : 0.05))
        }
        return .clear
    }

    private var rowStrokeColor: Color {
        if isSelected {
            return Color.accentColor.opacity(contrast == .increased ? 0.55 : 0.30)
        }
        if isHovered {
            return Color.primary.opacity(contrast == .increased ? 0.22 : 0.08)
        }
        return .clear
    }

    var body: some View {
        if let onSelect {
            Button(action: onSelect) {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityLabel(item.title + ", " + item.subtitle)
        } else {
            rowContent
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityLabel(item.title + ", " + item.subtitle)
        }
    }

    private var rowContent: some View {
        let rowShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconBadgeBackground)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconTint)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2.5) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.type == .OPENED_TAB {
                OpenTabProfilesControl(itemID: item.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if isPinned {
                StickyRowGlassSurface(colorScheme: colorScheme, contrast: contrast)
            } else {
                rowShape
                    .fill(rowFillColor)
                    .overlay {
                        rowShape.strokeBorder(rowStrokeColor, lineWidth: 0.75)
                    }
            }
        }
    }
}

private struct StickyRowGlassSurface: View {
    let colorScheme: ColorScheme
    let contrast: ColorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        let rimColor = colorScheme == .dark
            ? Color.accentColor.opacity(contrast == .increased ? 0.55 : 0.36)
            : Color.accentColor.opacity(contrast == .increased ? 0.45 : 0.28)
        if reduceTransparency {
            shape
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    shape.strokeBorder(Color.accentColor.opacity(contrast == .increased ? 0.65 : 0.45), lineWidth: 1)
                }
        } else {
            Color.clear
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.14)), in: shape)
                .overlay {
                    shape.strokeBorder(rimColor, lineWidth: 0.75)
                }
        }
    }
}
