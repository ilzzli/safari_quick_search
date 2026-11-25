import AppKit
import SwiftUI

private final class AppPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let actions = AppActions()
    private let swipeMonitor: any SwipeMonitorInterface = SystemSwipeEventMonitor()
    private let safariTabGroupSwitcher: any SafariTabGroupSwitcherInterface = ShortcutTabGroupSwitcher(
        fallback: SafariControl()
    )
    private lazy var hotkeys = HotkeyRegistration(
        actions: HotkeysActionsProvider(togglePanelAction: { [weak self] in
            self?.actions.togglePanel()
        }),
        safari: safariTabGroupSwitcher,
        swipeMonitor: swipeMonitor
    )
    private let tabSupplier: any TabSupplierInterface = TabSupplier(actions: TabActions())
    private let tabGroups: any TabGroupsInterface = SafariTabGroups()
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        let panel = AppPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: PanelLayout(actions: actions, tabSupplier: tabSupplier, tabGroups: tabGroups))
        self.panel = panel
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - 350, y: visible.midY - 250))
        } else {
            panel.center()
        }
        actions.attachPanel(panel)
        actions.showPanel()
        hotkeys.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
        actions.hidePanel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        actions.showPanel()
        return true
    }
}

@main
struct SafariQuickSearchApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
