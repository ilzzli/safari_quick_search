import Foundation

protocol TabSupplierInterface: Sendable {
    func tabs(matching input: String, snapshotID: UUID) async throws -> [TabItem]
    func cachedTabs(matching input: String, snapshotID: UUID) async throws -> [TabItem]
    func select(_ tab: TabItem) async
}
