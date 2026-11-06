import SwiftUI

struct PanelLayout: View {
    let actions: any AppActionsInterface
    let tabSupplier: any TabSupplierInterface
    let tabGroups: any TabGroupsInterface
    @State private var searchText = ""
    @State private var hoveredTab: TabItem?

    var body: some View {
        VStack(spacing: 0) {
            TabGroupsSection(provider: tabGroups, hoveredTab: hoveredTab)
                .padding(.horizontal, 24)
                .padding(.top, 18)
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search history, enter a URL, or search Google", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 23))
                    .frame(height: 38)
                    .accessibilityLabel("Search history, enter a URL, or search Google")
                Button(action: actions.hidePanel) {
                    Text("esc")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hide panel")
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            Divider().opacity(0.45)
            TabResults(supplier: tabSupplier, input: searchText, hoveredTab: $hoveredTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.45)
            HStack {
                Text("SAFARI QUICK SEARCH " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                OptionsMenu(actions: actions)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 700, height: 500)
        .modifier(PanelGlassSurface())
    }
}

private struct OptionsMenu: View {
    let actions: any AppActionsInterface
    @State private var launchAtStartupEnabled = false
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Menu {
            Toggle("Launch at Startup", isOn: Binding(
                get: { launchAtStartupEnabled },
                set: { enabled in
                    actions.setLaunchAtStartup(enabled)
                    launchAtStartupEnabled = actions.launchAtStartupEnabled
                }
            ))
            .onAppear {
                launchAtStartupEnabled = actions.launchAtStartupEnabled
            }
            Divider()
            Button("Quit", action: actions.quit)
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .opacity(isHovered ? 0.5 : 0.25)
        .frame(width: 36, height: 24)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? (contrast == .increased ? 0.18 : 0.08) : 0))
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDisappear { isHovered = false }
        .help("Options")
        .accessibilityLabel("Options")
    }
}
