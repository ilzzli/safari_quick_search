protocol TabSupplierInterface: Sendable {
    func select(_ tab: TabItem) async
    func tabs(matching input: String) async throws -> [TabItem]
}
