import AppKit
import Carbon
import SQLite3

/// Switches Safari tab groups by invoking a macOS Shortcuts app shortcut (e.g. "Open Safari Tab Group 3")
/// with the next/previous named tab group of Safari's frontmost window.
/// Falls back to `fallback` (menu-based switcher) when the shortcut is not registered or tab groups cannot be resolved.
@MainActor
final class ShortcutTabGroupSwitcher: SafariTabGroupSwitcherInterface {
    private struct TabGroupEntry: Sendable {
        let id: Int64
        let title: String
    }

    private struct WindowGroupSnapshot: Sendable {
        let windowID: Int64
        let activeGroupID: Int64?
        let localGroupID: Int64?
        let groups: [TabGroupEntry]
    }

    private struct OptimisticSwitch {
        let windowID: Int64
        let previousDBGroupID: Int64?
        let targetGroupID: Int64
        let timestamp: TimeInterval
    }

    private final class ShortcutsBridge: @unchecked Sendable {
        private static let scriptSource = """
        on shortcut_exists(shortcutName)
            tell application id "com.apple.shortcuts.events"
                return exists shortcut shortcutName
            end tell
        end shortcut_exists

        on run_shortcut(shortcutName, groupName)
            ignoring application responses
                tell application id "com.apple.shortcuts.events"
                    run shortcut shortcutName with input groupName
                end tell
            end ignoring
        end run_shortcut
        """

        private let queue = DispatchQueue(label: "SafariQuickSearch.ShortcutTabGroupSwitcher", qos: .userInteractive)
        private var compiledScript: NSAppleScript?
        private var cachedRegistered: Bool?
        private var lastCheckTime: TimeInterval = 0
        private var didPrewarm = false

        func prewarm(shortcutName: String) {
            if !didPrewarm {
                didPrewarm = true
                let eventsURL = URL(fileURLWithPath: "/System/Library/CoreServices/Shortcuts Events.app")
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.hides = true
                NSWorkspace.shared.openApplication(at: eventsURL, configuration: config) { _, _ in }
            }
            queue.async { [weak self] in
                guard let self else { return }
                _ = self.checkRegisteredLocked(shortcutName: shortcutName, force: true)
            }
        }

        func runIfRegistered(
            shortcutName: String,
            groupName: String,
            completion: @escaping @Sendable (Bool) -> Void
        ) {
            queue.async { [weak self] in
                guard let self else {
                    completion(false)
                    return
                }
                let registered = self.checkRegisteredLocked(shortcutName: shortcutName, force: false)
                guard registered else {
                    completion(false)
                    return
                }
                guard let script = self.ensureScriptLocked() else {
                    completion(false)
                    return
                }
                let event = self.makeSubroutineEvent(name: "run_shortcut", arguments: [shortcutName, groupName])
                var error: NSDictionary?
                script.executeAppleEvent(event, error: &error)
                if let error {
                    SwipeLogger.debug("Shortcut '\(shortcutName)' execution failed: \(error)")
                    self.cachedRegistered = nil
                    completion(false)
                    return
                }
                completion(true)
            }
        }

        private func checkRegisteredLocked(shortcutName: String, force: Bool) -> Bool {
            let now = ProcessInfo.processInfo.systemUptime
            if !force, let cached = cachedRegistered {
                // Re-verify occasionally (more frequently if previously missing so newly added shortcuts work promptly).
                let ttl: TimeInterval = cached ? 30.0 : 5.0
                if now - lastCheckTime < ttl {
                    return cached
                }
            }
            guard let script = ensureScriptLocked() else {
                cachedRegistered = false
                lastCheckTime = now
                return false
            }
            let event = makeSubroutineEvent(name: "shortcut_exists", arguments: [shortcutName])
            var error: NSDictionary?
            let result = script.executeAppleEvent(event, error: &error)
            let exists = (error == nil) && result.booleanValue
            cachedRegistered = exists
            lastCheckTime = now
            SwipeLogger.debug("Shortcut '\(shortcutName)' registered=\(exists)")
            return exists
        }

        private func ensureScriptLocked() -> NSAppleScript? {
            if let compiledScript { return compiledScript }
            guard let script = NSAppleScript(source: Self.scriptSource) else { return nil }
            var error: NSDictionary?
            script.compileAndReturnError(&error)
            if let error {
                SwipeLogger.debug("Failed to compile Shortcuts AppleScript: \(error)")
                return nil
            }
            compiledScript = script
            return script
        }

        private func makeSubroutineEvent(name: String, arguments: [String]) -> NSAppleEventDescriptor {
            let params = NSAppleEventDescriptor.list()
            for (index, value) in arguments.enumerated() {
                params.insert(NSAppleEventDescriptor(string: value), at: index + 1)
            }
            let event = NSAppleEventDescriptor.appleEvent(
                withEventClass: AEEventClass(kASAppleScriptSuite),
                eventID: AEEventID(kASSubroutineEvent),
                targetDescriptor: NSAppleEventDescriptor.null(),
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            event.setParam(NSAppleEventDescriptor(string: name), forKeyword: AEKeyword(keyASSubroutineName))
            event.setParam(params, forKeyword: AEKeyword(keyDirectObject))
            return event
        }
    }

