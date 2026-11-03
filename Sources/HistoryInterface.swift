protocol HistoryInterface: Sendable {
    func recentEntries(matching input: String) async throws -> [HistoryEntry]
}

/// Runs database queries away from the main actor.
actor SafariHistory: HistoryInterface {
    private let store: HistoryStore

    init(path: String = HistoryStore.defaultPath) {
        store = HistoryStore(path: path)
    }

    func recentEntries(matching input: String) async throws -> [HistoryEntry] {
        let ticket = SearchTicket()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let entries = try store.search(input, ticket: ticket)
            try Task.checkCancellation()
            return entries
        } onCancel: {
            ticket.cancel()
        }
    }
}
