struct MockTabGroups: TabGroupsInterface {
    func profiles() async throws -> [SafariProfileGroups] {
        [SafariProfileGroups(id: "personal", title: "Personal", windows: [
            SafariWindowTabGroups(
                id: "mock-window", windowTitle: "Window 1",
                groups: [
                    SafariTabGroup(id: "default", title: "Default"),
                    SafariTabGroup(id: "work", title: "Work")
                ],
                activeGroupID: "work"
            )
        ])]
    }
}
