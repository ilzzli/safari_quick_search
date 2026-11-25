import AppKit

/// Interactive 3-finger swipe handler that presents a floating Liquid Glass multivalue toggle bubble
/// starting on Safari's active tab group, applies magnetic detent resistance while scrubbing,
/// and invokes the shortcut with whichever tab group the user stopped on upon release.
@MainActor
final class BubbleSafariSwipeHandler: SafariSwipeHandlerInterface {
    private struct ActiveSession {
        let snapshot: SafariActiveWindowTabGroups
        var selectedIndex: Int?
        var slotAnchorX: CGFloat = 0
        var hasMovedFromInitial = false
        var lastStepDirection: Int = 1
    }

    /// Magnetic breakout distance required to leave the starting tab group (fraction of trackpad width).
    private static let initialBreakoutDistance: CGFloat = 0.065
    /// Magnetic breakout distance per additional tab group step after the first move.
    private static let stepBreakoutDistance: CGFloat = 0.095

    private let scrubMonitor: any SwipeScrubMonitorInterface
    private let shortcutSwitcher: ShortcutTabGroupSwitcher
    private let bubbleController: TabGroupBubblePanelController
    private var session: ActiveSession?

    init(
        scrubMonitor: any SwipeScrubMonitorInterface,
        shortcutSwitcher: ShortcutTabGroupSwitcher,
        bubbleController: TabGroupBubblePanelController? = nil
    ) {
        self.scrubMonitor = scrubMonitor
        self.shortcutSwitcher = shortcutSwitcher
        self.bubbleController = bubbleController ?? TabGroupBubblePanelController()
    }

    var isSafariFocused: Bool {
        shortcutSwitcher.isFocused
    }

    func start() {
        scrubMonitor.start { [weak self] event in
            self?.handleScrubEvent(event)
        }
    }

    func stop() {
        scrubMonitor.stop()
        session = nil
        bubbleController.dismiss(immediate: true)
    }

    private func handleScrubEvent(_ event: SwipeScrubEvent) {
        switch event {
        case .began:
            guard isSafariFocused else { return }
            guard let snapshot = shortcutSwitcher.activeWindowTabGroups(), !snapshot.groups.isEmpty else {
                session = nil
                return
            }
            session = ActiveSession(
                snapshot: snapshot,
                selectedIndex: snapshot.activeIndex,
                slotAnchorX: 0,
                hasMovedFromInitial: false
            )
            SwipeLogger.debug(
                "Bubble began: active=\(snapshot.activeIndex.map(String.init) ?? "none") groups=[\(snapshot.groups.map(\.title).joined(separator: ", "))]"
            )
            bubbleController.show(
                groups: snapshot.groups,
                initialActiveIndex: snapshot.activeIndex,
                selectedIndex: snapshot.activeIndex,
                safariWindowFrame: snapshot.windowFrame
            )

        case .changed(let deltaX):
            updateSelection(deltaX: deltaX)

        case .ended(let deltaX):
            updateSelection(deltaX: deltaX)
            commitAndDismiss(finalDeltaX: deltaX)

        case .cancelled:
            session = nil
            bubbleController.dismiss(immediate: true)
        }
    }

    private func updateSelection(deltaX: CGFloat) {
        guard var currentSession = session else { return }
        let count = currentSession.snapshot.groups.count
        guard count > 0 else { return }

        var localDelta = deltaX - currentSession.slotAnchorX
        var didSnap = false

        // Handle entering the toggle bubble from Safari's default "no-group" state.
        if currentSession.selectedIndex == nil {
            let threshold = Self.initialBreakoutDistance
            if localDelta >= threshold {
                currentSession.selectedIndex = 0
                currentSession.slotAnchorX += threshold
                currentSession.hasMovedFromInitial = true
                currentSession.lastStepDirection = 1
                localDelta = deltaX - currentSession.slotAnchorX
                didSnap = true
            } else if localDelta <= -threshold {
                currentSession.selectedIndex = count - 1
                currentSession.slotAnchorX -= threshold
                currentSession.hasMovedFromInitial = true
                currentSession.lastStepDirection = -1
                localDelta = deltaX - currentSession.slotAnchorX
                didSnap = true
            }
        }

        // Step across adjacent tab groups whenever the user pushes past the magnetic detent force,
        // looping seamlessly across the start and end boundaries when there are multiple groups.
        while let currentIndex = currentSession.selectedIndex, count > 1 {
            let threshold = currentSession.hasMovedFromInitial
                ? Self.stepBreakoutDistance
                : Self.initialBreakoutDistance

            if localDelta >= threshold {
                currentSession.selectedIndex = (currentIndex + 1) % count
                currentSession.slotAnchorX += threshold
                currentSession.hasMovedFromInitial = true
                currentSession.lastStepDirection = 1
                localDelta = deltaX - currentSession.slotAnchorX
                didSnap = true
            } else if localDelta <= -threshold {
                currentSession.selectedIndex = (currentIndex - 1 + count) % count
                currentSession.slotAnchorX -= threshold
                currentSession.hasMovedFromInitial = true
                currentSession.lastStepDirection = -1
                localDelta = deltaX - currentSession.slotAnchorX
                didSnap = true
            } else {
                break
            }
        }

        if didSnap {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            if let idx = currentSession.selectedIndex {
                SwipeLogger.debug("Bubble snapped to '\(currentSession.snapshot.groups[idx].title)' (index \(idx)/\(count))")
            }
        }

        // Compute elastic magnetic pull (-1...1) so the pill visibly leans & resists before snapping.
        let magneticPull: CGFloat
        if currentSession.selectedIndex != nil {
            let threshold = currentSession.hasMovedFromInitial
                ? Self.stepBreakoutDistance
                : Self.initialBreakoutDistance
            let sign: CGFloat = localDelta >= 0 ? 1 : -1

            if count == 1 {
                let normalized = min(abs(localDelta) / threshold, 1.5)
                magneticPull = sign * (normalized / (1 + normalized)) * 0.55
            } else {
                let ratio = min(abs(localDelta) / threshold, 1.0)
                magneticPull = sign * pow(ratio, 1.35)
            }
        } else {
            magneticPull = 0
        }

        session = currentSession
        bubbleController.update(selectedIndex: currentSession.selectedIndex, magneticPull: magneticPull)
    }

    private func commitAndDismiss(finalDeltaX: CGFloat) {
        let finished = session
        session = nil
        bubbleController.dismiss()

        guard isSafariFocused else { return }

        guard let finished else {
            // No named groups resolved from DB; fall back to menu switching if swipe crossed breakout distance.
            if abs(finalDeltaX) >= Self.initialBreakoutDistance {
                if finalDeltaX > 0 {
                    shortcutSwitcher.nextTabGroup()
                } else {
                    shortcutSwitcher.previousTabGroup()
                }
            }
            return
        }

        guard let targetIndex = finished.selectedIndex else {
            SwipeLogger.debug("Bubble ended without leaving default group; no switch")
            return
        }

        if targetIndex == finished.snapshot.activeIndex {
            SwipeLogger.debug("Bubble ended on current active group '\(finished.snapshot.groups[targetIndex].title)'; no switch")
            return
        }

        let target = finished.snapshot.groups[targetIndex]

        shortcutSwitcher.openTabGroup(
            target,
            inWindow: finished.snapshot.windowID,
            previousDBGroupID: finished.snapshot.activeGroupID,
            fallbackOffset: finished.lastStepDirection
        )
    }
}
