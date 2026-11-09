import SwiftUI

/// One profile card combines groups from all of its windows.
struct TabGroupsRow: View {
    let profile: SafariProfileGroups
    var highlightedGroups: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(profile.title, systemImage: "person.crop.circle")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(highlightedGroups.isEmpty ? Color.secondary : Color.primary)
            HStack(spacing: 8) {
                if profile.groups.isEmpty {
                    Text("No tab groups").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(profile.groups) { group in
                    let isHighlighted = !group.sourceIDs.isDisjoint(with: highlightedGroups)
                    Label(group.title, systemImage: isHighlighted ? "checkmark.circle.fill" : "rectangle.on.rectangle")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize()
                        .font(.caption)
                        .fontWeight(isHighlighted ? .semibold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            isHighlighted ? Color.yellow.opacity(0.18)
                                : Color.secondary.opacity(0.07),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(isHighlighted ? Color.yellow.opacity(0.65) : Color.secondary.opacity(0.12), lineWidth: 1)
                        }
                        .accessibilityAddTraits(group.isActive ? .isSelected : [])
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(12)
        .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(highlightedGroups.isEmpty ? Color.secondary.opacity(0.12) : Color.yellow.opacity(0.4),
                              lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.title + " tab groups")
    }
}
