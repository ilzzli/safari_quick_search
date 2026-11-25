import AppKit

/// Actions available to the app's interface.
@MainActor
protocol AppActionsInterface {
    var isPanelVisible: Bool { get }
    var panelFrame: NSRect? { get }
    var launchAtStartupEnabled: Bool { get }
    func setLaunchAtStartup(_ enabled: Bool)
    func showPanel()
    func hidePanel()
    func togglePanel()
    func quit()
}
