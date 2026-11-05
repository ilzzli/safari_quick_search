struct SafariTabGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
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
