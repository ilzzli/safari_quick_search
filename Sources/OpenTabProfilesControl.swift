import SwiftUI

struct OpenTabIconAnchorKey: PreferenceKey {
    static let defaultValue: [TabItem.ID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TabItem.ID: Anchor<CGRect>],
        nextValue: () -> [TabItem.ID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Invisible trailing anchor inside an opened-tab row; reports its bounds for the singleton popup.
struct OpenTabProfilesControl: View {
    let itemID: TabItem.ID

    var body: some View {
        Color.clear
            .frame(width: 1, height: 32)
            .anchorPreference(key: OpenTabIconAnchorKey.self, value: .bounds) { [itemID: $0] }
            .accessibilityHidden(true)
    }
}

/// Singleton Liquid Glass popup that glides between active/hovered opened-tab rows.
struct OpenTabProfilesPopupOverlay: View {
    let items: [TabItem]
    let activeItem: TabItem?
    let pointerLocation: CGPoint?
    let allProfiles: [SafariProfileGroups]
    let showAllWindows: Bool
    let isPointerHovered: Bool
    let isPointerInsidePinnedRow: Bool
    let isScrolling: Bool
    let anchors: [TabItem.ID: Anchor<CGRect>]
    let rowAnchors: [TabItem.ID: Anchor<CGRect>]
    let pinnedRowID: TabItem.ID?
    let proxy: GeometryProxy

    private static let topViewportPadding: CGFloat = 4
    private static let bottomViewportPadding: CGFloat = 12
    private static let rowVerticalGap: CGFloat = 5
    private static let rowTrailingGap: CGFloat = 6.5
    private static let rowBorderCompensation: CGFloat = 0.75

    @State private var displayedItem: TabItem?
    @State private var appearProgress: CGFloat = 0
    @State private var glideGeneration = 0
    @State private var dismissTask: Task<Void, Never>?
    @State private var measuredSizes: [TabItem.ID: CGSize] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private struct GroupChip: Equatable {
        let title: String
        let isHighlighted: Bool
    }

    private struct ProfileEntry: Equatable {
        let id: String
        let name: String
        var groups: [GroupChip]
        var hasMatch: Bool
    }

    private func matchedProfiles(for tabs: [SafariTabMatch]) -> [ProfileEntry] {
        var result: [ProfileEntry] = []
        for tab in tabs {
            guard tab.windowID != nil else { continue }
            let id = String(tab.activeProfileID ?? -1)
            let name = SafariTabGroup.normalizedProfileName(tab.activeProfileName)
            let groupTitle = SafariTabGroup.normalizedTitle(tab.groupName)
            if let index = result.firstIndex(where: { $0.id == id }) {
                if !result[index].groups.contains(where: { $0.title == groupTitle }) {
                    result[index].groups.append(GroupChip(title: groupTitle, isHighlighted: true))
                }
            } else {
                result.append(
                    ProfileEntry(
                        id: id,
                        name: name,
                        groups: [GroupChip(title: groupTitle, isHighlighted: true)],
                        hasMatch: true
                    )
                )
            }
        }
        return result
    }

    private func allWindowProfiles(for tabs: [SafariTabMatch]) -> [ProfileEntry] {
        guard !allProfiles.isEmpty else {
            return matchedProfiles(for: tabs)
        }
        return allProfiles.map { profile in
            let matchingGroupIDs = Set(
                tabs.filter {
                    $0.activeProfileID.map(String.init) == profile.id && $0.windowID != nil
                }.map { String($0.groupID) }
            )
            let chips = profile.groups.map { group in
                GroupChip(
                    title: group.title,
                    isHighlighted: !group.sourceIDs.isDisjoint(with: matchingGroupIDs)
                )
            }
            return ProfileEntry(
                id: profile.id,
                name: profile.title,
                groups: chips,
                hasMatch: chips.contains(where: \.isHighlighted)
            )
        }
    }

    private func profiles(for tabs: [SafariTabMatch]) -> [ProfileEntry] {
        showAllWindows ? allWindowProfiles(for: tabs) : matchedProfiles(for: tabs)
    }

    /// Synchronously resolves the active opened-tab item on the exact frame the scroll offset changes,
    /// using the live pointer location to hit-test the row under the cursor before `.onHover` catches up.
    private var resolvedActiveItem: TabItem? {
        if isPointerInsidePinnedRow {
            return activeItem
        }
        if isPointerHovered, let point = pointerLocation {
            var closestOpenedItem: TabItem?
            var closestDistance = CGFloat.greatestFiniteMagnitude
            for item in items where item.type == .OPENED_TAB {
                guard item.id != pinnedRowID else { continue }
                guard let anchor = anchors[item.id] else { continue }
                let rect = proxy[anchor]
                guard rect.maxY > 0 else { continue }
                let distance = abs(rect.midY - point.y)
                if distance <= 36 && distance < closestDistance {
                    closestDistance = distance
                    closestOpenedItem = item
                }
            }
            if let closestOpenedItem {
                return closestOpenedItem
            }
        }
        return activeItem
    }

    private var activeAnchorExists: Bool {
        guard let id = resolvedActiveItem?.id else { return false }
        return anchors[id] != nil
    }

    var body: some View {
        let liveItem = resolvedActiveItem
        let currentItem = liveItem ?? displayedItem
        ZStack(alignment: .bottomTrailing) {
            if let item = currentItem, let anchor = anchors[item.id] {
                let iconRect = proxy[anchor]
                let rowRect = rowAnchors[item.id].map { proxy[$0] }
                let rowHeight = rowRect?.height ?? 46
                let verticalInset = Self.rowVerticalGap + Self.rowBorderCompensation
                let trailingInset = Self.rowTrailingGap + Self.rowBorderCompensation
                let targetHeight = max(rowHeight - verticalInset * 2, 28)
                let targetWidth = measuredSizes[item.id]?.width
                let halfHeight = targetHeight / 2
                let targetCenterY: CGFloat = {
                    if pinnedRowID == item.id, let rowRect {
                        return rowRect.midY
                    }
                    let rawCenterY = rowRect?.midY ?? iconRect.midY
                    let minCenterY = halfHeight + Self.topViewportPadding + verticalInset
                    let maxCenterY = max(
                        proxy.size.height - Self.bottomViewportPadding - verticalInset - halfHeight,
                        minCenterY
                    )
                    return min(max(rawCenterY, minCenterY), maxCenterY)
                }()
                let targetRightX = (rowRect?.maxX ?? (iconRect.maxX + 12)) - trailingInset

                popupInnerContent(for: item)
                    .accessibilityHidden(appearProgress == 0)
                    .modifier(
                        AnimatablePopupLayoutModifier(
                            width: targetWidth,
                            height: targetHeight,
                            rightX: targetRightX,
                            centerY: targetCenterY,
                            appearProgress: appearProgress,
                            reduceTransparency: reduceTransparency
                        )
                    )
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24).delay(0.035), value: liveItem?.id)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: glideGeneration)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: targetCenterY)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .clipped()
        .background {
            ZStack {
                ForEach(items.filter { $0.type == .OPENED_TAB }) { item in
                    popupInnerContent(for: item)
                        .onGeometryChange(for: CGSize.self) { geo in
                            geo.size
                        } action: { newSize in
                            measuredSizes[item.id] = newSize
                        }
                }
            }
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
        .onChange(of: resolvedActiveItem, initial: true) { _, _ in
            syncPopupState()
        }
        .onChange(of: activeAnchorExists) { _, _ in
            syncPopupState()
        }
        .onChange(of: showAllWindows) { _, _ in
            glideGeneration &+= 1
        }
    }

    private func syncPopupState() {
        dismissTask?.cancel()
        dismissTask = nil

        if let activeItem = resolvedActiveItem, anchors[activeItem.id] != nil {
            let wasHidden = (displayedItem == nil && appearProgress == 0)
            displayedItem = activeItem
            if wasHidden {
                Task { @MainActor in
                    guard self.resolvedActiveItem != nil else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        self.appearProgress = 1
                    }
                }
            } else if appearProgress < 1 {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    appearProgress = 1
                }
            }
        } else if resolvedActiveItem == nil {
            let debounceMs = isScrolling ? 160 : 50
            let closeAnimDuration = 0.20
            let removeDelayMs = reduceMotion ? 0 : 210
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(debounceMs))
                guard !Task.isCancelled, self.resolvedActiveItem == nil else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: closeAnimDuration)) {
                    self.appearProgress = 0
                }
                if removeDelayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(removeDelayMs))
                }
                guard !Task.isCancelled, self.resolvedActiveItem == nil else { return }
                self.displayedItem = nil
            }
        }
    }

    private func popupInnerContent(for item: TabItem) -> some View {
        let itemProfiles = profiles(for: item.openTabs)
        return HStack(spacing: 12) {
            if itemProfiles.isEmpty {
                Text("Profile unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(itemProfiles.enumerated()), id: \.offset) { _, profile in
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(profile.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(profile.hasMatch ? .primary : .secondary)
                    if showAllWindows {
                        HStack(spacing: 4) {
                            ForEach(Array(profile.groups.enumerated()), id: \.offset) { _, group in
                                Text(group.title)
                                    .font(.system(size: 10, weight: group.isHighlighted ? .semibold : .medium))
                                    .foregroundStyle(group.isHighlighted ? Color.accentColor : .secondary)
                                    .padding(.horizontal, 6.5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        group.isHighlighted
                                            ? Color.accentColor.opacity(0.16)
                                            : Color.primary.opacity(0.06),
                                        in: Capsule()
                                    )
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                group.isHighlighted
                                                    ? Color.accentColor.opacity(0.32)
                                                    : Color.primary.opacity(0.08),
                                                lineWidth: 0.5
                                            )
                                    }
                            }
                        }
                    } else {
                        Text(profile.groups.map(\.title).joined(separator: " · "))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .fixedSize()
    }
}

struct AnimatablePopupLayoutModifier: ViewModifier, Animatable {
    var width: CGFloat
    var height: CGFloat
    var rightX: CGFloat
    var centerY: CGFloat
    var appearProgress: CGFloat
    let hasMeasuredSize: Bool
    let reduceTransparency: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        width: CGFloat?,
        height: CGFloat?,
        rightX: CGFloat,
        centerY: CGFloat,
        appearProgress: CGFloat = 1,
        reduceTransparency: Bool
    ) {
        if let width, let height {
            self.width = width
            self.height = height
            self.hasMeasuredSize = true
        } else {
            self.width = 0
            self.height = 0
            self.hasMeasuredSize = false
        }
        self.rightX = rightX
        self.centerY = centerY
        self.appearProgress = appearProgress
        self.reduceTransparency = reduceTransparency
    }

    var animatableData: AnimatablePair<
        AnimatablePair<
            AnimatablePair<CGFloat, CGFloat>,
            AnimatablePair<CGFloat, CGFloat>
        >,
        CGFloat
    > {
        get {
            AnimatablePair(
                AnimatablePair(
                    AnimatablePair(width, height),
                    AnimatablePair(rightX, centerY)
                ),
                appearProgress
            )
        }
        set {
            width = newValue.first.first.first
            height = newValue.first.first.second
            rightX = newValue.first.second.first
            centerY = newValue.first.second.second
            appearProgress = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let clampedProgress = min(max(appearProgress, 0), 1)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let currentWidth = max(width * clampedProgress, 0)
        let currentHeight = max(height * (0.65 + 0.35 * clampedProgress), 0)
        let rimColor = colorScheme == .dark
            ? Color.white.opacity(contrast == .increased ? 0.28 : 0.16)
            : Color.black.opacity(contrast == .increased ? 0.20 : 0.08)

        Group {
            if clampedProgress > 0.01 {
                let w = max(currentWidth, 1)
                let h = max(currentHeight, 1)

                let framed = Group {
                    if hasMeasuredSize {
                        content
                            .opacity(clampedProgress)
                            .frame(width: w, height: h, alignment: .center)
                            .clipped()
                            .clipShape(shape)
                    } else {
                        content
                            .opacity(clampedProgress)
                            .clipShape(shape)
                    }
                }

                let styled = Group {
                    if reduceTransparency {
                        framed
                            .background(Color(nsColor: .controlBackgroundColor), in: shape)
                            .overlay {
                                shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                            }
                    } else {
                        framed
                            .glassEffect(.regular, in: shape)
                            .overlay {
                                shape.strokeBorder(rimColor, lineWidth: 0.75)
                            }
                    }
                }

                styled
                    .position(
                        x: hasMeasuredSize ? (rightX - w / 2) : rightX,
                        y: centerY
                    )
            }
        }
    }
}
