enum SwipeDirection: Sendable {
    case left, right
}

@MainActor
protocol SwipeMonitorInterface: AnyObject {
    func start(onSwipe: @escaping @MainActor (SwipeDirection) -> Void)
    func stop()
}
