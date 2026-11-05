@MainActor
protocol TabActionInterface: Sendable {
    func openHistory(_ tab: TabItem) async
    func search(_ tab: TabItem)
    func openURL(_ tab: TabItem)
}
