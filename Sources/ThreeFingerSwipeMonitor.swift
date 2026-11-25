import AppKit
import Darwin

/// Private MultitouchSupport ABI: 96-byte contacts, state at 20, normalized x/y at 32/36.
/// See firedev/threefinger's mt.h. Resolve symbols at runtime; fail gracefully if unavailable.
private typealias ContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Void

private final class ContactRouter: @unchecked Sendable {
    static let shared = ContactRouter()
    private let lock = NSLock()
    private var action: (@Sendable (SwipeDirection) -> Void)?
    private struct Gesture {
        var origin: (Float, Float)?
        var fired = false
    }
    private var gestures: [UInt: Gesture] = [:]

    func configure(_ action: (@Sendable (SwipeDirection) -> Void)?) {
        lock.lock()
        self.action = action
        gestures.removeAll()
        lock.unlock()
    }

    func receive(device: UnsafeMutableRawPointer?, contacts: UnsafeMutableRawPointer?, count: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard let action, let device, count >= 0, count <= 32 else { return }
        let key = UInt(bitPattern: device)
        var gesture = gestures[key] ?? Gesture()
        defer { gestures[key] = gesture }
        // Rearm only after every contact has left, not when one finger briefly lifts.
        if count == 0 {
            gesture = Gesture()
            return
        }
        guard let contacts else { return }
        var points: [(Float, Float)] = []
        for index in 0..<Int(count) {
            let contact = contacts.advanced(by: index * 96)
            let state = contact.load(fromByteOffset: 20, as: Int32.self)
            if state == 3 || state == 4 {
                points.append((
                    contact.load(fromByteOffset: 32, as: Float.self),
                    contact.load(fromByteOffset: 36, as: Float.self)
                ))
            }
        }
        guard !gesture.fired else { return }
        guard points.count == 3 else {
            gesture.origin = nil
            if points.count > 3 { gesture.fired = true }
            return
        }
        let x = points.reduce(Float(0)) { $0 + $1.0 } / 3
        let y = points.reduce(Float(0)) { $0 + $1.1 } / 3
        guard let origin = gesture.origin else {
            gesture.origin = (x, y)
            SwipeLogger.debug("Three-finger gesture began")
            return
        }
        let dx = x - origin.0
        let dy = y - origin.1
        if abs(dy) > 0.08 && abs(dy) >= abs(dx) {
            gesture.fired = true
            SwipeLogger.debug("Ignored vertical gesture")
        } else if abs(dx) > 0.08 && abs(dx) > abs(dy) * 1.5 {
            gesture.fired = true
            SwipeLogger.debug(dx < 0 ? "Recognized left swipe" : "Recognized right swipe")
            action(dx < 0 ? .left : .right)
        }
    }
}

@MainActor
final class ThreeFingerSwipeMonitor: SwipeMonitorInterface {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer?, ContactCallback?) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private static weak var owner: ThreeFingerSwipeMonitor?
    private static let callback: ContactCallback = { device, contacts, count, _, _ in
        ContactRouter.shared.receive(device: device, contacts: contacts, count: count)
    }
    private var library: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var devices: [UnsafeMutableRawPointer] = []
    private var unregister: Register?
    private var stopDevice: Stop?
    private var lockFD: Int32 = -1
    private var generation = UUID()

    func start(onSwipe: @escaping @MainActor (SwipeDirection) -> Void) {
        stop()
        Self.owner?.stop()
        Self.owner = self

        // A crashed process releases flock automatically. Never kill another app instance.
        let lockPath = NSTemporaryDirectory() + "SafariQuickSearch-swipes-" + String(getuid()) + ".lock"
        lockFD = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            SwipeLogger.debug("Tracking unavailable: listener lock could not be acquired, errno=\(errno)")
            stop()
            return
        }
        if library == nil {
            library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        }
        guard let library,
              let createSymbol = dlsym(library, "MTDeviceCreateList"),
              let registerSymbol = dlsym(library, "MTRegisterContactFrameCallback"),
              let unregisterSymbol = dlsym(library, "MTUnregisterContactFrameCallback"),
              let startSymbol = dlsym(library, "MTDeviceStart"),
              let stopSymbol = dlsym(library, "MTDeviceStop") else {
            SwipeLogger.debug("Multitouch framework or required symbols unavailable")
            stop()
            return
        }
        let create = unsafeBitCast(createSymbol, to: CreateList.self)
        let register = unsafeBitCast(registerSymbol, to: Register.self)
        let startDevice = unsafeBitCast(startSymbol, to: Start.self)
        unregister = unsafeBitCast(unregisterSymbol, to: Register.self)
        stopDevice = unsafeBitCast(stopSymbol, to: Stop.self)
        deviceList = create()?.takeRetainedValue()
        guard let deviceList else {
            SwipeLogger.debug("No multitouch device list returned")
            stop()
            return
        }
        let token = generation
        ContactRouter.shared.configure { [weak self] direction in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                onSwipe(direction)
            }
        }
        for index in 0..<CFArrayGetCount(deviceList) {
            guard let raw = CFArrayGetValueAtIndex(deviceList, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            guard !devices.contains(device) else { continue }
            devices.append(device)
            register(device, Self.callback)
            startDevice(device, 0)
        }
        SwipeLogger.debug("Tracking started: \(devices.count) device(s)")
    }

    func stop() {
        if !devices.isEmpty { SwipeLogger.debug("Stopping tracking and removing callbacks") }
        generation = UUID()
        if Self.owner === self {
            ContactRouter.shared.configure(nil)
            Self.owner = nil
        }
        for device in devices {
            stopDevice?(device)
            unregister?(device, Self.callback)
        }
        devices.removeAll()
        deviceList = nil
        if lockFD >= 0 {
            flock(lockFD, LOCK_UN)
            close(lockFD)
            lockFD = -1
        }
        // Keep the library loaded: callbacks may still be unwinding on its thread.
    }
}
