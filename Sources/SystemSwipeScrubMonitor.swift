import AppKit

/// Tracks continuous 3-finger horizontal trackpad swipes using a public `CGEvent` tap
/// (`.gesture`, `.swipe`, `.beginGesture`, `.endGesture`), consuming horizontal `.swipe`
/// events so Safari does not navigate Back/Forward while emitting live `deltaX` updates
/// until all fingers are released.
@MainActor
final class SystemSwipeScrubMonitor: SwipeScrubMonitorInterface {
    private enum AxisLock {
        case undecided
        case horizontal
        case ignored
    }

    private static let horizontalStartThreshold: CGFloat = 0.018
    private static let verticalIgnoreThreshold: CGFloat = 0.035

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?
    private var onEvent: (@MainActor (SwipeScrubEvent) -> Void)?
    private var generation = UUID()

    private var origin: CGPoint?
    private var axisLock: AxisLock = .undecided
    private var lastDeltaX: CGFloat = 0
    private var syntheticOffset: CGFloat = 0
    private var fingersAreDown = false

    func start(onEvent: @escaping @MainActor (SwipeScrubEvent) -> Void) {
        stop()
        self.onEvent = onEvent
        generation = UUID()

        let mask =
            NSEvent.EventTypeMask.gesture.rawValue
            | NSEvent.EventTypeMask.swipe.rawValue
            | NSEvent.EventTypeMask.beginGesture.rawValue
            | NSEvent.EventTypeMask.endGesture.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<SystemSwipeScrubMonitor>
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
            SwipeLogger.debug("System swipe scrub tap started")
            return
        }

        SwipeLogger.debug("System swipe scrub tap unavailable; using read-only NSEvent monitor")
        let token = generation
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.gesture, .swipe, .endGesture]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                _ = self.processNSEvent(event)
            }
        }
    }

    func stop() {
        let wasActive = (axisLock == .horizontal)
        let handler = onEvent

        generation = UUID()
        onEvent = nil
        resetGestureState()

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
            runLoopSource = nil
            SwipeLogger.debug("System swipe scrub tap stopped")
        }

        if let fallbackMonitor {
            NSEvent.removeMonitor(fallbackMonitor)
            self.fallbackMonitor = nil
        }

        if wasActive, let handler {
            DispatchQueue.main.async {
                handler(.cancelled)
            }
        }
    }

    private func resetGestureState() {
        origin = nil
        axisLock = .undecided
        lastDeltaX = 0
        syntheticOffset = 0
        fingersAreDown = false
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
            // Swallow horizontal system swipes so Safari never triggers Back/Forward.
            let isHorizontal = event.deltaX != 0 && abs(event.deltaX) >= abs(event.deltaY)
            if isHorizontal && axisLock == .undecided {
                // Fast flick where system recognized a swipe before touch delta crossed threshold.
                let syntheticDelta: CGFloat = event.deltaX > 0 ? -0.09 : 0.09
                if fingersAreDown {
                    axisLock = .horizontal
                    syntheticOffset = (origin == nil ? syntheticDelta : 0)
                    lastDeltaX = syntheticDelta
                    emit(.began)
                    emit(.changed(deltaX: syntheticDelta))
                } else {
                    emit(.began)
                    emit(.changed(deltaX: syntheticDelta))
                    emit(.ended(deltaX: syntheticDelta))
                }
            }
            return isHorizontal

        case .gesture:
            let allTouches = event.allTouches()
            guard !allTouches.isEmpty else { return false }

            let touching = allTouches.filter {
                $0.phase == .began || $0.phase == .moved || $0.phase == .stationary
            }

            if touching.isEmpty {
                fingersAreDown = false
                finishGestureIfActive()
                return false
            }

            fingersAreDown = true

            if touching.count > 3 {
                if axisLock == .undecided {
                    axisLock = .ignored
                }
                return false
            }

            guard touching.count == 3 else {
                // Fewer than 3 fingers touching: if not yet scrubbing, wait for 3 fingers;
                // if already scrubbing, hold `lastDeltaX` steady until all fingers lift.
                if axisLock == .undecided {
                    origin = nil
                }
                return false
            }

            let count = CGFloat(touching.count)
            let avgX = touching.reduce(CGFloat(0)) { $0 + $1.normalizedPosition.x } / count
            let avgY = touching.reduce(CGFloat(0)) { $0 + $1.normalizedPosition.y } / count

            guard let start = origin else {
                origin = CGPoint(x: avgX, y: avgY)
                return false
            }

            let dx = (avgX - start.x) + syntheticOffset
            let dy = avgY - start.y

            switch axisLock {
            case .ignored:
                return false

            case .undecided:
                if abs(dy) > Self.verticalIgnoreThreshold && abs(dy) > abs(dx) * 1.15 {
                    axisLock = .ignored
                    return false
                }
                if abs(dx) > Self.horizontalStartThreshold && abs(dx) > abs(dy) * 1.15 {
                    axisLock = .horizontal
                    // Re-anchor origin slightly so magnetism starts cleanly from when the bubble appears.
                    origin = CGPoint(x: avgX, y: avgY)
                    lastDeltaX = 0
                    emit(.began)
                }
                return false

            case .horizontal:
                lastDeltaX = dx
                emit(.changed(deltaX: dx))
                return false
            }

        case .endGesture:
            finishGestureIfActive()
            return false

        default:
            return false
        }
    }

    private func finishGestureIfActive() {
        if axisLock == .horizontal {
            let finalDelta = lastDeltaX
            resetGestureState()
            emit(.ended(deltaX: finalDelta))
        } else {
            resetGestureState()
        }
    }

    private func emit(_ scrubEvent: SwipeScrubEvent) {
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.onEvent?(scrubEvent)
        }
    }
}
