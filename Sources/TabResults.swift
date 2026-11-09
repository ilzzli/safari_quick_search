import AppKit
import SwiftUI

/// Owns loading state; TabList only renders the resulting items.
struct TabResults: View {
    let supplier: any TabSupplierInterface
    let input: String
    @Binding var hoveredTab: TabItem?

    private struct Request: Equatable {
        let input: String
        let snapshotID: UUID
    }

    @State private var items: [TabItem] = []
    @State private var isRefreshing = true
    @State private var errorMessage: String?
    @State private var snapshotID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Retry") { snapshotID = UUID() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                Text("No results found.")
                    .foregroundStyle(.secondary)
                    .opacity(isRefreshing ? 0 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabList(items: items, isRefreshing: isRefreshing, hoveredTab: $hoveredTab) { tab in
                    Task { await supplier.select(tab) }
                }
            }
        }
        .task {
            // Refresh only on a hidden-to-visible transition, not when an alert
            // closes or the panel regains keyboard focus.
            let activations = NotificationCenter.default.notifications(
                named: AppActions.panelDidOpenNotification
            ).map { _ in true }
            for await _ in activations {
                guard !Task.isCancelled else { return }
                snapshotID = UUID()
            }
        }
        .task(id: Request(input: input, snapshotID: snapshotID)) {
            hoveredTab = nil
            isRefreshing = true
            errorMessage = nil
            do {
                let cached = try await supplier.cachedTabs(matching: input, snapshotID: snapshotID)
                try Task.checkCancellation()
                items = cached
                let loaded = try await supplier.tabs(matching: input, snapshotID: snapshotID)
                try Task.checkCancellation()
                items = loaded
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }
}
