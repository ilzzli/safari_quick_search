enum TabType: String, Sendable {
    case HISTORY
    case SEARCH
    case URL
}

/// Presentation data shared by history, search, and direct URL options.
struct TabItem: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let type: TabType
        let value: String
    }

    let type: TabType
    let title: String
    let subtitle: String
    /// Full URL for HISTORY/URL; query text for SEARCH.
    let value: String

    var id: ID {
        ID(type: type, value: type == .HISTORY ? subtitle : value)
    }
}
