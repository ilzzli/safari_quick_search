import AppKit
import SwiftUI

/// Owns loading state; TabList only renders the resulting items.
struct TabResults: View {
    let supplier: any TabSupplierInterface
    let tabGroups: any TabGroupsInterface
    let input: String
    @Binding var hoveredTab: TabItem?

    private struct Request: Equatable {
        let input: String
        let snapshotID: UUID
    }

    @State private var selectedID: TabItem.ID?
    @State private var items: [TabItem] = []
    @State private var isRefreshing = true
    @State private var errorMessage: String?
    @State private var showAllWindowsInPopup = false
    @Binding var snapshotID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Retry") { snapshotID = UUID() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                Text("No results found.")
                    .foregroundStyle(.secondary)
                    .opacity(isRefreshing ? 0 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabList(
                    items: items,
                    isRefreshing: isRefreshing,
                    selectedID: selectedID,
                    tabGroups: tabGroups,
                    showAllWindowsInPopup: showAllWindowsInPopup,
                    refreshID: snapshotID,
                    hoveredTab: $hoveredTab
                ) { tab in
                    hoveredTab = nil
                    Task { await supplier.select(tab) }
                }
            }
        }
        .background(
            ResultKeyboardHandler(
                onKey: handleKey,
                onOptionTab: {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        showAllWindowsInPopup.toggle()
                    }
                }
            )
        )
        .task {
            // Refresh only on a hidden-to-visible transition, not when an alert
            // closes or the panel regains keyboard focus.
            let activations = NotificationCenter.default.notifications(
                named: AppActions.panelDidOpenNotification
            ).map { _ in true }
            for await _ in activations {
                guard !Task.isCancelled else { return }
                snapshotID = UUID()
            }
        }
        .task(id: Request(input: input, snapshotID: snapshotID)) {
            hoveredTab = nil
            selectedID = nil
            isRefreshing = true
            errorMessage = nil
            do {
                let cached = try await supplier.cachedTabs(matching: input, snapshotID: snapshotID)
                try Task.checkCancellation()
                items = cached
                let loaded = try await supplier.tabs(matching: input, snapshotID: snapshotID)
                try Task.checkCancellation()
                items = loaded
                if !items.contains(where: { $0.id == selectedID }) { selectedID = nil }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }
    private func handleKey(_ code: UInt16, shift: Bool) -> Bool {
        guard !isRefreshing, errorMessage == nil, !items.isEmpty else { return false }
        if code == 48 || code == 125 || code == 126 {
            let backwards = code == 126 || (code == 48 && shift)
            let current = items.firstIndex { $0.id == selectedID }
            let step = backwards ? -1 : 1
            let next = current.map { ($0 + step + items.count) % items.count }
                ?? (backwards ? items.count - 1 : 0)
            selectedID = items[next].id
            return true
        }
        guard code == 36 || code == 76,
              let item = items.first(where: { $0.id == selectedID }) else { return false }
        hoveredTab = nil
        Task { await supplier.select(item) }
        return true
    }

}

/// Scope keyboard handling to the search panel, including its text field editor.
private struct ResultKeyboardHandler: NSViewRepresentable {
    let onKey: (UInt16, Bool) -> Bool
    let onOptionTab: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKey = onKey
        view.onOptionTab = onOptionTab
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.onKey = onKey
        view.onOptionTab = onOptionTab
    }

    static func dismantleNSView(_ view: KeyView, coordinator: ()) {
        view.stop()
    }

    final class KeyView: NSView {
        var onKey: ((UInt16, Bool) -> Bool)?
        var onOptionTab: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window,
                      window.isVisible, window.isKeyWindow, event.window === window,
                      NSApp.modalWindow == nil else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function])
                if event.keyCode == 48 && flags == [.option] {
                    self.onOptionTab?()
                    return nil
                }
                guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      (!event.modifierFlags.contains(.shift) || event.keyCode == 48) else { return event }
                if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() {
                    return event
                }
                return self.onKey?(event.keyCode, event.modifierFlags.contains(.shift)) == true ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
