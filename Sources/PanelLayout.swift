import AppKit
import SwiftUI

struct PanelLayout: View {
    private static let headerControlHeight: CGFloat = 56

    let actions: any AppActionsInterface
    let tabSupplier: any TabSupplierInterface
    let tabGroups: any TabGroupsInterface
    @State private var searchText = ""
    @State private var hoveredTab: TabItem?
    @State private var snapshotID = UUID()
    @State private var profiles: [SafariProfileGroups] = []

    var body: some View {
        TabResults(
            supplier: tabSupplier,
            profiles: profiles,
            input: searchText,
            hoveredTab: $hoveredTab,
            snapshotID: $snapshotID
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaBar(edge: .top, spacing: 0) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    searchBubble
                    OptionsMenu(actions: actions) {
                        hoveredTab = nil
                        snapshotID = UUID()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .background {
            Button("", action: actions.hidePanel)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: 700, height: 500)
        .modifier(PanelGlassSurface())
        .task(id: snapshotID) {
            do {
                let loaded = try await tabGroups.profiles()
                try Task.checkCancellation()
                profiles = loaded
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
        .task {
            let switches = NotificationCenter.default.notifications(
                named: .safariTabGroupDidSwitch
            ).map { _ in true }
            for await _ in switches {
                guard !Task.isCancelled else { return }
                guard actions.isPanelVisible else { continue }
                hoveredTab = nil
                snapshotID = UUID()
            }
        }
    }

    private var searchBubble: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search history, enter a URL, or search Google", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .frame(height: 32)
                .accessibilityLabel("Search history, enter a URL, or search Google")
        }
        .padding(.horizontal, 18)
        .frame(height: Self.headerControlHeight)
        .frame(maxWidth: .infinity)
        .modifier(HeaderBubbleGlassSurface(shape: Capsule()))
    }
}

private struct HeaderBubbleGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                }
        } else {
            content
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.20), lineWidth: 0.75)
                }
        }
    }
}

private struct OptionsMenu: View {
    let actions: any AppActionsInterface
    let onRefresh: () -> Void
    @State private var launchAtStartupEnabled = false

    var body: some View {
        Menu {
            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
            Divider()
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
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .modifier(HeaderBubbleGlassSurface(shape: Circle(), interactive: true))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Options")
        .accessibilityLabel("Options")
    }
}
