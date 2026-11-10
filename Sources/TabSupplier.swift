import Foundation

actor TabSupplier: TabSupplierInterface {
    private let actions: any TabActionInterface
    private let historyStore = HistoryStore(path: HistoryStore.defaultPath)
    private let tabStore = LiveTabStore()
    private var activeTicket: SearchTicket?
    private var openSnapshotID: UUID?
    private var openSnapshot: [SafariTabMatch]?

    init(actions: any TabActionInterface) {
        self.actions = actions
    }

    func cachedTabs(matching input: String, snapshotID: UUID) async throws -> [TabItem] {
        let openTabs = openSnapshotID == snapshotID ? (openSnapshot ?? []) : []
        return Self.orderedTabs(history: [], openTabs: openTabs, input: input)
    }

    func tabs(matching input: String, snapshotID: UUID) async throws -> [TabItem] {
        activeTicket?.cancel()
        if !input.isEmpty {
            try await Task.sleep(for: .milliseconds(250))
        }
        let openTabs = try await loadedOpenTabs(snapshotID: snapshotID)
        let ticket = SearchTicket()
        activeTicket = ticket
        defer { if activeTicket === ticket { activeTicket = nil } }
        let phrase = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let store = historyStore
        let entries = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try store.search(phrase, ticket: ticket)
        } onCancel: {
            ticket.cancel()
        }
        return Self.orderedTabs(history: entries, openTabs: openTabs, input: input)
    }

    private func loadedOpenTabs(snapshotID: UUID) async throws -> [SafariTabMatch] {
        if openSnapshotID == snapshotID, let openSnapshot {
            return openSnapshot
        }
        let loaded = try await tabStore.tabs()
        openSnapshotID = snapshotID
        openSnapshot = loaded
        return loaded
    }

    nonisolated static func orderedTabs(
        history: [HistoryEntry],
        openTabs: [SafariTabMatch] = [],
        input: String
    ) -> [TabItem] {
        let phrase = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let openByURL = Dictionary(grouping: openTabs) { TabStore.pageURL($0.url) }
        var seenOpenURLs = Set<String>()
        var openItems: [TabItem] = []
        for tab in openTabs {
            guard phrase.isEmpty || tab.title.localizedCaseInsensitiveContains(phrase)
                || tab.url.localizedCaseInsensitiveContains(phrase) else { continue }
            let key = TabStore.pageURL(tab.url)
            guard seenOpenURLs.insert(key).inserted else { continue }
            let matches = openByURL[key] ?? [tab]
            let historyMatches = history.filter { TabStore.pageURL($0.url) == key }
            let title = matches.first(where: { !$0.title.isEmpty })?.title
                ?? historyMatches.first?.title ?? tab.url
            openItems.append(
                TabItem(
                    type: .OPENED_TAB,
                    title: title,
                    subtitle: displayURL(tab.url),
                    value: tab.url,
                    openTabs: matches,
                    historyRecords: historyMatches
                )
            )
        }
        let historyItems = history.compactMap { entry -> TabItem? in
            guard openByURL[TabStore.pageURL(entry.url)] == nil else { return nil }
            return TabItem(
                type: .HISTORY,
                title: entry.title,
                subtitle: entry.displayURL,
                value: entry.url,
                historyRecords: [entry]
            )
        }
        var results = Array((openItems + historyItems).prefix(20))
        if !phrase.isEmpty {
            results.insert(
                TabItem(
                    type: .SEARCH,
                    title: "Search: \(phrase)",
                    subtitle: "Google • opens in Safari",
                    value: phrase
                ),
                at: min(1, results.count)
            )
        }
        if let url = navigationURL(phrase) {
            results.insert(
                TabItem(
                    type: .URL,
                    title: "Navigate to URL",
                    subtitle: url.absoluteString,
                    value: url.absoluteString
                ),
                at: 0
            )
        }
        return results
    }

    private nonisolated static func displayURL(_ url: String) -> String {
        String(url.prefix { $0 != "?" && $0 != "#" })
    }

    func select(_ tab: TabItem) async {
        switch tab.type {
        case .HISTORY, .OPENED_TAB:
            await actions.openHistory(tab)
        case .SEARCH:
            await actions.search(tab)
        case .URL:
            await actions.openURL(tab)
        }
    }

    /// Only treat the entire input as an address; ordinary phrases remain searches.
    nonisolated static func navigationURL(_ input: String) -> URL? {
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
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard host == "localhost" || (labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }) else { return nil }
            guard !value.contains("://"), !value.contains("@") else { return nil }
        }
        return url
    }
}
