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

/// The trailing window icon inside an opened-tab row; reports its bounds for the singleton popup.
struct OpenTabProfilesControl: View {
    let itemID: TabItem.ID
    let isExpanded: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let icon = Image(systemName: "macwindow")
            .font(.system(size: 14))
            .foregroundStyle(isExpanded ? .primary : .secondary)
            .frame(width: 34, height: 32)
            .accessibilityHidden(true)

        Group {
            if reduceTransparency {
                icon
                    .background(Color(nsColor: .windowBackgroundColor).opacity(isExpanded ? 1 : 0.45), in: shape)
                    .overlay {
                        shape.strokeBorder(Color.primary.opacity(isExpanded ? 0.18 : 0.08), lineWidth: 1)
                    }
            } else {
                icon
                    .glassEffect(.regular, in: shape)
            }
        }
        .anchorPreference(key: OpenTabIconAnchorKey.self, value: .bounds) { [itemID: $0] }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open tab profiles")
    }
}

/// Singleton Liquid Glass popup that glides between active/hovered opened-tab rows.
struct OpenTabProfilesPopupOverlay: View {
    let items: [TabItem]
    let activeItem: TabItem?
    let anchors: [TabItem.ID: Anchor<CGRect>]
    let proxy: GeometryProxy

    @State private var displayedItem: TabItem?
    @State private var isPresented = false
    @State private var glideGeneration = 0
    @State private var measuredSizes: [TabItem.ID: CGSize] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private struct Profile: Equatable {
        let id: Int64
        let name: String
        var groups: [String]
    }

    private func profiles(for tabs: [SafariTabMatch]) -> [Profile] {
        var result: [Profile] = []
        for tab in tabs {
            guard tab.windowID != nil else { continue }
            let id = tab.activeProfileID ?? -1
            let name = tab.activeProfileName.flatMap { $0.isEmpty ? nil : $0 } ?? "Default"
            let group = ["local", "unnamed", ""].contains(tab.groupName.lowercased()) ? "Base" : tab.groupName
            if let index = result.firstIndex(where: { $0.id == id }) {
                if !result[index].groups.contains(group) { result[index].groups.append(group) }
            } else {
                result.append(Profile(id: id, name: name, groups: [group]))
            }
        }
        return result
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
                let visible = isPresented && isWithinVisibleBounds

                let targetSize = measuredSizes[item.id]
                let popupHeight = targetSize?.height ?? 44
                let halfHeight = popupHeight / 2
                let clampedCenterY = min(
                    max(iconRect.midY, halfHeight + 4),
                    max(proxy.size.height - halfHeight - 4, halfHeight + 4)
                )

                popupInnerContent(for: item)
                    .accessibilityHidden(!isPresented)
                    .modifier(
                        AnimatablePopupLayoutModifier(
                            width: targetSize?.width,
                            height: targetSize?.height,
                            rightX: iconRect.maxX,
                            centerY: clampedCenterY,
                            visible: visible,
                            appearOffsetY: iconRect.midY - clampedCenterY,
                            reduceMotion: reduceMotion,
                            reduceTransparency: reduceTransparency
                        )
                    )
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: glideGeneration)
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
    }

    private func syncPopupState() {
        if let activeItem, anchors[activeItem.id] != nil {
            if !isPresented {
                let wasNil = (displayedItem == nil)
                displayedItem = activeItem
                if wasNil {
                    Task { @MainActor in
                        guard self.activeItem != nil else { return }
                        self.isPresented = true
                    }
                } else {
                    isPresented = true
                }
            } else if displayedItem != activeItem {
                displayedItem = activeItem
                glideGeneration &+= 1
            }
        } else if activeItem == nil {
            isPresented = false
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
                VStack(alignment: .leading, spacing: 3) {
                    Label(profile.name, systemImage: "person.crop.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(profile.groups.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
    let visible: Bool
    let appearOffsetY: CGFloat
    let reduceMotion: Bool
    let hasMeasuredSize: Bool
    let reduceTransparency: Bool

    init(
        width: CGFloat?,
        height: CGFloat?,
        rightX: CGFloat,
        centerY: CGFloat,
        visible: Bool = true,
        appearOffsetY: CGFloat = 0,
        reduceMotion: Bool = false,
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
        self.visible = visible
        self.appearOffsetY = appearOffsetY
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
    }

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(width, height),
                AnimatablePair(rightX, centerY)
            )
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            rightX = newValue.second.first
            centerY = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let w = max(width, 1)
        let h = max(height, 1)

        let framed = Group {
            if hasMeasuredSize {
                content
                    .frame(width: w, height: h, alignment: .leading)
                    .clipped()
                    .clipShape(shape)
            } else {
                content
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
                    .clipShape(shape)
            }
        }

        styled
            .scaleEffect(visible ? 1.0 : 0.18, anchor: .trailing)
            .opacity(visible ? 1.0 : 0.0)
            .offset(y: visible ? 0 : appearOffsetY)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: visible)
            .position(
                x: hasMeasuredSize ? (rightX - w / 2) : rightX,
                y: centerY
            )
    }
}
