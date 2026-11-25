@MainActor
protocol SafariTabGroupSwitcherInterface: AnyObject {
    var isFocused: Bool { get }
    func previousTabGroup()
    func nextTabGroup()
}
