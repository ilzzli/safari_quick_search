import AppKit

/// Placeholder actions until Safari navigation is connected.
@MainActor
final class TabActions: TabActionInterface {
    func openHistory(_ tab: TabItem) {
        showAlert(for: tab)
    }

    func search(_ tab: TabItem) {
        showAlert(for: tab)
    }

    func openURL(_ tab: TabItem) {
        showAlert(for: tab)
    }

    private func showAlert(for tab: TabItem) {
        let alert = NSAlert()
        alert.messageText = "Tab Action: " + tab.type.rawValue
        alert.informativeText = [
            "Title: " + tab.title,
            "Subtitle: " + tab.subtitle,
            "Value: " + tab.value
        ].joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        alert.runModal()
    }
}
