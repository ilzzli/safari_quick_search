import AppKit

/// Intercepts high-level macOS `.swipe` events (requires System Settings -> Trackpad ->
/// More Gestures -> "Swipe between pages" set to "Swipe with Three Fingers" or "Two or Three Fingers"),
/// consumes the horizontal swipe immediately so Safari does not navigate Back/Forward,
/// and defers triggering `onSwipe` until the gesture ends (all fingers are released).
@MainActor
final class SystemSwipeOnReleaseMonitor: SwipeMonitorInterface {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?
    private var onSwipe: (@MainActor (SwipeDirection) -> Void)?
    private var generation = UUID()
    private var activeTouchCount = 0
    private var pendingDirection: SwipeDirection?

    func start(onSwipe: @escaping @MainActor (SwipeDirection) -> Void) {
        stop()
        self.onSwipe = onSwipe
        generation = UUID()

        let mask =
            NSEvent.EventTypeMask.gesture.rawValue
            | NSEvent.EventTypeMask.swipe.rawValue
            | NSEvent.EventTypeMask.beginGesture.rawValue
            | NSEvent.EventTypeMask.endGesture.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<SystemSwipeOnReleaseMonitor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                return monitor.handleTapEvent(type: type, event: event)
            }
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let tap =
            CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: userInfo
            )
            ?? CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: userInfo
            )

        if let tap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            eventTap = tap
            runLoopSource = source
            if let source {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            SwipeLogger.debug("System swipe-on-release tap started")
            return
        }

        SwipeLogger.debug("System swipe-on-release tap unavailable; using read-only NSEvent monitor")
        let token = generation
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.swipe, .gesture, .endGesture]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                _ = self.processNSEvent(event)
            }
        }
    }

    func stop() {
        generation = UUID()
        onSwipe = nil
        activeTouchCount = 0
        pendingDirection = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
            runLoopSource = nil
            SwipeLogger.debug("System swipe-on-release tap stopped")
        }

        if let fallbackMonitor {
            NSEvent.removeMonitor(fallbackMonitor)
            self.fallbackMonitor = nil
        }
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        return processNSEvent(nsEvent) ? nil : Unmanaged.passUnretained(event)
    }

    /// Returns `true` when the event should be swallowed (horizontal `.swipe`).
    private func processNSEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .swipe:
            return handleSwipe(event)

        case .gesture:
            let allTouches = event.allTouches()
            guard !allTouches.isEmpty else { return false }
            let touchingCount = allTouches.filter {
                $0.phase == .began || $0.phase == .moved || $0.phase == .stationary
            }.count
            activeTouchCount = touchingCount
            if touchingCount == 0 {
                flushPendingSwipe(reason: "all fingers released")
            }
            return false

        case .endGesture:
            activeTouchCount = 0
            flushPendingSwipe(reason: "endGesture")
            return false

        default:
            return false
        }
    }

    private func handleSwipe(_ event: NSEvent) -> Bool {
        guard event.deltaX != 0, abs(event.deltaX) >= abs(event.deltaY) else {
            return false
        }

        // Per AppKit NSEvent.deltaX docs: +1.0 is swipe left, -1.0 is swipe right.
        let direction: SwipeDirection = event.deltaX > 0 ? .left : .right
        if activeTouchCount > 0 {
            pendingDirection = direction
            SwipeLogger.debug(
                "Queued \(direction == .left ? "left" : "right") swipe until release (touches=\(activeTouchCount))"
            )
        } else {
            pendingDirection = nil
            SwipeLogger.debug(
                "Recognized \(direction == .left ? "left" : "right") swipe (fingers already released)"
            )
            dispatchSwipe(direction)
        }
        return true
    }

    private func flushPendingSwipe(reason: String) {
        guard let direction = pendingDirection else { return }
        pendingDirection = nil
        SwipeLogger.debug(
            "Dispatching \(direction == .left ? "left" : "right") swipe on \(reason)"
        )
        dispatchSwipe(direction)
    }

    private func dispatchSwipe(_ direction: SwipeDirection) {
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.onSwipe?(direction)
        }
    }
}
