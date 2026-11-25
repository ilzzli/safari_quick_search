import AppKit
import SwiftUI

/// Hosts `TabGroupBubbleView` in a floating, non-activating, click-through `NSPanel`
/// centered over Safari's frontmost window while scrubbing between tab groups.
@MainActor
final class TabGroupBubblePanelController {
    private let model = TabGroupBubbleModel()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TabGroupBubbleView>?
    private var hideTask: Task<Void, Never>?

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
            let targetFrame = centeredFrame(size: size, over: safariWindowFrame)
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

    private func centeredFrame(size: NSSize, over safariFrame: NSRect?) -> NSRect {
        let referenceFrame = safariFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let originX = round(referenceFrame.midX - size.width / 2)
        // Float slightly above vertical center of Safari's window so it's immediately in view.
        let originY = round(referenceFrame.minY + referenceFrame.height * 0.54 - size.height / 2)
        return NSRect(x: originX, y: originY, width: ceil(size.width), height: ceil(size.height))
    }
}
