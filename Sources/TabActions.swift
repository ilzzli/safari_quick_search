import AppKit

/// Placeholder actions until Safari navigation is connected.
@MainActor
final class TabActions: TabActionInterface {
    private var isLookingUpHistory = false

    func openHistory(_ tab: TabItem) async {
        guard !isLookingUpHistory else { return }
        isLookingUpHistory = true
        defer { isLookingUpHistory = false }
        do {
            let matches = tab.openTabs
            try Task.checkCancellation()
            let details = matches.isEmpty
                ? "No live Safari tab matched this URL in the latest refresh."
                : matches.enumerated().map { index, match in
                    """
                    Match \(index + 1)
                    Tab: \(match.tabID) — \(match.title)
                    URL: \(match.url)
                    Group: \(match.groupID) — \(match.groupName)
                    Database window: \(match.windowID.map(String.init) ?? "Not linked")
                    Safari window ID: \(match.safariWindowID ?? "Unknown")
                    Live tab index: \(match.tabIndex)
                    Window UUID: \(match.windowUUID ?? "Unknown")
                    Window active profile ID: \(match.activeProfileID.map(String.init) ?? "Unknown")
                    Window active profile name: \(match.activeProfileName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed")
                    Active group: \(match.windowID == nil ? "Unknown" : (match.isActiveGroup ? "Yes" : "No"))
                    Selected tab (live): \(match.isActiveTab ? "Yes" : "No")
                    """
                }.joined(separator: "\n\n")
            let alert = NSAlert()
            alert.messageText = "Safari Tab Lookup"
            alert.informativeText = tab.value
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false
            text.isSelectable = true
            text.isVerticallyResizable = true
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.font = .systemFont(ofSize: NSFont.systemFontSize)
            text.string = details
            scroll.documentView = text
            alert.accessoryView = scroll
            alert.window.level = .floating
            alert.runModal()
        } catch {
            guard !Task.isCancelled else { return }
            let alert = NSAlert()
            alert.messageText = "Could Not Read Safari Tabs"
            alert.informativeText = error.localizedDescription
            alert.window.level = .floating
            alert.runModal()
        }
    }

    func search(_ tab: TabItem) {
        showAlert(for: tab)
    }

    func openURL(_ tab: TabItem) {
        guard let url = TabSupplier.navigationURL(tab.value) else {
            presentError(title: "Could Not Open URL in Safari", message: "Invalid HTTP or HTTPS address: \(tab.value)")
            return
        }
        let address = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        with timeout of 3 seconds
            tell application id "com.apple.Safari"
                if (count of windows) > 0 then
                    tell front window
                        set theTab to make new tab
                        set current tab to theTab
                        set URL of theTab to "\(address)"
                    end tell
                else
                    make new document with properties {URL:"\(address)"}
                end if
            end tell
        end timeout
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String ?? "Safari could not load the URL.")
                + "\nAllow this app to control Safari under System Settings → Privacy & Security → Automation."
            presentError(title: "Could Not Open URL in Safari", message: message)
            return
        }
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.activate()
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.window.level = .floating
        alert.runModal()
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
