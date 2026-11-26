import AppKit
import Carbon
import SwiftUI

private final class AppPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) {
            return true
        }
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return performEditingKeyEquivalent(with: event)
    }

    private func performEditingKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        let asciiKey: String? = {
            if let chars = event.charactersIgnoringModifiers?.lowercased(),
               !chars.isEmpty,
               chars.unicodeScalars.allSatisfy(\.isASCII) {
                return chars
            }
            switch Int(event.keyCode) {
            case kVK_ANSI_A: return "a"
            case kVK_ANSI_C: return "c"
            case kVK_ANSI_V: return "v"
            case kVK_ANSI_X: return "x"
            case kVK_ANSI_Z: return "z"
            default: return nil
            }
        }()

        guard let key = asciiKey else { return false }

        let action: Selector?
        switch (key, flags) {
        case ("x", [.command]):
            action = #selector(NSText.cut(_:))
        case ("c", [.command]):
            action = #selector(NSText.copy(_:))
        case ("v", [.command]):
            action = #selector(NSText.paste(_:))
        case ("v", [.command, .option, .shift]):
            action = #selector(NSTextView.pasteAsPlainText(_:))
        case ("a", [.command]):
            action = #selector(NSText.selectAll(_:))
        case ("z", [.command]):
            action = Selector(("undo:"))
        case ("z", [.command, .shift]):
            action = Selector(("redo:"))
        default:
            action = nil
        }

        guard let action else { return false }
        if NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        var responder = firstResponder
        while let candidate = responder {
            if candidate.responds(to: action) {
                return NSApp.sendAction(action, to: candidate, from: self)
            }
            responder = candidate.nextResponder
        }
        return false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let actions = AppActions()
    private let shortcutTabGroupSwitcher = ShortcutTabGroupSwitcher(
        fallback: SafariControl()
    )
    private lazy var bubblePresenter: any TabGroupBubblePresenterInterface = TabGroupBubblePanelController(
        searchPanelFrameProvider: { [weak self] in
            self?.actions.panelFrame
        }
    )
    private lazy var swipeHandler: any SafariSwipeHandlerInterface = BubbleSafariSwipeHandler(
        scrubMonitor: SystemSwipeScrubMonitor(),
        shortcutSwitcher: shortcutTabGroupSwitcher,
        bubblePresenter: bubblePresenter
    )
    // Swap to `DiscreteSafariSwipeHandler(swipeMonitor: SystemSwipeOnReleaseMonitor(), switcher: shortcutTabGroupSwitcher)`
    // (or `SystemSwipeEventMonitor()` / `ThreeFingerSwipeMonitor()` / `SafariControl()`) to switch approaches in one place.
    private lazy var hotkeys = HotkeyRegistration(
        actions: HotkeysActionsProvider(togglePanelAction: { [weak self] in
            self?.actions.togglePanel()
        }),
        swipeHandler: swipeHandler
    )
    private lazy var tabActions: any TabActionInterface = SafariTabActions(onComplete: { [weak self] in
        self?.actions.hidePanel()
    })
    // Swap to `TabActions()` to restore the debug inspection alert implementation.
    private lazy var tabSupplier: any TabSupplierInterface = TabSupplier(actions: tabActions)
    private let tabGroups: any TabGroupsInterface = SafariTabGroups()
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()
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

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = NSMenu()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pastePlainItem = editMenu.addItem(
            withTitle: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pastePlainItem.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
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
