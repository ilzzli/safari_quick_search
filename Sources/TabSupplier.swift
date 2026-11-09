import Foundation

/// Reads Safari history off the main actor and combines it with extra options.
actor TabSupplier: TabSupplierInterface {
    private var cachedHistory: [HistoryEntry] = []
    private var snapshotID: UUID?
    private var snapshotTask: Task<[SafariTabMatch], Error>?
    private let defaultSnapshotID = UUID()
    private let store: HistoryStore
    private let liveTabs: LiveTabStore
    private let actions: any TabActionInterface
    private let additionalOptions: @Sendable (String) -> [TabItem]

    init(
        actions: any TabActionInterface,
        path: String = HistoryStore.defaultPath,
        additionalOptions: @escaping @Sendable (String) -> [TabItem] = { _ in [] }
    ) {
        self.actions = actions
        liveTabs = LiveTabStore(actions: actions)
        store = HistoryStore(path: path)
        self.additionalOptions = additionalOptions
    }

    /// Keep the top match first, followed by actions, then remaining matches.
    nonisolated static func orderedTabs(
        history: [TabItem], input: String, additionalOptions: [TabItem] = []
    ) -> [TabItem] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = Array(history.prefix(1))
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
        items.append(contentsOf: history.dropFirst())
        items.append(contentsOf: additionalOptions)
        var seen = Set<TabItem.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// AppleScript-selected tabs first, then numeric Safari window ID and tab index.
    nonisolated static func currentTabPrecedes(_ lhs: SafariTabMatch, _ rhs: SafariTabMatch) -> Bool {
        if lhs.isActiveTab != rhs.isActiveTab { return lhs.isActiveTab }
        let lhsWindowID = lhs.safariWindowID.flatMap { Int64($0) } ?? Int64.max
        let rhsWindowID = rhs.safariWindowID.flatMap { Int64($0) } ?? Int64.max
        return (lhsWindowID, lhs.tabIndex, lhs.tabID)
            < (rhsWindowID, rhs.tabIndex, rhs.tabID)
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
                : .OPENED_TAB
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
        case .HISTORY, .OPENED_TAB:
            await actions.openHistory(tab)
        case .SEARCH:
            await actions.search(tab)
        case .URL:
            await actions.openURL(tab)
        }
    }

    func tabs(matching input: String) async throws -> [TabItem] {
        try await tabs(matching: input, snapshotID: defaultSnapshotID)
    }

    private func snapshot(for id: UUID) async throws -> [SafariTabMatch] {
        if snapshotID != id || snapshotTask == nil {
            snapshotID = id
            cachedHistory = []
            snapshotTask = Task { [liveTabs] in try await liveTabs.tabs() }
        }
        guard let task = snapshotTask else { return [] }
        let opened = try await task.value
        try Task.checkCancellation()
        return opened
    }

    func cachedTabs(matching input: String, snapshotID: UUID) async throws -> [TabItem] {
        let opened = try await snapshot(for: snapshotID)
        return results(opened: opened, entries: cachedHistory, input: input)
    }

    func tabs(matching input: String, snapshotID: UUID) async throws -> [TabItem] {
        let opened = try await snapshot(for: snapshotID)
        // Only the database query is debounced; cached results are already visible.
        try await Task.sleep(for: .milliseconds(200))
        let ticket = SearchTicket()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let entries = try store.search(input, ticket: ticket)
            try Task.checkCancellation()
            cachedHistory = entries
            return results(opened: opened, entries: entries, input: input)
        } onCancel: {
            ticket.cancel()
        }
    }

    private func results(opened: [SafariTabMatch], entries: [HistoryEntry], input: String) -> [TabItem] {
        let sorted = opened.sorted(by: Self.currentTabPrecedes)
        let mappedTabs = sorted.map {
            TabItem(type: .OPENED_TAB,
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
        ).map { item in
            guard item.type == .URL else { return item }
            var item = item
            item.openTabs = opened.filter { TabStore.pageURL($0.url) == TabStore.pageURL(item.value) }
            return item
        }
    }
}
