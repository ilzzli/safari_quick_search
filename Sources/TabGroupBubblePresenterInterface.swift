import AppKit

/// Presents the floating tab group multivalue toggle bubble while the user scrubs with 3 fingers.
@MainActor
protocol TabGroupBubblePresenterInterface: AnyObject {
    func show(
        groups: [SafariTabGroupOption],
        initialActiveIndex: Int?,
        selectedIndex: Int?,
        safariWindowFrame: NSRect?
    )
    func update(selectedIndex: Int?, magneticPull: CGFloat)
    func dismiss(immediate: Bool)
}

extension TabGroupBubblePresenterInterface {
    func dismiss() {
        dismiss(immediate: false)
    }
}
