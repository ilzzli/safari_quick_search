import AppKit
import Foundation

/// Reads the tabs Safari exposes in its live windows. Safari's scripting dictionary
/// does not expose profile, tab-group, pinned status, or a persistent tab identifier.
actor AppleScriptTabSupplier: TabSupplierInterface {
    private let actions: any TabActionInterface
    private var records: [Record] = []

    init(actions: any TabActionInterface) {
        self.actions = actions
    }

    func tabs(matching input: String) async throws -> [TabItem] {
        try await Task.sleep(for: .milliseconds(250))
        let loaded = try readTabs()
        try Task.checkCancellation()
        records = loaded
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let items = loaded.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.url.localizedCaseInsensitiveContains(query)
        }.filter { seen.insert($0.url).inserted }.prefix(20).map {
            TabItem(type: .HISTORY, title: $0.title.isEmpty ? $0.url : $0.title,
                    subtitle: $0.url, value: $0.url)
        }
        return TabSupplier.orderedTabs(history: items, input: input)
    }

    func select(_ tab: TabItem) async {
        switch tab.type {
        case .HISTORY, .OPENED_TAB, .PINNED_TAB:
            let details = records.filter { $0.url == tab.value }.map(\.details)
                .joined(separator: "\n\n")
            await Self.showResponse(details.isEmpty ? tab.value : details)
        case .SEARCH:
            await actions.search(tab)
        case .URL:
            await actions.openURL(tab)
        }
    }

    struct Record: Sendable {
        let url: String
        let title: String
        let windowID: String
        let windowIndex: Int
        let windowTitle: String
        let tabIndex: Int
        let selected: Bool

        var details: String {
            """
            Title: \(title)
            URL: \(url)
            AppleScript window ID: \(windowID)
            Window index: \(windowIndex)
            Window title: \(windowTitle)
            Tab index: \(tabIndex)
            Selected tab: \(selected ? "Yes" : "No")

            Profile, tab group, and pinned status: not exposed by Safari AppleScript.
            Window IDs here are not SafariTabs.db window IDs.
            """
        }
    }

    // Return typed Apple event lists instead of delimited text so titles and URLs
    // containing newlines, quotes, or tabs can be read without escaping ambiguity.
    private static let source = """
    if application "Safari" is not running then return {}
    set tabRows to {}
    with timeout of 10 seconds
        tell application "/Applications/Safari.app"
            repeat with browserWindow in windows
                set windowID to (id of browserWindow) as text
                set windowIndex to index of browserWindow
                set windowTitle to name of browserWindow
                set selectedIndex to index of current tab of browserWindow
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL is not missing value and tabURL is not "" then
                        set tabTitle to name of browserTab
                        if tabTitle is missing value then set tabTitle to ""
                        set tabIndex to index of browserTab
                        set end of tabRows to {tabURL, tabTitle, windowID, windowIndex, windowTitle, tabIndex, (tabIndex = selectedIndex)}
                    end if
                end repeat
            end repeat
        end tell
    end timeout
    return tabRows
    """

    private func readTabs() throws -> [Record] {
        try Task.checkCancellation()
        guard let script = NSAppleScript(source: Self.source) else {
            throw SafariScriptError.failed("Could not create the tab-reading script.")
        }
        var error: NSDictionary?
        let response = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            if code == -1743 {
                throw SafariScriptError.failed(
                    "Allow Safari Quick Search to control Safari in System Settings → Privacy & Security → Automation."
                )
            }
            throw SafariScriptError.failed(
                error[NSAppleScript.errorMessage] as? String ?? "Safari did not return its tabs."
            )
        }
        return try Self.records(from: response)
    }

    static func records(from response: NSAppleEventDescriptor) throws -> [Record] {
        guard response.descriptorType == typeAEList else {
            throw SafariScriptError.failed("Safari returned an unexpected tab list.")
        }
        guard response.numberOfItems > 0 else { return [] }
        return try (1...response.numberOfItems).map { index in
            guard let row = response.atIndex(index), row.numberOfItems == 7,
                  let url = row.atIndex(1)?.stringValue,
                  let title = row.atIndex(2)?.stringValue,
                  let windowID = row.atIndex(3)?.stringValue,
                  let windowIndex = row.atIndex(4),
                  let windowTitle = row.atIndex(5)?.stringValue,
                  let tabIndex = row.atIndex(6),
                  let selected = row.atIndex(7) else {
                throw SafariScriptError.failed("Safari returned an incomplete tab record.")
            }
            return Record(url: url, title: title, windowID: windowID,
                          windowIndex: Int(windowIndex.int32Value), windowTitle: windowTitle,
                          tabIndex: Int(tabIndex.int32Value), selected: selected.booleanValue)
        }
    }

    @MainActor
    private static func showResponse(_ response: String) {
        let alert = NSAlert()
        alert.messageText = "Safari Live Tab Details"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.string = response
        scroll.documentView = text
        alert.accessoryView = scroll
        alert.window.level = .floating
        alert.runModal()
    }
}

private enum SafariScriptError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return "Could not read Safari tabs. " + message
        }
    }
}
