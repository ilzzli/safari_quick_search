import AppKit
import ServiceManagement

@MainActor
final class AppActions: AppActionsInterface {
    private weak var panel: NSPanel?
    private let outsideClickMonitor = OutsideClickMonitor()

    func attachPanel(_ panel: NSPanel) {
        self.panel = panel
    }

    func showPanel() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        outsideClickMonitor.start(panel: panel) { [weak self] in
            self?.hidePanel()
        }
    }

    func hidePanel() {
        outsideClickMonitor.stop()
        panel?.orderOut(nil)
    }

    func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    var launchAtStartupEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtStartup(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try service.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Change Launch at Startup"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
