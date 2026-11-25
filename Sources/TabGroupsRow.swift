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
            HStack(spacing: 6) {
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
                        .foregroundStyle(isHighlighted ? Color.accentColor : .primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            isHighlighted ? Color.accentColor.opacity(0.15)
                                : Color.primary.opacity(0.05),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(isHighlighted ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.10), lineWidth: 0.75)
                        }
                        .accessibilityAddTraits(group.isActive ? .isSelected : [])
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(highlightedGroups.isEmpty ? Color.primary.opacity(0.10) : Color.accentColor.opacity(0.38),
                              lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.title + " tab groups")
    }
}
