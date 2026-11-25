import SwiftUI

struct PanelGlassSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    func body(content: Content) -> some View {
        let strokeOpacity = contrast == .increased ? 0.28 : 0.12
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(Color(nsColor: .separatorColor).opacity(contrast == .increased ? 0.9 : 0.55), lineWidth: 1)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 0.75)
                }
        }
    }
}
