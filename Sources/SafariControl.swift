import AppKit

@MainActor
final class SafariControl {
    var isFocused: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari"
    }

    func previousTabGroup() {
        switchTabGroup(menuItem: "Go To Previous Tab Group")
    }

    func nextTabGroup() {
        switchTabGroup(menuItem: "Go To Next Tab Group")
    }

    private func switchTabGroup(menuItem: String) {
        guard isFocused else {
            SwipeLogger.debug("Skipped tab group switch: Safari lost focus")
            return
        }
        SwipeLogger.debug("Executing Safari command: " + menuItem)
        let source = """
        tell application "System Events"
            tell process "Safari"
                if frontmost then
                    click menu item "\(menuItem)" of menu "Window" of menu bar 1
                end if
            end tell
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            SwipeLogger.debug("Safari command failed: " + error.description)
            let alert = NSAlert()
            alert.messageText = "Could Not Switch Safari Tab Group"
            alert.informativeText = (error[NSAppleScript.errorMessage] as? String ?? "Safari’s tab group command is unavailable.")
                + "\nAllow this app to control System Events under Automation and grant Accessibility (Device Control and Data Access)."
            alert.runModal()
        }
    }
}
