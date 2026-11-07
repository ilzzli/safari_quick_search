import Foundation

/// Reads Safari history off the main actor and combines it with extra options.
actor TabSupplier: TabSupplierInterface {
    private let store: HistoryStore
    private let tabStore = TabStore()
    private let actions: any TabActionInterface
    private let additionalOptions: @Sendable (String) -> [TabItem]

    init(
        actions: any TabActionInterface,
        path: String = HistoryStore.defaultPath,
        additionalOptions: @escaping @Sendable (String) -> [TabItem] = { _ in [] }
    ) {
        self.actions = actions
        store = HistoryStore(path: path)
        self.additionalOptions = additionalOptions
    }

    /// Keep result sections together; direct URL and search actions follow them.
    nonisolated static func orderedTabs(
        history: [TabItem], input: String, additionalOptions: [TabItem] = []
    ) -> [TabItem] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = history
        if !query.isEmpty {
            if let url = navigationURL(query) {
                items.append(TabItem(
                    type: .URL, title: "Open: \(query)",
                    subtitle: url.absoluteString, value: url.absoluteString
                ))
            }
            items.append(TabItem(
                type: .SEARCH, title: "Search: \(query)",
                subtitle: "Search Google", value: query
            ))
        }
        items.append(contentsOf: additionalOptions)
        var seen = Set<TabItem.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// One full-URL row retains every occurrence; opened tabs take precedence.
    nonisolated static func mergeResults(_ items: [TabItem], matching input: String) -> [TabItem] {
        var keys: [String] = []
        var groups: [String: [TabItem]] = [:]
        for item in items {
            let key = TabStore.pageURL(item.value)
            if groups[key] == nil { keys.append(key) }
            groups[key, default: []].append(item)
        }
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var opened: [TabItem] = []
        var history: [TabItem] = []
        for key in keys {
            guard let sources = groups[key],
                  query.isEmpty || sources.contains(where: {
                      $0.title.localizedCaseInsensitiveContains(query)
                          || $0.value.localizedCaseInsensitiveContains(query)
                  }) else { continue }
            let tabs = sources.flatMap(\.openTabs).reduce(into: [SafariTabMatch]()) {
                if !$0.contains($1) { $0.append($1) }
            }
            let records = sources.flatMap(\.historyRecords).reduce(into: [HistoryEntry]()) {
                if !$0.contains($1) { $0.append($1) }
            }
            guard let representative = sources.first(where: { !$0.openTabs.isEmpty }) ?? sources.first else { continue }
            let type: TabType = tabs.isEmpty ? .HISTORY
                : (tabs.contains(where: \.isPinned) ? .PINNED_TAB : .OPENED_TAB)
            let item = TabItem(type: type, title: representative.title,
                               subtitle: representative.subtitle, value: representative.value,
                               openTabs: tabs, historyRecords: records)
            if tabs.isEmpty { history.append(item) } else { opened.append(item) }
        }
        return opened + history.prefix(10)
    }

    nonisolated static func navigationURL(_ input: String) -> URL? {
        guard !input.contains(where: { $0.isWhitespace }) else { return nil }
        let hasScheme = input.contains("://")
        let candidate = hasScheme ? input : "https://" + input
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        // Bare words are searches; domain names, localhost, and explicit web URLs are navigable.
        guard hasScheme || host.contains(".") || host == "localhost" || host.contains(":") else {
            return nil
        }
        return components.url
    }

    func select(_ tab: TabItem) async {
        switch tab.type {
        case .HISTORY, .OPENED_TAB, .PINNED_TAB:
            await actions.openHistory(tab)
        case .SEARCH:
            await actions.search(tab)
        case .URL:
            await actions.openURL(tab)
        }
    }

    func tabs(matching input: String) async throws -> [TabItem] {
        let ticket = SearchTicket()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let entries = try store.search(input, ticket: ticket)
            try Task.checkCancellation()
            let opened = try await tabStore.allTabs()
            try Task.checkCancellation()
            // Base has separate database IDs per window but is one UI group.
            let baseIDs = Dictionary(grouping: opened.filter {
                ["local", "unnamed", ""].contains($0.groupName.lowercased())
            }, by: { $0.activeProfileID ?? -1 }).mapValues {
                $0.map(\.groupID).min() ?? 0
            }
            func groupOrder(_ tab: SafariTabMatch) -> Int64 {
                ["local", "unnamed", ""].contains(tab.groupName.lowercased())
                    ? (baseIDs[tab.activeProfileID ?? -1] ?? tab.groupID) : tab.groupID
            }
            let sorted = opened.sorted {
                let lhs = ($0.activeProfileID ?? -1, groupOrder($0), $0.tabIndex, $0.tabID)
                let rhs = ($1.activeProfileID ?? -1, groupOrder($1), $1.tabIndex, $1.tabID)
                return lhs < rhs
            }
            let mappedTabs = sorted.map {
                TabItem(type: $0.isPinned ? .PINNED_TAB : .OPENED_TAB,
                        title: $0.title.isEmpty ? $0.url : $0.title,
                        subtitle: $0.url, value: $0.url, openTabs: [$0])
            }
            let mappedHistory = entries.map {
                TabItem(type: .HISTORY, title: $0.title, subtitle: $0.displayURL,
                        value: $0.url, historyRecords: [$0])
            }
            let merged = Self.mergeResults(mappedTabs + mappedHistory, matching: input)
            return Self.orderedTabs(
                history: merged, input: input, additionalOptions: additionalOptions(input)
            )
        } onCancel: {
            ticket.cancel()
        }
    }
}
