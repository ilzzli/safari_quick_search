import SwiftUI

struct HistoryList: View {
    let history: any HistoryInterface
    let input: String

    private struct Request: Equatable {
        let input: String
        let reloadID: Int
    }

    @State private var entries: [HistoryEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reloadID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Safari History")
                .font(.headline)

            if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("Retry") { reloadID += 1 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                Text(input.isEmpty ? "No Safari history found." : "No matching history found.")
                    .opacity(isLoading ? 0 : 1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .lineLimit(1)
                                Text(entry.displayURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(entry.url)
                        }
                    }
                }
            }
        }
        .opacity(isLoading ? 0.55 : 1)
        .disabled(isLoading)
        .scrollDisabled(isLoading)
        .task(id: Request(input: input, reloadID: reloadID)) {
            isLoading = true
            errorMessage = nil
            do {
                let loaded = try await history.recentEntries(matching: input)
                try Task.checkCancellation()
                entries = loaded
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
