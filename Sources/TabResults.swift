import SwiftUI

/// Owns loading state; TabList only renders the resulting items.
struct TabResults: View {
    let supplier: any TabSupplierInterface
    let input: String

    private struct Request: Equatable {
        let input: String
        let retryID: Int
    }

    @State private var items: [TabItem] = []
    @State private var isRefreshing = true
    @State private var errorMessage: String?
    @State private var retryID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.headline)

            if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("Retry") { retryID += 1 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                Text("No results found.")
                    .foregroundStyle(.secondary)
                    .opacity(isRefreshing ? 0 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabList(items: items, isRefreshing: isRefreshing) { tab in
                    Task { await supplier.select(tab) }
                }
            }
        }
        .task(id: Request(input: input, retryID: retryID)) {
            isRefreshing = true
            errorMessage = nil
            do {
                let loaded = try await supplier.tabs(matching: input)
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
