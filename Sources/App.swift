import AppKit
import Carbon
import SwiftUI

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    func register() -> OSStatus {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            hotkey.action?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return installed }
        // Change the key code/modifiers here to customize the shortcut.
        return RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey),
                                   EventHotKeyID(signature: 0x53515348, id: 1),
                                   GetApplicationEventTarget(), 0, &reference)
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: SearchPanel!
    private let model = SearchModel()
    private let hotkey = GlobalHotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self
        let host = NSHostingView(rootView: SearchView(model: model, openPermissions: openPermissions, showSetup: showSetup,
                                                        chooseDatabase: chooseDatabase, resetDatabase: resetDatabase, quit: quit))
        host.wantsLayer = true
        host.layer?.cornerRadius = 26
        host.layer?.masksToBounds = true
        panel.contentView = host
        model.dismiss = { [weak self] in self?.hide() }
        hotkey.action = { [weak self] in self?.toggle() }
        let status = hotkey.register()
        if status != noErr {
            let alert = NSAlert()
            alert.messageText = "The global shortcut is unavailable"
            alert.informativeText = "Option–Command–N may be used by another app (status \(status)). You can still open search by reopening Safari Quick Search from Finder."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        show()
    }

    private func configureMenu() {
        // Standard Edit actions keep Cmd+A/C/V/X and undo working in the field.
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"),
                                      ("Cut", #selector(NSText.cut(_:)), "x"),
                                      ("Copy", #selector(NSText.copy(_:)), "c"),
                                      ("Paste", #selector(NSText.paste(_:)), "v"),
                                      ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }
    @objc private func toggle() { panel.isVisible ? hide() : show() }
    private func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - 350, y: area.midY - 180))
        }
        panel.makeKeyAndOrderFront(nil)
        if let field = firstTextField(panel.contentView) { panel.makeFirstResponder(field) }
        model.refresh()
    }
    private func firstTextField(_ view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField { return field }
        for child in view.subviews {
            if let result = firstTextField(child) { return result }
        }
        return nil
    }
    private func hide() { panel.orderOut(nil); model.clear() }
    func windowDidResignKey(_ notification: Notification) { hide() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showSetup() {
        hide()
        let alert = NSAlert()
        alert.messageText = "Allow Safari history access"
        alert.informativeText = "In System Settings → Privacy & Security → Full Disk Access, add this Safari Quick Search.app and enable it. Then quit and reopen the app.\n\nFull Disk Access is broad: macOS does not limit it to Safari history. This app uses it only to read your chosen history database. It has no analytics, history uploads, or background indexing. Google receives a query only when you open the Google result.\n\nAllow Automation access to Safari when prompted to switch to an existing tab without reloading it. If access is denied, links open normally. No Accessibility or Input Monitoring permission is needed.\n\nCurrent database:\n\(model.path)"
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openPermissions() }
    }
    private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func chooseDatabase() {
        hide()
        let chooser = NSOpenPanel()
        chooser.title = "Choose a Safari History.db"
        chooser.message = "Choose a Safari profile's History.db or a consistent SQLite backup. Access to protected Safari files may still require Full Disk Access."
        chooser.canChooseDirectories = false
        chooser.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if chooser.runModal() == .OK, let url = chooser.url {
            UserDefaults.standard.set(url.path, forKey: "historyPath")
            show()
        }
    }
    @objc private func resetDatabase() {
        UserDefaults.standard.removeObject(forKey: "historyPath")
        show()
    }
}

@main
struct SafariQuickSearchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
