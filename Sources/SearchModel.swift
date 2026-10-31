import AppKit
import ServiceManagement
import SwiftUI

enum SearchSuggestion: Equatable {
    case history(HistoryEntry)
    case google(String)
    case navigate(URL)

    var title: String {
        switch self {
        case .navigate: return "Navigate to URL"
        case .history(let entry): return entry.title
        case .google(let query): return "Search: \(query)"
        }
    }
    var subtitle: String {
        switch self {
        case .navigate(let url): return url.absoluteString
        case .history(let entry): return entry.displayURL
        case .google: return "Google • opens in Safari"
        }
    }
    var icon: String {
        switch self {
        case .navigate, .history: return "globe"
        case .google: return "magnifyingglass"
        }
    }
    var faviconURL: URL? {
        guard let destination, let host = destination.host,
              ["http", "https"].contains(destination.scheme?.lowercased() ?? "") else { return nil }
        // Never include the visited path, credentials, query or fragment.
        var icon = URLComponents()
        icon.scheme = "https"
        icon.host = host
        if destination.scheme?.lowercased() == "https" { icon.port = destination.port }
        icon.path = "/favicon.ico"
        return icon.url
    }

    var destination: URL? {
        switch self {
        case .navigate(let url): return url
        case .history(let entry): return URL(string: entry.url)
        case .google(let query):
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            return components.url
        }
    }
}

final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var entries: [HistoryEntry] = []
    @Published var selected = 0
    @Published var searching = false
    @Published private(set) var loginItemStatus = SMAppService.mainApp.status
    @Published private(set) var updatingLoginItem = false
    @Published var loginItemError: String?

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !updatingLoginItem else { return }
        updatingLoginItem = true
        Task { @MainActor in
            defer {
                loginItemStatus = SMAppService.mainApp.status
                updatingLoginItem = false
            }
            do {
                if enabled {
                    if SMAppService.mainApp.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    } else if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                        if SMAppService.mainApp.status == .requiresApproval {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                } else {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                loginItemError = error.localizedDescription
            }
        }
    }

    @Published var error: String?
    var dismiss: (() -> Void)?
    private let queue = DispatchQueue(label: "SafariQuickSearch.history", qos: .userInitiated)
    private var ticket: SearchTicket?
    private var generation = 0
    private let historyPath: String?
    init(historyPath: String? = nil) { self.historyPath = historyPath }
    var path: String {
        historyPath ?? UserDefaults.standard.string(forKey: "historyPath") ?? HistoryStore.defaultPath
    }
    var hasGoogle: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var suggestions: [SearchSuggestion] {
        var rows = entries.map(SearchSuggestion.history)
        if hasGoogle { rows.insert(.google(query), at: min(1, rows.count)) }
        if let url = Self.navigationURL(for: query) { rows.insert(.navigate(url), at: 0) }
        return rows
    }
    var rowCount: Int { suggestions.count }

    // Only treat the entire input as an address; ordinary phrases remain searches.
    static func navigationURL(for input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let hasWebScheme = value.lowercased().hasPrefix("https://") || value.lowercased().hasPrefix("http://")
        let candidate = hasWebScheme ? value : "https://" + value
        guard let components = URLComponents(string: candidate),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        if let port = components.port, !(1...65535).contains(port) { return nil }
        if !hasWebScheme {
            // Require an address-like host before adding HTTPS to avoid navigating search words.
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard host == "localhost" || (labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }) else { return nil }
            guard !value.contains("://"), !value.contains("@") else { return nil }
        }
        return url
    }


    func refresh() {
        loginItemStatus = SMAppService.mainApp.status
        ticket?.cancel()
        generation += 1
        let current = generation
        let next = SearchTicket()
        ticket = next
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let store = HistoryStore(path: path)
        entries = [] // Never allow Return to open a result for an older query.
        selected = 0
        error = nil
        searching = true
        queue.async { [weak self] in
            let result = Result { try store.search(phrase, ticket: next) }
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.searching = false
                switch result {
                case .success(let rows): self.entries = rows
                case .failure(let failure): self.error = failure.localizedDescription
                }
                self.selected = 0
            }
        }
    }

    func clear() {
        ticket?.cancel()
        generation += 1
        query = ""
        entries = []
        error = nil
        searching = false
    }

    func move(_ delta: Int) {
        guard rowCount > 0 else { return }
        selected = (selected + delta + rowCount) % rowCount
    }

    // Selecting a tab never assigns its URL, so Safari keeps the loaded page and state.
    static func focusExistingSafariTab(for url: URL) -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty else {
            return false
        }
        // Escape the URL as data, never as executable AppleScript.
        let address = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        with timeout of 3 seconds
            tell application id "com.apple.Safari"
                repeat with browserWindow in windows
                    repeat with tabNumber from 1 to count of tabs of browserWindow
                        considering case
                            set matchesURL to (URL of tab tabNumber of browserWindow is "\(address)")
                        end considering
                        if matchesURL then
                            set current tab of browserWindow to tab tabNumber of browserWindow
                            set miniaturized of browserWindow to false
                            set index of browserWindow to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return false
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var scriptError: NSDictionary?
        let result = script.executeAndReturnError(&scriptError)
        return scriptError == nil && result.booleanValue
    }

    func openSelection() {
        guard selected >= 0, selected < rowCount else { return }
        let destination = suggestions[selected].destination
        guard let destination, let scheme = destination.scheme?.lowercased(),
              ["http", "https"].contains(scheme), destination.host != nil else {
            error = "This suggestion is not a valid HTTP or HTTPS address."
            return
        }
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            error = "Safari could not be found on this Mac."
            return
        }
        if Self.focusExistingSafariTab(for: destination) {
            dismiss?()
            return
        }
        NSWorkspace.shared.open([destination], withApplicationAt: safari,
                                configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, failure in
            DispatchQueue.main.async {
                guard let self else { return }
                if let failure { self.error = "Could not open Safari: \(failure.localizedDescription)" }
                else { self.dismiss?() }
            }
        }
    }
}
