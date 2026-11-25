import Observation
import SwiftUI

@MainActor
@Observable
final class TabGroupBubbleModel {
    var groups: [SafariTabGroupOption] = []
    /// Index of the tab group Safari currently has open when the swipe began (`nil` if on default no-group).
    var initialActiveIndex: Int?
    /// Index currently highlighted by the Liquid Glass toggle thumb (`nil` only while neutral on default no-group).
    var selectedIndex: Int?
    /// Normalized elastic magnetic pull in `-1.0 ... 1.0` toward the adjacent slot before breakout.
    var magneticPull: CGFloat = 0
    /// Controls appear / disappear animation inside the floating panel.
    var isVisible: Bool = false
}

private struct BubbleSegmentFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TabGroupBubbleView: View {
    let model: TabGroupBubbleModel

    @State private var segmentFrames: [Int: CGRect] = [:]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let trackSpace = "TabGroupBubbleTrack"

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack(alignment: .topLeading) {
                // Morphing Liquid Glass toggle thumb behind the segment labels.
                if let selectedIndex = model.selectedIndex,
                   let rect = segmentFrames[selectedIndex] {
                    let pull = reduceMotion ? 0 : model.magneticPull
                    let stretchWidth = abs(pull) * 7
                    let offsetX = pull * 10
                    let thumbWidth = rect.width + stretchWidth

                    selectionThumb
                        .frame(width: thumbWidth, height: rect.height)
                        .position(x: rect.midX + offsetX, y: rect.midY)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.78),
                            value: selectedIndex
                        )
                        .animation(
                            reduceMotion ? nil : .interactiveSpring(response: 0.11, dampingFraction: 0.86),
                            value: pull
                        )
                }

                // All tab group segments in a single horizontal multivalue toggle row.
                HStack(spacing: 3) {
                    ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                        let isSelected = model.selectedIndex == index
                        let isStartingGroup = model.initialActiveIndex == index

                        HStack(spacing: 6) {
                            if isStartingGroup {
                                Circle()
                                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.55))
                                    .frame(width: 5.5, height: 5.5)
                            }
                            Text(group.title)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: BubbleSegmentFrameKey.self,
                                    value: [index: geo.frame(in: .named(trackSpace))]
                                )
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: trackSpace)
            .onPreferenceChange(BubbleSegmentFrameKey.self) { frames in
                segmentFrames = frames
            }
            .padding(4)
            .modifier(
                BubbleTrackGlassSurface(
                    colorScheme: colorScheme,
                    contrast: contrast,
                    reduceTransparency: reduceTransparency
                )
            )
        }
        .fixedSize()
        .padding(24)
        .scaleEffect(model.isVisible || reduceMotion ? 1.0 : 0.92)
        .opacity(model.isVisible ? 1.0 : 0.0)
        .animation(
            reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.84),
            value: model.isVisible
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var selectionThumb: some View {
        let shape = Capsule()
        let rimColor = colorScheme == .dark
            ? Color.white.opacity(contrast == .increased ? 0.36 : 0.24)
            : Color.accentColor.opacity(contrast == .increased ? 0.45 : 0.28)
        if reduceTransparency {
            shape
                .fill(Color.accentColor.opacity(0.20))
                .overlay {
                    shape.strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                }
        } else {
            Color.clear
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.18)), in: shape)
                .overlay {
                    shape.strokeBorder(rimColor, lineWidth: 0.75)
                }
        }
    }
}

private struct BubbleTrackGlassSurface: ViewModifier {
    let colorScheme: ColorScheme
    let contrast: ColorSchemeContrast
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        let shape = Capsule()
        let rimColor = colorScheme == .dark
            ? Color.white.opacity(contrast == .increased ? 0.28 : 0.16)
            : Color.black.opacity(contrast == .increased ? 0.20 : 0.09)
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay {
                    shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
        } else {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.strokeBorder(rimColor, lineWidth: 0.75)
                }
        }
    }
}
