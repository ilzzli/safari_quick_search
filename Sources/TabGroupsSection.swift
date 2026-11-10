import SwiftUI

struct TabGroupsSection: View {
    let profiles: [SafariProfileGroups]
    let errorMessage: String?
    let hoveredTab: TabItem?

    private var matches: [SafariTabMatch] {
        hoveredTab?.openTabs ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if profiles.isEmpty {
                Text("No Safari profiles or open windows found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(profiles) { profile in
                            TabGroupsRow(
                                profile: profile,
                                highlightedGroups: Set(
                                    matches.filter {
                                        $0.activeProfileID.map(String.init) == profile.id
                                            && $0.windowID != nil
                                    }.map { String($0.groupID) }
                                )
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
