import SwiftUI

/// One profile card combines groups from all of its windows.
struct TabGroupsRow: View {
    let profile: SafariProfileGroups
    var highlightedGroups: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(highlightedGroups.isEmpty ? Color.secondary : Color.primary)
            HStack(spacing: 8) {
                if profile.groups.isEmpty {
                    Text("No tab groups").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(profile.groups) { group in
                    let isHighlighted = !group.sourceIDs.isDisjoint(with: highlightedGroups)
                    Text(group.title)
                        .font(.caption)
                        .fontWeight(group.isActive ? .semibold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            isHighlighted ? Color.yellow.opacity(0.35)
                                : (group.isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isHighlighted ? Color.yellow
                                    : (group.isActive ? Color.accentColor : .clear), lineWidth: 1)
                        }
                        .accessibilityAddTraits(group.isActive ? .isSelected : [])
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(highlightedGroups.isEmpty ? Color.secondary.opacity(0.25) : Color.yellow,
                              lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.title + " tab groups")
    }
}
