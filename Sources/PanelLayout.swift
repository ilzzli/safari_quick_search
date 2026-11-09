import SwiftUI

struct PanelLayout: View {
    let actions: any AppActionsInterface
    let tabSupplier: any TabSupplierInterface
    let tabGroups: any TabGroupsInterface
    @State private var searchText = ""
    @State private var hoveredTab: TabItem?
    @State private var snapshotID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            TabGroupsSection(provider: tabGroups, hoveredTab: hoveredTab, refreshID: snapshotID)
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
            TabResults(supplier: tabSupplier, tabGroups: tabGroups, input: searchText, hoveredTab: $hoveredTab, snapshotID: $snapshotID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)
            Divider().opacity(0.45)
            HStack {
                Text("SAFARI QUICK SEARCH " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    hoveredTab = nil
                    snapshotID = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .help("Refresh Safari tabs and groups")
                .accessibilityLabel("Refresh Safari tabs and groups")
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
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .help("Options")
        .accessibilityLabel("Options")
    }
}
