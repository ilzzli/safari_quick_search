import AppKit
import SQLite3

@MainActor
final class SafariControl: SafariTabGroupSwitcherInterface {
    private let dbPath: String
    private var switchNotificationTask: Task<Void, Never>?
    private var compiledScripts: [String: NSAppleScript] = [:]

    init(dbPath: String = TabStore.defaultPath) {
        self.dbPath = dbPath
    }

    var isFocused: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari"
    }

    func previousTabGroup() {
        switchTabGroup(menuItem: "Go To Previous Tab Group")
    }

    func nextTabGroup() {
        switchTabGroup(menuItem: "Go To Next Tab Group")
    }

    private func switchTabGroup(menuItem: String) {
        guard isFocused else {
            SwipeLogger.debug("Skipped tab group switch: Safari lost focus")
            return
        }
        SwipeLogger.debug("Executing Safari command: " + menuItem)
        let beforeGroups = Self.readActiveGroupIDs(dbPath: dbPath)
        let script: NSAppleScript?
        if let cached = compiledScripts[menuItem] {
            script = cached
        } else {
            let source = """
            tell application "System Events"
                tell process "Safari"
                    if frontmost then
                        click menu item "\(menuItem)" of menu "Window" of menu bar 1
                    end if
                end tell
            end tell
            """
            let created = NSAppleScript(source: source)
            var compileError: NSDictionary?
            created?.compileAndReturnError(&compileError)
            if compileError == nil, let created {
                compiledScripts[menuItem] = created
            }
            script = created
        }
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            SwipeLogger.debug("Safari command failed: " + error.description)
            let alert = NSAlert()
            alert.messageText = "Could Not Switch Safari Tab Group"
            alert.informativeText = (error[NSAppleScript.errorMessage] as? String ?? "Safari’s tab group command is unavailable.")
                + "\nAllow this app to control System Events under Automation and grant Accessibility (Device Control and Data Access)."
            alert.runModal()
        } else {
            scheduleTabGroupSwitchNotification(beforeGroups: beforeGroups)
        }
    }

    private func scheduleTabGroupSwitchNotification(beforeGroups: [Int64: Int64?]?) {
        switchNotificationTask?.cancel()
        let path = dbPath
        switchNotificationTask = Task { @MainActor [weak self] in
            var confirmed = false
            if let beforeGroups {
                for _ in 0..<12 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    let current = await Task.detached(priority: .userInitiated) {
                        Self.readActiveGroupIDs(dbPath: path)
                    }.value
                    guard !Task.isCancelled else { return }
                    guard let current else {
                        try? await Task.sleep(for: .milliseconds(250))
                        break
                    }
                    if current != beforeGroups {
                        confirmed = true
                        try? await Task.sleep(for: .milliseconds(120))
                        break
                    }
                }
            } else {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, let self else { return }
            SwipeLogger.debug("Posting menu tab group switch refresh (confirmed=\(confirmed))")
            NotificationCenter.default.post(name: .safariTabGroupDidSwitch, object: self)
        }
    }

    nonisolated private static func readActiveGroupIDs(dbPath: String) -> [Int64: Int64?]? {
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(dbPath, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)

        let sql = "SELECT id, active_tab_group_id FROM windows WHERE date_closed IS NULL"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var groups: [Int64: Int64?] = [:]
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return groups }
            guard step == SQLITE_ROW else { return nil }
            let windowID = sqlite3_column_int64(stmt, 0)
            let groupID = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 1)
            groups[windowID] = groupID
        }
    }
}
