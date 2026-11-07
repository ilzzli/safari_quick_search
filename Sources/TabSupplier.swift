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
        case .HISTORY, .WINDOW:
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
            let byURL = Dictionary(grouping: opened) { TabStore.pageURL($0.url) }
            let history = entries.prefix(10).map {
                TabItem(type: .HISTORY, title: $0.title, subtitle: $0.displayURL,
                        value: $0.url, openTabs: byURL[TabStore.pageURL($0.url)] ?? [])
            }
            var seen = Set<String>()
            var windowTabs: [TabItem] = []
            let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
            for tab in opened where query.isEmpty
                || tab.title.localizedCaseInsensitiveContains(query)
                || tab.url.localizedCaseInsensitiveContains(query) {
                let key = TabStore.pageURL(tab.url)
                guard seen.insert(key).inserted else { continue }
                windowTabs.append(TabItem(
                    type: .WINDOW, title: tab.title.isEmpty ? tab.url : tab.title,
                    subtitle: tab.url, value: tab.url, openTabs: byURL[key] ?? []
                ))
            }
            return Self.orderedTabs(
                history: windowTabs + history, input: input, additionalOptions: additionalOptions(input)
            )
        } onCancel: {
            ticket.cancel()
        }
    }
}
