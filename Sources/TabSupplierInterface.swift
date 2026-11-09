import Foundation

protocol TabSupplierInterface: Sendable {
    func tabs(matching input: String, snapshotID: UUID) async throws -> [TabItem]
    func cachedTabs(matching input: String, snapshotID: UUID) async throws -> [TabItem]
    func select(_ tab: TabItem) async
    func tabs(matching input: String) async throws -> [TabItem]
}

extension TabSupplierInterface {
    func cachedTabs(matching input: String, snapshotID: UUID) async throws -> [TabItem] {
        TabSupplier.orderedTabs(history: [], input: input)
    }

    func tabs(matching input: String, snapshotID: UUID) async throws -> [TabItem] {
        try await tabs(matching: input)
    }
}
