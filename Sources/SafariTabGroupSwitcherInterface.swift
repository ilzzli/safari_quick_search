import Foundation

extension Notification.Name {
    static let safariTabGroupDidSwitch = Notification.Name("SafariQuickSearch.safariTabGroupDidSwitch")
}

@MainActor
protocol SafariTabGroupSwitcherInterface: AnyObject {
    var isFocused: Bool { get }
    func previousTabGroup()
    func nextTabGroup()
}
