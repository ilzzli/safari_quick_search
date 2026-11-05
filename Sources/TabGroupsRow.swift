import SwiftUI

struct TabGroupsRow: View {
    let window: SafariWindowTabGroups

    var body: some View {
        HStack(spacing: 12) {
            Label(window.windowTitle, systemImage: "safari")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(window.groups) { group in
                        let isActive = group.id == window.activeGroupID
                        Text(group.title)
                            .font(.caption)
                            .fontWeight(isActive ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 1)
                            }
                            .accessibilityAddTraits(isActive ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Safari window tab groups")
    }
}
