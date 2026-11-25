import AppKit
import SwiftUI

/// Hosts `TabGroupBubbleView` in a floating, non-activating, click-through `NSPanel`
/// positioned cleanly above the search panel (when visible) or near the top of Safari's window.
@MainActor
final class TabGroupBubblePanelController: TabGroupBubblePresenterInterface {
    /// Matches `TabGroupBubbleView`'s outer transparent shadow/animation padding (`24pt`).
    private static let viewOuterPadding: CGFloat = 24
    /// Visual gap between the search panel's top border and the bubble's bottom border.
    private static let gapAboveSearchPanel: CGFloat = 10

    private let searchPanelFrameProvider: @MainActor () -> NSRect?
    private let model = TabGroupBubbleModel()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TabGroupBubbleView>?
    private var hideTask: Task<Void, Never>?

    init(searchPanelFrameProvider: @escaping @MainActor () -> NSRect? = { nil }) {
        self.searchPanelFrameProvider = searchPanelFrameProvider
    }

    func show(
        groups: [SafariTabGroupOption],
        initialActiveIndex: Int?,
        selectedIndex: Int?,
        safariWindowFrame: NSRect?
    ) {
        hideTask?.cancel()
        hideTask = nil

        model.groups = groups
        model.initialActiveIndex = initialActiveIndex
        model.selectedIndex = selectedIndex
        model.magneticPull = 0

        let panel = ensurePanel()
        if let hostingView {
            hostingView.layoutSubtreeIfNeeded()
            let size = hostingView.fittingSize
            let targetFrame = positionedFrame(size: size, safariFrame: safariWindowFrame)
            panel.setFrame(targetFrame, display: true)
        }

        panel.orderFrontRegardless()
        model.isVisible = true
    }

    func update(selectedIndex: Int?, magneticPull: CGFloat) {
        model.selectedIndex = selectedIndex
        model.magneticPull = magneticPull
    }

    func dismiss(immediate: Bool = false) {
        hideTask?.cancel()
        hideTask = nil

        guard let panel else { return }
        model.magneticPull = 0
        model.isVisible = false

        if immediate {
            panel.orderOut(nil)
            return
        }

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, !self.model.isVisible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        let hostingView = NSHostingView(rootView: TabGroupBubbleView(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func positionedFrame(size: NSSize, safariFrame: NSRect?) -> NSRect {
        let width = ceil(size.width)
        let height = ceil(size.height)

        // When the Quick Search panel is open, place the bubble horizontally centered
        // directly above the panel's top edge (matching the screenshot layout).
        if let searchFrame = searchPanelFrameProvider() {
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(searchFrame) }) ?? NSScreen.main
            let originX = round(searchFrame.midX - width / 2)
            var originY = round(searchFrame.maxY + Self.gapAboveSearchPanel - Self.viewOuterPadding)
            if let visible = screen?.visibleFrame {
                let maxOriginY = visible.maxY - height + Self.viewOuterPadding - 4
                originY = min(originY, round(maxOriginY))
            }
            return NSRect(x: originX, y: originY, width: width, height: height)
        }

        // Otherwise, place the bubble horizontally centered in the upper HUD zone
        // (matching where above-the-centered-panel sits on screen / below Safari's toolbar).
        let screen = safariFrame.flatMap { sf in
            NSScreen.screens.first(where: { $0.frame.intersects(sf) })
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let referenceFrame = safariFrame ?? visible

        let originX = round(referenceFrame.midX - width / 2)
        let idealVisualBottomY = visible.midY + 250 + Self.gapAboveSearchPanel
        let maxSafariVisualTopY = referenceFrame.maxY - 62
        let visualHeight = max(height - Self.viewOuterPadding * 2, 36)
        let clampedVisualBottomY = min(idealVisualBottomY, maxSafariVisualTopY - visualHeight)
        let originY = round(max(clampedVisualBottomY - Self.viewOuterPadding, referenceFrame.minY + 40))

        return NSRect(x: originX, y: originY, width: width, height: height)
    }
}
