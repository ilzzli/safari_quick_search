struct SafariTabGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String

    var displayTitle: String {
        ["local", "unnamed", ""].contains(title.lowercased()) ? "Base" : title
    }
}

struct SafariWindowTabGroups: Identifiable, Sendable {
    let id: String
    let windowTitle: String
    let groups: [SafariTabGroup]
    let activeGroupID: String?
}

struct SafariProfileGroups: Identifiable, Sendable {
    let id: String
    let title: String
    let windows: [SafariWindowTabGroups]
}

protocol TabGroupsInterface: Sendable {
    func profiles() async throws -> [SafariProfileGroups]
}
