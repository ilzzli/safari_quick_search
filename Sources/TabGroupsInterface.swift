struct SafariTabGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

struct SafariWindowTabGroups: Sendable {
    let windowTitle: String
    let groups: [SafariTabGroup]
    let activeGroupID: String?
}

@MainActor
protocol TabGroupsInterface {
    var currentWindow: SafariWindowTabGroups { get }
}
