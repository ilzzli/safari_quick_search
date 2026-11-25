import ApplicationServices
import AppKit
import SwiftUI

@MainActor
private enum SafariAXTabGroupSwitcher {
    private static var cachedPID: pid_t = 0
    private static var cachedItems: [String: AXUIElement] = [:]

    static func pressWindowMenuItem(named targetTitle: String) {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            return
        }
        let pid = safari.processIdentifier
        if pid != cachedPID {
            cachedPID = pid
            cachedItems.removeAll()
        }

        if let cached = cachedItems[targetTitle],
           AXUIElementPerformAction(cached, kAXPressAction as CFString) == .success {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return
        }

        if let item = findMenuItem(in: menuBar as! AXUIElement, title: targetTitle, depth: 0) {
            cachedItems[targetTitle] = item
            AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
    }

    private static func findMenuItem(in element: AXUIElement, title: String, depth: Int) -> AXUIElement? {
        guard depth < 5 else { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var itemTitleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &itemTitleRef) == .success,
               let itemTitle = itemTitleRef as? String {
                if itemTitle == title {
                    return child
                }
                // Only descend into the "Window" menu bar item (or submenus inside it)
                if depth == 0 && itemTitle != "Window" {
                    continue
                }
            }
            if let found = findMenuItem(in: child, title: title, depth: depth + 1) {
                return found
            }
        }
        return nil
    }
}

struct PanelLayout: View {
    private static let testTabGroups = ["ooo", "Work", "123"]

    let actions: any AppActionsInterface
    let tabSupplier: any TabSupplierInterface
    let tabGroups: any TabGroupsInterface
    @State private var searchText = ""
    @State private var hoveredTab: TabItem?
    @State private var snapshotID = UUID()
    @State private var profiles: [SafariProfileGroups] = []
    @State private var profilesError: String?
    @State private var currentTabGroupIndex = 0

    private func switchTestTabGroup(offset: Int) {
        let count = Self.testTabGroups.count
        guard count > 0 else { return }
        currentTabGroupIndex = ((currentTabGroupIndex + offset) % count + count) % count
        let groupName = Self.testTabGroups[currentTabGroupIndex]
        SafariAXTabGroupSwitcher.pressWindowMenuItem(named: groupName)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabGroupsSection(
                profiles: profiles,
                errorMessage: profilesError,
                hoveredTab: hoveredTab
            )
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

            TabResults(
                supplier: tabSupplier,
                profiles: profiles,
                input: searchText,
                hoveredTab: $hoveredTab,
                snapshotID: $snapshotID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)

            Divider().opacity(0.45)

            HStack {
                Text("SAFARI QUICK SEARCH " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                Button("<") {
                    switchTestTabGroup(offset: -1)
                }
                .buttonStyle(.glass)
                Button(">") {
                    switchTestTabGroup(offset: 1)
                }
                .buttonStyle(.glass)
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
        .task(id: snapshotID) {
            profilesError = nil
            do {
                let loaded = try await tabGroups.profiles()
                try Task.checkCancellation()
                profiles = loaded
            } catch {
                guard !Task.isCancelled else { return }
                profilesError = error.localizedDescription
            }
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
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .help("Options")
        .accessibilityLabel("Options")
    }
}
