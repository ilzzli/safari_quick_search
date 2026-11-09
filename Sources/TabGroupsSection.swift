import SwiftUI

struct TabGroupsSection: View {
    let provider: any TabGroupsInterface
    let hoveredTab: TabItem?
    private var matches: [SafariTabMatch] {
        hoveredTab?.openTabs ?? []
    }
    @State private var profiles: [SafariProfileGroups] = []
    @State private var errorMessage: String?
    @State private var refreshID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
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
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(profiles) { profile in
                            TabGroupsRow(
                                profile: profile,
                                highlightedGroups: Set(matches.filter {
                                    $0.activeProfileID.map(String.init) == profile.id
                                        && $0.windowID != nil
                                }.map { String($0.groupID) })
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
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
