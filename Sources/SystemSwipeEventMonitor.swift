import AppKit

/// Intercepts high-level macOS `.swipe` events (requires System Settings -> Trackpad ->
/// More Gestures -> "Swipe between pages" set to "Swipe with Three Fingers" or "Two or Three Fingers").
/// Uses an active `CGEvent` tap so matched horizontal swipes are consumed before reaching Safari.
@MainActor
final class SystemSwipeEventMonitor: SwipeMonitorInterface {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?
    private var onSwipe: (@MainActor (SwipeDirection) -> Void)?
    private var generation = UUID()

    func start(onSwipe: @escaping @MainActor (SwipeDirection) -> Void) {
        stop()
        self.onSwipe = onSwipe
        generation = UUID()

        let mask =
            NSEvent.EventTypeMask.gesture.rawValue
            | NSEvent.EventTypeMask.swipe.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<SystemSwipeEventMonitor>
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
            SwipeLogger.debug("System swipe tap started")
            return
        }

        SwipeLogger.debug("System swipe tap unavailable; using read-only NSEvent monitor")
        let token = generation
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                _ = self.handleSwipe(event)
            }
        }
    }

    func stop() {
        generation = UUID()
        onSwipe = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
            runLoopSource = nil
            SwipeLogger.debug("System swipe tap stopped")
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

        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .swipe else {
            return Unmanaged.passUnretained(event)
        }

        return handleSwipe(nsEvent) ? nil : Unmanaged.passUnretained(event)
    }

    private func handleSwipe(_ event: NSEvent) -> Bool {
        guard event.deltaX != 0, abs(event.deltaX) >= abs(event.deltaY) else {
            return false
        }

        // Per AppKit NSEvent.deltaX docs: +1.0 is swipe left, -1.0 is swipe right.
        let direction: SwipeDirection = event.deltaX > 0 ? .left : .right
        SwipeLogger.debug(direction == .left ? "Recognized left swipe" : "Recognized right swipe")

        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.onSwipe?(direction)
        }
        return true
    }
}
