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
    let allProfiles: [SafariProfileGroups]
    let showAllWindows: Bool
    let anchors: [TabItem.ID: Anchor<CGRect>]
    let proxy: GeometryProxy

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
            let name = tab.activeProfileName.flatMap { $0.isEmpty ? nil : $0 } ?? "Default"
            let groupTitle = ["local", "unnamed", ""].contains(tab.groupName.lowercased()) ? "Base" : tab.groupName
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

    private var activeAnchorExists: Bool {
        guard let id = activeItem?.id else { return false }
        return anchors[id] != nil
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let item = displayedItem, let anchor = anchors[item.id] {
                let iconRect = proxy[anchor]
                let isWithinVisibleBounds = iconRect.minY >= 0 && iconRect.maxY <= proxy.size.height
                let effectiveProgress = isWithinVisibleBounds ? appearProgress : 0

                let targetSize = measuredSizes[item.id]
                let popupHeight = targetSize?.height ?? 44
                let halfHeight = popupHeight / 2
                let clampedCenterY = min(
                    max(iconRect.midY, halfHeight + 4),
                    max(proxy.size.height - halfHeight - 4, halfHeight + 4)
                )

                popupInnerContent(for: item)
                    .accessibilityHidden(effectiveProgress == 0)
                    .modifier(
                        AnimatablePopupLayoutModifier(
                            width: targetSize?.width,
                            height: targetSize?.height,
                            rightX: iconRect.maxX,
                            centerY: clampedCenterY,
                            appearProgress: effectiveProgress,
                            reduceTransparency: reduceTransparency
                        )
                    )
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: glideGeneration)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isWithinVisibleBounds)
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
        .onChange(of: activeItem, initial: true) { _, _ in
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

        if let activeItem, anchors[activeItem.id] != nil {
            if displayedItem == nil {
                displayedItem = activeItem
                appearProgress = 0
                Task { @MainActor in
                    guard self.activeItem != nil else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        self.appearProgress = 1
                    }
                }
            } else if appearProgress < 1 {
                displayedItem = activeItem
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    appearProgress = 1
                }
            } else if displayedItem != activeItem {
                displayedItem = activeItem
                glideGeneration &+= 1
            }
        } else if activeItem == nil {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.20)) {
                appearProgress = 0
            }
            let delayMs = reduceMotion ? 0 : 210
            dismissTask = Task { @MainActor in
                if delayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(delayMs))
                }
                guard !Task.isCancelled, self.activeItem == nil else { return }
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
                VStack(alignment: .leading, spacing: 4) {
                    Label(profile.name, systemImage: "person.crop.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(profile.hasMatch ? .primary : .secondary)
                    if showAllWindows {
                        HStack(spacing: 4) {
                            ForEach(Array(profile.groups.enumerated()), id: \.offset) { _, group in
                                Label(
                                    group.title,
                                    systemImage: group.isHighlighted ? "checkmark.circle.fill" : "rectangle.on.rectangle"
                                )
                                .font(.caption2.weight(group.isHighlighted ? .semibold : .regular))
                                .foregroundStyle(group.isHighlighted ? .primary : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    group.isHighlighted ? Color.yellow.opacity(0.22) : Color.secondary.opacity(0.08),
                                    in: Capsule()
                                )
                            }
                        }
                    } else {
                        Text(profile.groups.map(\.title).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let currentWidth = max(width * clampedProgress, 0)
        let currentHeight = max(height * (0.65 + 0.35 * clampedProgress), 0)

        Group {
            if clampedProgress > 0.01 {
                let w = max(currentWidth, 1)
                let h = max(currentHeight, 1)

                let framed = Group {
                    if hasMeasuredSize {
                        content
                            .opacity(clampedProgress)
                            .frame(width: w, height: h, alignment: .leading)
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
                            .background(Color(nsColor: .windowBackgroundColor), in: shape)
                            .overlay {
                                shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                            }
                    } else {
                        framed
                            .glassEffect(.regular, in: shape)
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
