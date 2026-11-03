import AppKit

@MainActor
final class OutsideClickMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(panel: NSPanel, onOutsideClick: @escaping @MainActor () -> Void) {
        stop()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak panel] _ in
            guard let panel, panel.isVisible,
                  !panel.frame.contains(NSEvent.mouseLocation) else { return }
            onOutsideClick()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak panel] event in
            guard let panel, panel.isVisible, event.window !== panel else { return event }
            // Menus are separate windows; selecting a menu item should not dismiss the panel.
            if let window = event.window, window.level >= .popUpMenu {
                return event
            }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                onOutsideClick()
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
