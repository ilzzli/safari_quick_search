@MainActor
protocol TabActionInterface: Sendable {
    func openHistory(_ tab: TabItem)
    func search(_ tab: TabItem)
    func openURL(_ tab: TabItem)
}
