import SwiftUI

struct TabGroupsRow: View {
    let window: SafariWindowTabGroups
    var highlightedGroups: Set<String> = []

    var body: some View {
        HStack(spacing: 12) {
            Label(window.windowTitle, systemImage: "safari")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(4)
                .background(highlightedGroups.isEmpty ? Color.clear : Color.yellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(window.groups) { group in
                        let isActive = group.id == window.activeGroupID
                        let isHighlighted = highlightedGroups.contains(group.id)
                        Text(group.displayTitle)
                            .font(.caption)
                            .fontWeight(isActive ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isHighlighted ? Color.yellow.opacity(0.35) : (isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08)),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(isHighlighted ? Color.yellow : (isActive ? Color.accentColor : .clear), lineWidth: 1)
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
