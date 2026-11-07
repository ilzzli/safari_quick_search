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

    /// Merge window-local Base groups; shared named groups retain their database identity.
    var groups: [SafariProfileTabGroup] {
        var result: [SafariProfileTabGroup] = []
        for window in windows {
            for group in window.groups {
                let key = ["local", "unnamed", ""].contains(group.title.lowercased())
                    ? "base" : "group:" + group.id
                if let index = result.firstIndex(where: { $0.id == key }) {
                    result[index].sourceIDs.insert(group.id)
                    result[index].isActive = result[index].isActive || group.id == window.activeGroupID
                } else {
                    result.append(SafariProfileTabGroup(
                        id: key, title: group.displayTitle, sourceIDs: [group.id],
                        isActive: group.id == window.activeGroupID
                    ))
                }
            }
        }
        return result.filter { $0.id == "base" } + result.filter { $0.id != "base" }
    }
}

struct SafariProfileTabGroup: Identifiable, Sendable {
    let id: String
    let title: String
    var sourceIDs: Set<String>
    var isActive: Bool
}

protocol TabGroupsInterface: Sendable {
    func profiles() async throws -> [SafariProfileGroups]
}
