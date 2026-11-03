import AppKit

@MainActor
final class HotkeysActionsProvider: HotkeysActionsInterface {
    private let togglePanelAction: @MainActor () -> Void

    /// Without an injected action, hotkeys use a mock suitable for UI development.
    init(togglePanelAction: @escaping @MainActor () -> Void = {
        let alert = NSAlert()
        alert.messageText = "Toggle Panel"
        alert.informativeText = "Mock hotkey action."
        alert.runModal()
    }) {
        self.togglePanelAction = togglePanelAction
    }

    func togglePanel() {
        togglePanelAction()
    }
}
