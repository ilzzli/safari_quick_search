import SwiftUI

struct TabGroupsSection: View {
    let provider: any TabGroupsInterface
    @State private var profiles: [SafariProfileGroups] = []
    @State private var errorMessage: String?
    @State private var refreshID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Safari profiles · open windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { refreshID += 1 } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh Safari tab groups")
                .accessibilityLabel("Refresh Safari tab groups")
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if profiles.isEmpty {
                Text("No Safari profiles or open windows found.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(profiles) { profile in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.title).font(.caption.weight(.semibold))
                                if profile.windows.isEmpty {
                                    Text("No open windows").font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(profile.windows) { window in
                                    TabGroupsRow(window: window)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .task(id: refreshID) {
            // Refresh while displayed so Safari tab-group changes are reflected.
            while !Task.isCancelled {
                do {
                    let loaded = try await provider.profiles()
                    try Task.checkCancellation()
                    profiles = loaded
                    errorMessage = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                    return
                }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
    }
}
