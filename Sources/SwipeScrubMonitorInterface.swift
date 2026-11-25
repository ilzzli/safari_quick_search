import CoreGraphics

enum SwipeScrubEvent: Sendable {
    /// Three-finger horizontal swipe gesture started.
    case began
    /// Continuous normalized horizontal displacement from the gesture's start point
    /// (positive = fingers moved right, negative = fingers moved left).
    case changed(deltaX: CGFloat)
    /// Three fingers were released (gesture finished).
    case ended(deltaX: CGFloat)
    /// Gesture was cancelled (e.g., tracking stopped).
    case cancelled
}

@MainActor
protocol SwipeScrubMonitorInterface: AnyObject {
    func start(onEvent: @escaping @MainActor (SwipeScrubEvent) -> Void)
    func stop()
}
