import Foundation
import SQLite3

struct SafariWindowMetadata: Sendable {
    let id: Int64
    let uuid: String
    let profileID: Int64?
    let profileName: String?
    let groupID: Int64
    let groupName: String
    let restoredWindowIDs: Set<String>
}

/// Live script results determine existence, URL, title, index, and selection.
/// SQLite contributes only saved window/group/profile and bookmark metadata.
actor LiveTabStore {
    private let reader = AppleScriptTabSupplier()
    private let database = TabStore()

    func tabs() async throws -> [SafariTabMatch] {
        let reader = self.reader
        let database = self.database
        async let liveTask = Task.detached(priority: .userInitiated) {
            try reader.readTabs()
        }.value
        async let windowsTask = Task.detached(priority: .userInitiated) {
            try Self.windows()
        }.value
        async let savedTask = database.allTabs()

        let (live, windows, saved) = try await (liveTask, windowsTask, savedTask)
        try Task.checkCancellation()
        return Self.combine(live: live, windows: windows, saved: saved)
    }

    static func combine(
        live: [AppleScriptTabSupplier.Record],
        windows: [SafariWindowMetadata],
        saved: [SafariTabMatch]
    ) -> [SafariTabMatch] {
        guard !live.isEmpty else { return [] }
        let liveWindows = Dictionary(grouping: live, by: \.windowID)
        var savedByWindowID: [Int64: [SafariTabMatch]] = [:]
        var savedURLSetByWindowID: [Int64: Set<String>] = [:]
        var savedByWindowAndPageURL: [Int64: [String: [SafariTabMatch]]] = [:]

        for match in saved {
            guard let winID = match.windowID else { continue }
            let normalizedURL = TabStore.pageURL(match.url)
            savedByWindowID[winID, default: []].append(match)
            savedURLSetByWindowID[winID, default: []].insert(normalizedURL)
            savedByWindowAndPageURL[winID, default: [:]][normalizedURL, default: []].append(match)
        }

        var associations: [String: SafariWindowMetadata] = [:]
        for (id, tabs) in liveWindows {
            let archived = windows.filter { $0.restoredWindowIDs.contains(id) }
            if archived.count == 1 {
                associations[id] = archived[0]
                continue
            }
            // A unique exact URL-set match is a fallback when restoration IDs
            // are unavailable. Ambiguous windows stay unassigned.
            let urls = Set(tabs.map { TabStore.pageURL($0.url) })
            guard !urls.isEmpty else { continue }
            let candidates = windows.filter { window in
                savedURLSetByWindowID[window.id] == urls
            }
            if candidates.count == 1 { associations[id] = candidates[0] }
        }
        // Do not claim a single DB window for multiple distinct live windows.
        let counts = Dictionary(grouping: associations.values, by: \.id).mapValues(\.count)
        return live.map { tab in
            let candidate = associations[tab.windowID]
            let window = candidate.flatMap { counts[$0.id] == 1 ? $0 : nil }
            let normalizedURL = TabStore.pageURL(tab.url)
            let stored = window.flatMap { savedByWindowAndPageURL[$0.id]?[normalizedURL] } ?? []
            let metadata = stored.count == 1 ? stored.first : nil
            return SafariTabMatch(
                tabID: metadata?.tabID ?? -Int64(tab.tabIndex),
                title: tab.title,
                url: tab.url,
                groupID: window?.groupID ?? -1,
                groupName: window?.groupName ?? "Unknown",
                windowID: window?.id,
                windowUUID: window?.uuid,
                activeProfileID: window?.profileID,
                activeProfileName: window?.profileName,
                isActiveGroup: window != nil,
                isActiveTab: tab.selected,
                tabIndex: Int64(tab.tabIndex),
                safariWindowID: tab.windowID
            )
        }
    }

    private static func windows() throws -> [SafariWindowMetadata] {
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(
            TabStore.defaultPath,
            &connection,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard status == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw TabStoreError.open(status)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        let sql = """
        SELECT w.id, w.uuid, w.active_profile_id, p.title,
               w.active_tab_group_id, g.title, w.restoration_archive
        FROM windows w
        LEFT JOIN bookmarks p ON p.id = w.active_profile_id AND p.deleted = 0
        LEFT JOIN bookmarks g ON g.id = w.active_tab_group_id AND g.deleted = 0
        WHERE w.date_closed IS NULL
        """
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw TabStoreError.query(prepared) }
        defer { sqlite3_finalize(statement) }
        func text(_ index: Int32) -> String? {
            sqlite3_column_text(statement, index).map { String(cString: $0) }
        }
        var result: [SafariWindowMetadata] = []
        while true {
            try Task.checkCancellation()
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw TabStoreError.query(status) }
            var ids: Set<String> = []
            if let bytes = sqlite3_column_blob(statement, 6) {
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 6)))
                ids = restoredWindowIDs(data)
            }
            result.append(
                SafariWindowMetadata(
                    id: sqlite3_column_int64(statement, 0),
                    uuid: text(1) ?? "",
                    profileID: sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 2),
                    profileName: text(3),
                    groupID: sqlite3_column_type(statement, 4) == SQLITE_NULL ? -1 : sqlite3_column_int64(statement, 4),
                    groupName: text(5) ?? "Unknown",
                    restoredWindowIDs: ids
                )
            )
        }
    }

    /// Inspect plain plist values, never instantiate archived classes.
    static func restoredWindowIDs(_ data: Data) -> Set<String> {
        var result: Set<String> = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 24 else { return }
            if let data = value as? Data,
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                visit(plist, depth: depth + 1)
            } else if let dictionary = value as? [String: Any] {
                if let number = dictionary["NSWindowNumber"] as? NSNumber {
                    result.insert(number.stringValue)
                }
                for value in dictionary.values { visit(value, depth: depth + 1) }
            } else if let array = value as? [Any] {
                for value in array { visit(value, depth: depth + 1) }
            }
        }
        visit(data, depth: 0)
        return result
    }
}
