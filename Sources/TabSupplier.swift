import Foundation

/// Reads Safari history off the main actor and combines it with extra options.
actor TabSupplier: TabSupplierInterface {
    private let store: HistoryStore
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

    /// Keep the best history match first, followed by direct actions.
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
        case .HISTORY:
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
            let history = entries.map {
                TabItem(type: .HISTORY, title: $0.title, subtitle: $0.displayURL, value: $0.url)
            }
            return Self.orderedTabs(
                history: history, input: input, additionalOptions: additionalOptions(input)
            )
        } onCancel: {
            ticket.cancel()
        }
    }
}