    let shortcutName: String
    private let fallback: any SafariTabGroupSwitcherInterface
    private let dbPath: String
    private let bridge = ShortcutsBridge()
    private var optimisticSwitch: OptimisticSwitch?
    private var didLogBookmarksSchema = false

    init(
        shortcutName: String = "Open Safari Tab Group 3",
        fallback: any SafariTabGroupSwitcherInterface,
        dbPath: String = TabStore.defaultPath
    ) {
        self.shortcutName = shortcutName
        self.fallback = fallback
        self.dbPath = dbPath
        bridge.prewarm(shortcutName: shortcutName)
    }

    var isFocused: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari"
    }

    func previousTabGroup() {
        switchTabGroup(offset: -1)
    }

    func nextTabGroup() {
        switchTabGroup(offset: 1)
    }

    private func switchTabGroup(offset: Int) {
        guard isFocused else {
            SwipeLogger.debug("Skipped tab group switch: Safari lost focus")
            return
        }

        guard let snapshot = readFrontWindowGroups(), !snapshot.groups.isEmpty else {
            SwipeLogger.debug("Could not resolve frontmost Safari window tab groups; falling back to menu switcher")
            invokeFallback(offset: offset)
            return
        }

        let effectiveActiveID = resolvedActiveGroupID(for: snapshot)
        let isDefaultNoGroup = effectiveActiveID == nil || effectiveActiveID == snapshot.localGroupID
        let count = snapshot.groups.count
        let targetIndex: Int

        if !isDefaultNoGroup,
           let activeID = effectiveActiveID,
           let currentIndex = snapshot.groups.firstIndex(where: { $0.id == activeID }) {
            targetIndex = ((currentIndex + offset) % count + count) % count
        } else {
            // Currently on default "no-group" (local) group:
            // next (left swipe) goes to first group; previous (right swipe) goes to last group.
            targetIndex = offset > 0 ? 0 : count - 1
        }

        let target = snapshot.groups[targetIndex]
        let previousDBGroupID = snapshot.activeGroupID
        let now = ProcessInfo.processInfo.systemUptime
        let name = shortcutName

        SwipeLogger.debug(
            "Win=\(snapshot.windowID) active=\(effectiveActiveID.map(String.init) ?? "nil") local=\(snapshot.localGroupID.map(String.init) ?? "nil") groups=[\(snapshot.groups.map(\.title).joined(separator: ", "))] -> '\(target.title)' (index \(targetIndex)/\(count))"
        )

        bridge.runIfRegistered(shortcutName: name, groupName: target.title) { [weak self] ran in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if ran {
                    self.optimisticSwitch = OptimisticSwitch(
                        windowID: snapshot.windowID,
                        previousDBGroupID: previousDBGroupID,
                        targetGroupID: target.id,
                        timestamp: now
                    )
                } else {
                    SwipeLogger.debug("Shortcut '\(name)' unavailable; falling back to menu switcher")
                    self.invokeFallback(offset: offset)
                }
            }
        }
    }

    private func resolvedActiveGroupID(for snapshot: WindowGroupSnapshot) -> Int64? {
        if let optimistic = optimisticSwitch {
            let age = ProcessInfo.processInfo.systemUptime - optimistic.timestamp
            if optimistic.windowID == snapshot.windowID,
               age < 2.0,
               snapshot.activeGroupID == optimistic.previousDBGroupID {
                return optimistic.targetGroupID
            }
            optimisticSwitch = nil
        }
        return snapshot.activeGroupID
    }

    private func invokeFallback(offset: Int) {
        if offset < 0 {
            fallback.previousTabGroup()
        } else {
            fallback.nextTabGroup()
        }
    }

    private func readFrontWindowGroups() -> WindowGroupSnapshot? {
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(dbPath, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            SwipeLogger.debug("Could not open SafariTabs.db (SQLite \(status))")
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        #if SQS_Debug
        if !didLogBookmarksSchema {
            didLogBookmarksSchema = true
            Self.logBookmarksOrderingColumns(db: db)
        }
        #endif

        struct OpenWindowRow {
            let id: Int64
            let activeProfileID: Int64?
            let activeProfileExternalUUID: String?
            let activeGroupID: Int64?
            let localGroupID: Int64?
            let restoredWindowIDs: Set<String>
        }

        let windowsSQL = """
        SELECT w.id, w.active_profile_id, p.external_uuid, w.active_tab_group_id, w.local_tab_group_id, w.restoration_archive
        FROM windows w
        LEFT JOIN bookmarks p ON p.id = w.active_profile_id AND p.deleted = 0
        WHERE w.date_closed IS NULL
        """
        var winStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, windowsSQL, -1, &winStmt, nil) == SQLITE_OK, let winStmt else {
            return nil
        }
        defer { sqlite3_finalize(winStmt) }

        var openWindows: [OpenWindowRow] = []
        while sqlite3_step(winStmt) == SQLITE_ROW {
            var restoredIDs: Set<String> = []
            if let bytes = sqlite3_column_blob(winStmt, 5) {
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(winStmt, 5)))
                restoredIDs = LiveTabStore.restoredWindowIDs(data)
            }
            openWindows.append(
                OpenWindowRow(
                    id: sqlite3_column_int64(winStmt, 0),
                    activeProfileID: sqlite3_column_type(winStmt, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(winStmt, 1),
                    activeProfileExternalUUID: sqlite3_column_text(winStmt, 2).map { String(cString: $0) },
                    activeGroupID: sqlite3_column_type(winStmt, 3) == SQLITE_NULL ? nil : sqlite3_column_int64(winStmt, 3),
                    localGroupID: sqlite3_column_type(winStmt, 4) == SQLITE_NULL ? nil : sqlite3_column_int64(winStmt, 4),
                    restoredWindowIDs: restoredIDs
                )
            )
        }
        guard !openWindows.isEmpty else { return nil }

        let matchedWindow: OpenWindowRow
        if let frontWindowNumber = Self.frontmostSafariWindowNumber(),
           let found = openWindows.first(where: { $0.restoredWindowIDs.contains(frontWindowNumber) }) {
            matchedWindow = found
        } else if openWindows.count == 1 {
            matchedWindow = openWindows[0]
        } else {
            return nil
        }

        // DefaultProfile's named tab groups are stored directly under Root (id = 0, parent IS NULL),
        // whereas custom profiles store their named tab groups under parent = active_profile_id.
        let containerParentID: Int64
        if let profileID = matchedWindow.activeProfileID,
           matchedWindow.activeProfileExternalUUID != "DefaultProfile" {
            containerParentID = profileID
        } else {
            containerParentID = Self.rootFolderID(db: db)
        }

        let groupsSQL = """
        SELECT g.id, g.title
        FROM bookmarks g
        WHERE g.deleted = 0
          AND g.type = 1
          AND g.subtype = 0
          AND g.parent = ?
          AND g.id != ?
          AND COALESCE(g.external_uuid, '') NOT IN ('pinned', 'privatePinned', 'recentlyClosed')
          AND COALESCE(g.external_uuid, '') NOT LIKE 'pinned-%'
          AND g.title IS NOT NULL
          AND g.title != ''
          AND (
              EXISTS (
                  SELECT 1 FROM bookmarks c
                  WHERE c.parent = g.id AND c.deleted = 0 AND c.subtype = 1
              )
              OR (
                  g.title NOT IN ('Windows', 'Local', 'Private', 'Unnamed')
                  AND NOT EXISTS (
                      SELECT 1 FROM windows_unnamed_tab_groups u
                      WHERE u.tab_group_id = g.id
                  )
              )
          )
        ORDER BY g.order_index, g.id
        """
        var grpStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, groupsSQL, -1, &grpStmt, nil) == SQLITE_OK, let grpStmt else {
            return nil
        }
        defer { sqlite3_finalize(grpStmt) }

        sqlite3_bind_int64(grpStmt, 1, containerParentID)
        sqlite3_bind_int64(grpStmt, 2, matchedWindow.localGroupID ?? -1)

        var groups: [TabGroupEntry] = []
        while sqlite3_step(grpStmt) == SQLITE_ROW {
            let groupID = sqlite3_column_int64(grpStmt, 0)
            guard let rawTitle = sqlite3_column_text(grpStmt, 1) else { continue }
            let title = String(cString: rawTitle)
            guard !SafariTabGroup.isBaseTitle(title) else { continue }
            groups.append(TabGroupEntry(id: groupID, title: title))
        }

        return WindowGroupSnapshot(
            windowID: matchedWindow.id,
            activeGroupID: matchedWindow.activeGroupID,
            localGroupID: matchedWindow.localGroupID,
            groups: groups
        )
    }

    private static func rootFolderID(db: OpaquePointer) -> Int64 {
        let sql = "SELECT id FROM bookmarks WHERE parent IS NULL AND deleted = 0 AND external_uuid = 'Root' LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    #if SQS_Debug
    private static func logBookmarksOrderingColumns(db: OpaquePointer) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(bookmarks)", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        var cols: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                cols.append(String(cString: name))
            }
        }
        SwipeLogger.debug("bookmarks columns: \(cols.joined(separator: ", "))")
    }
    #endif

    private static func frontmostSafariWindowNumber() -> String? {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            return nil
        }
        let pid = safari.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, width > 100,
                  let height = bounds["Height"] as? Double, height > 100,
                  let number = info[kCGWindowNumber as String] as? Int else {
                continue
            }
            return String(number)
        }
        return nil
    }
}
