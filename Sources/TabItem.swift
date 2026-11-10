enum TabType: String, Sendable {
    case HISTORY
    case OPENED_TAB
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
    var openTabs: [SafariTabMatch] = []
    var historyRecords: [HistoryEntry] = []

    var locationLabel: String? {
        guard !openTabs.isEmpty else { return nil }
        let locations = openTabs.compactMap { tab -> String? in
            guard tab.windowID != nil else { return nil }
            let group = SafariTabGroup.normalizedTitle(tab.groupName)
            let profile = SafariTabGroup.normalizedProfileName(tab.activeProfileName)
            return "\(profile) · \(group)"
        }
        var seen = Set<String>()
        let unique = locations.filter { seen.insert($0).inserted }
        return "Open · " + (unique.isEmpty ? "Window unknown" : unique.joined(separator: " / "))
    }

    var id: ID {
        ID(type: type, value: value)
    }
}
