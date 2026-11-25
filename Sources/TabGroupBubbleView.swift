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
                HStack(spacing: 4) {
                    ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                        let isSelected = model.selectedIndex == index
                        let isStartingGroup = model.initialActiveIndex == index

                        HStack(spacing: 6) {
                            if isStartingGroup {
                                Circle()
                                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))
                                    .frame(width: 6, height: 6)
                            }
                            Text(group.title)
                                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
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
            .padding(5)
            .modifier(BubbleTrackGlassSurface(reduceTransparency: reduceTransparency))
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
        if reduceTransparency {
            shape
                .fill(Color.accentColor.opacity(0.22))
                .overlay {
                    shape.strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                }
        } else {
            Color.clear
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.20)), in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.32), lineWidth: 0.75)
                }
        }
    }
}

private struct BubbleTrackGlassSurface: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        let shape = Capsule()
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                }
        } else {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                }
        }
    }
}
