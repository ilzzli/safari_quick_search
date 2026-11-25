import ApplicationServices
import AppKit

/// Navigates Safari to the selected item:
/// - `.OPENED_TAB`: switches directly to the existing tab in the most upfront matching Safari window
///   (or opens a new tab in the upfront Safari window when Command is held or the tab was closed).
/// - `.HISTORY`, `.URL`, `.SEARCH`: opens a new tab in Safari's frontmost on-screen window
///   (falling back to `front window` or a new Safari window if none is open).
@MainActor
final class SafariTabActions: TabActionInterface {
    private let onComplete: @MainActor () -> Void

    init(onComplete: @escaping @MainActor () -> Void = {}) {
        self.onComplete = onComplete
    }

    func openHistory(_ tab: TabItem) async {
        let forceNewTab = NSEvent.modifierFlags.contains(.command)
        if !forceNewTab, tab.type == .OPENED_TAB, !tab.openTabs.isEmpty {
            let didFocus = await focusBestOpenedTab(from: tab.openTabs)
            if didFocus {
                onComplete()
                return
            }
        }

        guard let url = resolvedURL(from: tab.value) else {
            presentError(
                title: "Could Not Open URL in Safari",
                message: "Invalid HTTP or HTTPS address: \(tab.value)"
            )
            return
        }
        await openInUpfrontSafariWindow(url: url)
    }

