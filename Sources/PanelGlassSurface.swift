import SwiftUI

struct PanelGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
