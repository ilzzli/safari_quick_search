import AppKit
import SwiftUI

struct PanelLayout: View {
    private static let headerControlHeight: CGFloat = 52

    let actions: any AppActionsInterface
    let tabSupplier: any TabSupplierInterface
    let tabGroups: any TabGroupsInterface
    @State private var searchText = ""
    @State private var hoveredTab: TabItem?
    @State private var snapshotID = UUID()
    @State private var profiles: [SafariProfileGroups] = []
    @FocusState private var isSearchFieldFocused: Bool

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
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
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
        .onAppear {
            isSearchFieldFocused = true
        }
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
            // On every hidden-to-visible panel opening: clear previous query, focus input, and refresh.
            let activations = NotificationCenter.default.notifications(
                named: AppActions.panelDidOpenNotification
            ).map { _ in true }
            for await _ in activations {
                guard !Task.isCancelled else { return }
                hoveredTab = nil
                searchText = ""
                snapshotID = UUID()
                isSearchFieldFocused = false
                Task { @MainActor in
                    isSearchFieldFocused = true
                }
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
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search tabs, history, enter a URL, or search Google", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
                .frame(height: 30)
                .focused($isSearchFieldFocused)
                .accessibilityLabel("Search tabs, history, enter a URL, or search Google")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.headerControlHeight)
        .frame(maxWidth: .infinity)
        .modifier(HeaderBubbleGlassSurface(shape: Capsule()))
    }
}

private struct HeaderBubbleGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let rimColor = colorScheme == .dark
            ? Color.white.opacity(contrast == .increased ? 0.30 : 0.16)
            : Color.black.opacity(contrast == .increased ? 0.22 : 0.08)
        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay {
                    shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
        } else {
            content
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                .overlay {
                    shape.strokeBorder(rimColor, lineWidth: 0.75)
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
            Button("Quit", systemImage: "power", action: actions.quit)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
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
