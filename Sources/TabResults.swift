import AppKit
import Carbon
import SwiftUI

/// Owns loading state; TabList only renders the resulting items.
struct TabResults: View {
    let supplier: any TabSupplierInterface
    let profiles: [SafariProfileGroups]
    let input: String
    @Binding var hoveredTab: TabItem?
    @Binding var snapshotID: UUID

    private struct Request: Equatable {
        let input: String
        let snapshotID: UUID
    }

    @State private var selectedID: TabItem.ID?
    @State private var items: [TabItem] = []
    @State private var isRefreshing = true
    @State private var hasCurrentInputItems = false
    @State private var userMovedSelection = false
    @State private var errorMessage: String?
    @State private var showAllWindowsInPopup = false
    @State private var lastLoadedSnapshotID: UUID?

    var body: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                    Button("Retry") { snapshotID = UUID() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("No Matching Results")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Try a different title, address, or search phrase.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(isRefreshing ? 0 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabList(
                    items: items,
                    isRefreshing: isRefreshing,
                    selectedID: selectedID,
                    allProfiles: profiles,
                    showAllWindowsInPopup: showAllWindowsInPopup,
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
        .task(id: Request(input: input, snapshotID: snapshotID)) {
            let hasInput = !input.isEmpty
            hoveredTab = nil
            if !hasInput {
                selectedID = nil
            }
            userMovedSelection = false
            hasCurrentInputItems = false
            isRefreshing = true
            errorMessage = nil
            let isSameSnapshot = lastLoadedSnapshotID == snapshotID
            do {
                if isSameSnapshot {
                    let cached = try await supplier.cachedTabs(matching: input, snapshotID: snapshotID)
                    try Task.checkCancellation()
                    items = cached
                    selectedID = hasInput ? cached.first?.id : nil
                    hasCurrentInputItems = true
                } else {
                    selectedID = nil
                }
                let loaded = try await supplier.tabs(matching: input, snapshotID: snapshotID)
                try Task.checkCancellation()
                items = loaded
                lastLoadedSnapshotID = snapshotID
                if userMovedSelection, items.contains(where: { $0.id == selectedID }) {
                    // Keep the row explicitly selected via keyboard while results refreshed.
                } else {
                    selectedID = hasInput ? loaded.first?.id : nil
                }
                hasCurrentInputItems = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    private func handleKey(_ code: UInt16, shift: Bool) -> Bool {
        guard hasCurrentInputItems, errorMessage == nil, !items.isEmpty else { return false }
        let isTab = code == UInt16(kVK_Tab)
        let isDownArrow = code == UInt16(kVK_DownArrow)
        let isUpArrow = code == UInt16(kVK_UpArrow)
        if isTab || isDownArrow || isUpArrow {
            let backwards = isUpArrow || (isTab && shift)
            let current = items.firstIndex { $0.id == selectedID }
            let step = backwards ? -1 : 1
            let next = current.map { ($0 + step + items.count) % items.count }
                ?? (backwards ? items.count - 1 : 0)
            userMovedSelection = true
            selectedID = items[next].id
            return true
        }
        let isReturn = code == UInt16(kVK_Return) || code == UInt16(kVK_ANSI_KeypadEnter)
        guard isReturn, let item = items.first(where: { $0.id == selectedID }) else { return false }
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
                if event.keyCode == UInt16(kVK_Tab) && flags == [.option] {
                    self.onOptionTab?()
                    return nil
                }
                let isReturnKey = event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
                let allowedWithCommand = isReturnKey && flags == [.command]
                guard allowedWithCommand
                    || (flags.intersection([.command, .option, .control]).isEmpty
                        && (!flags.contains(.shift) || event.keyCode == UInt16(kVK_Tab))) else {
                    return event
                }
                if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() {
                    return event
                }
                return self.onKey?(event.keyCode, flags.contains(.shift)) == true ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
