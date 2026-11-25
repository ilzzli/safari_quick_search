import AppKit

@MainActor
protocol SafariSwipeHandlerInterface: AnyObject {
    var isSafariFocused: Bool { get }
    func start()
    func stop()
}

/// Bridges any discrete `SwipeMonitorInterface` and `SafariTabGroupSwitcherInterface`.
@MainActor
final class DiscreteSafariSwipeHandler: SafariSwipeHandlerInterface {
    private let swipeMonitor: any SwipeMonitorInterface
    private let switcher: any SafariTabGroupSwitcherInterface

    init(
        swipeMonitor: any SwipeMonitorInterface,
        switcher: any SafariTabGroupSwitcherInterface
    ) {
        self.swipeMonitor = swipeMonitor
        self.switcher = switcher
    }

    var isSafariFocused: Bool {
        switcher.isFocused
    }

    func start() {
        swipeMonitor.start { [weak self] direction in
            guard let self, self.switcher.isFocused else { return }
            switch direction {
            case .left: self.switcher.nextTabGroup()
            case .right: self.switcher.previousTabGroup()
            }
        }
    }

    func stop() {
        swipeMonitor.stop()
    }
}
