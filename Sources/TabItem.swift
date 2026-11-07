enum TabType: String, Sendable {
    case HISTORY
    case WINDOW
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

    var locationLabel: String? {
        guard !openTabs.isEmpty else { return nil }
        let locations = openTabs.compactMap { tab -> String? in
            guard let windowID = tab.windowID else { return nil }
            let group = ["local", "unnamed", ""].contains(tab.groupName.lowercased())
                ? "Base" : tab.groupName
            return "Window \(windowID) · \(group)"
        }
        let unique = locations.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        let prefix = openTabs.contains(where: \.isPinned) ? "Pinned" : "Open"
        return prefix + " · " + (unique.isEmpty ? "Window unknown" : unique.joined(separator: " / "))
    }

    var id: ID {
        ID(type: type, value: value)
    }
}
