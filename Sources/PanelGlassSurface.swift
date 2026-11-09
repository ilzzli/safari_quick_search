import SwiftUI

struct PanelGlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.17, green: 0.17, blue: 0.18)
            : Color(red: 0.93, green: 0.93, blue: 0.94)
    }

    func body(content: Content) -> some View {
        content
            .background(backgroundColor, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
    }
}
