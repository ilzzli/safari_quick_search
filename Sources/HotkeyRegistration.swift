import AppKit
import Carbon

@MainActor
final class HotkeyRegistration: NSObject {
    private let actions: any HotkeysActionsInterface
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private weak var trackingMenu: NSMenu?
    private var menuKeyMonitor: Any?
    private var menuShortcutPressed = false

    init(actions: any HotkeysActionsInterface) {
        self.actions = actions
        super.init()
    }

    func start() {
        stop()
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuBeganTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuEndedTracking(_:)),
            name: NSMenu.didEndTrackingNotification, object: nil
        )
        // Handle release so holding the shortcut cannot repeatedly toggle the panel.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &identifier
                )
                guard status == noErr,
                      identifier.signature == HotkeyConfig.panelID.signature,
                      identifier.id == HotkeyConfig.panelID.id else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon dispatches application event handlers on the main thread.
                MainActor.assumeIsolated {
                    let registration = Unmanaged<HotkeyRegistration>
                        .fromOpaque(context).takeUnretainedValue()
                    registration.trackingMenu?.cancelTrackingWithoutAnimation()
                    registration.actions.togglePanel()
                }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard handlerStatus == noErr else {
            stop()
            showRegistrationError(handlerStatus)
            return
        }
        registerGlobalHotkey()
    }

    private func registerGlobalHotkey() {
        guard hotkey == nil, handler != nil else { return }
        let status = RegisterEventHotKey(
            HotkeyConfig.panelKeyCode, HotkeyConfig.panelModifiers,
            HotkeyConfig.panelID, GetEventDispatcherTarget(), 0, &hotkey
        )
        if status != noErr {
            stop()
            showRegistrationError(status)
        }
    }

    private func unregisterGlobalHotkey() {
        if let hotkey {
            UnregisterEventHotKey(hotkey)
            self.hotkey = nil
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        trackingMenu = nil
        stopMenuKeyMonitor()
        unregisterGlobalHotkey()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    @objc private func menuBeganTracking(_ notification: Notification) {
        guard trackingMenu == nil, let menu = notification.object as? NSMenu else { return }
        trackingMenu = menu
        // Carbon hotkeys queue during menu tracking. Only the local handler owns
        // the shortcut until this menu closes, preventing deferred duplicate actions.
        unregisterGlobalHotkey()
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self,
                  event.keyCode == UInt16(HotkeyConfig.panelKeyCode) else { return event }
            if event.type == .keyDown {
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function]) == HotkeyConfig.panelEventModifiers
                else { return event }
                self.menuShortcutPressed = true
                return nil
            }
            guard self.menuShortcutPressed else { return event }
            self.menuShortcutPressed = false
            self.trackingMenu?.cancelTrackingWithoutAnimation()
            self.actions.togglePanel()
            return nil
        }
    }

    @objc private func menuEndedTracking(_ notification: Notification) {
        if let menu = notification.object as? NSMenu, trackingMenu === menu {
            trackingMenu = nil
            stopMenuKeyMonitor()
            registerGlobalHotkey()
        }
    }

    private func stopMenuKeyMonitor() {
        if let menuKeyMonitor {
            NSEvent.removeMonitor(menuKeyMonitor)
            self.menuKeyMonitor = nil
        }
        menuShortcutPressed = false
    }

    private func showRegistrationError(_ status: OSStatus) {
        let alert = NSAlert()
        alert.messageText = "Could Not Register Panel Shortcut"
        alert.informativeText = "The shortcut may be in use by another app. Error: \(status)."
        alert.runModal()
    }
}