    func search(_ tab: TabItem) {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: tab.value)]
        guard let url = components?.url else { return }
        Task { @MainActor in
            await openInUpfrontSafariWindow(url: url)
        }
    }

    func openURL(_ tab: TabItem) {
        guard let url = TabSupplier.navigationURL(tab.value) else {
            presentError(
                title: "Could Not Open URL in Safari",
                message: "Invalid HTTP or HTTPS address: \(tab.value)"
            )
            return
        }
        Task { @MainActor in
            await openInUpfrontSafariWindow(url: url)
        }
    }

    // MARK: - Focus Existing Tab

    private func focusBestOpenedTab(from matches: [SafariTabMatch]) async -> Bool {
        let ranked = rankMatchesByUpfrontWindow(matches)
        for match in ranked {
            guard let rawWindowID = match.safariWindowID,
                  let windowID = Int(rawWindowID),
                  windowID > 0 else {
                continue
            }

            let script = Self.focusTabScript(
                windowID: windowID,
                tabIndex: Int(match.tabIndex),
                url: match.url,
                pageURL: TabStore.pageURL(match.url)
            )
            let result = await Self.executeAppleScript(script)
            if result.output == "ok" {
                activateAndRaiseSafari(windowID: windowID)
                return true
            }
            if let errorMessage = result.errorMessage {
                presentAutomationError(errorMessage)
                return true
            }
        }
        return false
    }

    private func rankMatchesByUpfrontWindow(_ matches: [SafariTabMatch]) -> [SafariTabMatch] {
        let onScreenOrder = Self.onScreenSafariWindowOrder()
        let allOrder = Self.allSafariWindowOrder()

        return matches.sorted { lhs, rhs in
            let lhsID = lhs.safariWindowID.flatMap(Int.init)
            let rhsID = rhs.safariWindowID.flatMap(Int.init)

            let lhsOnScreen = lhsID.flatMap { onScreenOrder[$0] }
            let rhsOnScreen = rhsID.flatMap { onScreenOrder[$0] }
            switch (lhsOnScreen, rhsOnScreen) {
            case let (l?, r?) where l != r:
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }

            let lhsAny = lhsID.flatMap { allOrder[$0] } ?? Int.max
            let rhsAny = rhsID.flatMap { allOrder[$0] } ?? Int.max
            if lhsAny != rhsAny {
                return lhsAny < rhsAny
            }

            if lhs.isActiveTab != rhs.isActiveTab {
                return lhs.isActiveTab
            }

            return lhs.tabIndex < rhs.tabIndex
        }
    }

    // MARK: - Open URL in Upfront Safari Window

    private func openInUpfrontSafariWindow(url: URL) async {
        let preferredWindowID = Self.frontmostOnScreenSafariWindowID() ?? 0
        let script = Self.openURLScript(url: url, preferredWindowID: preferredWindowID)
        let result = await Self.executeAppleScript(script)

        if let errorMessage = result.errorMessage {
            presentAutomationError(errorMessage)
            return
        }

        let targetWindowID = result.output.flatMap(Int.init) ?? preferredWindowID
        activateAndRaiseSafari(windowID: targetWindowID > 0 ? targetWindowID : nil)
        onComplete()
    }

    private func resolvedURL(from raw: String) -> URL? {
        if let direct = URL(string: raw),
           let scheme = direct.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return direct
        }
        return TabSupplier.navigationURL(raw)
    }

    // MARK: - Window Ordering & Activation

    private static func safariPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.processIdentifier
    }

    private static func frontmostOnScreenSafariWindowID() -> Int? {
        onScreenSafariWindowOrder().min(by: { $0.value < $1.value })?.key
    }

    private static func onScreenSafariWindowOrder() -> [Int: Int] {
        safariWindowOrder(options: [.optionOnScreenOnly, .excludeDesktopElements])
    }

    private static func allSafariWindowOrder() -> [Int: Int] {
        safariWindowOrder(options: [.optionAll, .excludeDesktopElements])
    }

    private static func safariWindowOrder(options: CGWindowListOption) -> [Int: Int] {
        guard let pid = safariPID(),
              let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var order: [Int: Int] = [:]
        var rank = 0
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 100,
                  bounds.height > 100 else {
                continue
            }
            if order[windowNumber] == nil {
                order[windowNumber] = rank
                rank += 1
            }
        }
        return order
    }

    private static func windowBounds(for windowID: Int, pid: pid_t) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let number = info[kCGWindowNumber as String] as? Int,
                  number == windowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            return bounds
        }
        return nil
    }

    private func activateAndRaiseSafari(windowID: Int?) {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            return
        }
        safari.activate()

        guard let windowID,
              let targetBounds = Self.windowBounds(for: windowID, pid: safari.processIdentifier) else {
            return
        }
        let appElement = AXUIElementCreateApplication(safari.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return
        }

        for axWindow in axWindows {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let posVal = posRef,
                  let sizeVal = sizeRef,
                  CFGetTypeID(posVal) == AXValueGetTypeID(),
                  CFGetTypeID(sizeVal) == AXValueGetTypeID() else {
                continue
            }
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

            if abs(pos.x - targetBounds.origin.x) <= 2,
               abs(pos.y - targetBounds.origin.y) <= 2,
               abs(size.width - targetBounds.width) <= 2,
               abs(size.height - targetBounds.height) <= 2 {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                break
            }
        }
    }

    // MARK: - AppleScript Execution

    private struct ScriptResult: Sendable {
        let output: String?
        let errorMessage: String?
    }

    private nonisolated static func escapeAppleScriptString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private nonisolated static func focusTabScript(
        windowID: Int,
        tabIndex: Int,
        url: String,
        pageURL: String
    ) -> String {
        let escapedURL = escapeAppleScriptString(url)
        let escapedPage = escapeAppleScriptString(pageURL)
        return """
        with timeout of 3 seconds
            tell application id "com.apple.Safari"
                set targetWindow to missing value
                try
                    set targetWindow to first window whose id is \(windowID)
                end try
                if targetWindow is missing value then
                    return "not_found"
                end if

                set targetTab to missing value
                if \(tabIndex) > 0 then
                    try
                        set candidateTab to tab \(tabIndex) of targetWindow
                        if (URL of candidateTab) is "\(escapedURL)" then
                            set targetTab to candidateTab
                        end if
                    end try
                end if

                if targetTab is missing value then
                    repeat with t in (tabs of targetWindow)
                        try
                            if (URL of t) is "\(escapedURL)" then
                                set targetTab to t
                                exit repeat
                            end if
                        end try
                    end repeat
                end if

                if targetTab is missing value then
                    repeat with t in (tabs of targetWindow)
                        try
                            set u to URL of t
                            if u is "\(escapedPage)" or u starts with "\(escapedPage)?" or u starts with "\(escapedPage)#" then
                                set targetTab to t
                                exit repeat
                            end if
                        end try
                    end repeat
                end if

                if targetTab is missing value then
                    return "not_found"
                end if

                set current tab of targetWindow to targetTab
                set index of targetWindow to 1
                return "ok"
            end tell
        end timeout
        """
    }

    private nonisolated static func openURLScript(url: URL, preferredWindowID: Int) -> String {
        let escapedURL = escapeAppleScriptString(url.absoluteString)
        return """
        with timeout of 3 seconds
            tell application id "com.apple.Safari"
                set targetWindow to missing value
                if \(preferredWindowID) > 0 then
                    try
                        set targetWindow to first window whose id is \(preferredWindowID)
                    end try
                end if
                if targetWindow is missing value and (count of windows) > 0 then
                    set targetWindow to front window
                end if
                if targetWindow is not missing value then
                    tell targetWindow
                        set theTab to make new tab
                        set current tab to theTab
                        set URL of theTab to "\(escapedURL)"
                    end tell
                    set index of targetWindow to 1
                    return (id of targetWindow) as text
                else
                    make new document with properties {URL:"\(escapedURL)"}
                    if (count of windows) > 0 then
                        return (id of front window) as text
                    end if
                    return "0"
                end if
            end tell
        end timeout
        """
    }

    private nonisolated static func executeAppleScript(_ source: String) async -> ScriptResult {
        await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let message = error[NSAppleScript.errorMessage] as? String
                    ?? "Safari could not complete the action."
                return ScriptResult(output: nil, errorMessage: message)
            }
            return ScriptResult(output: descriptor?.stringValue, errorMessage: nil)
        }.value
    }

    // MARK: - Alerts

    private func presentAutomationError(_ message: String) {
        presentError(
            title: "Could Not Open in Safari",
            message: message + "\nAllow this app to control Safari under System Settings → Privacy & Security → Automation."
        )
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.window.level = .floating
        alert.runModal()
    }
}
