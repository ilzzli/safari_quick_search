import SwiftUI

struct PanelLayout: View {
    let actions: any AppActionsInterface
    let tabSupplier: any TabSupplierInterface
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Search Safari history", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search Safari history")
            TabResults(supplier: tabSupplier, input: searchText)
        }
        .padding(24)
        .padding(.bottom, 48)
        .frame(width: 700, height: 500)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        .overlay(alignment: .bottomTrailing) {
            OptionsMenu(actions: actions)
                .padding(16)
        }
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
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 36, height: 24)
        .help("Options")
        .accessibilityLabel("Options")
    }
}
