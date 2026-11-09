import Foundation
import SQLite3

struct SafariTabMatch: Equatable, Sendable {
    let tabID: Int64
    let title: String
    let url: String
    let groupID: Int64
    let groupName: String
    let windowID: Int64?
    let windowUUID: String?
    let activeProfileID: Int64?
    let activeProfileName: String?
    let isActiveGroup: Bool
    let isActiveTab: Bool
    var tabIndex: Int64 = 0
    var safariWindowID: String? = nil

    var resultKey: String {
        let group = ["local", "unnamed", ""].contains(groupName.lowercased()) ? "base" : String(groupID)
        return "\(activeProfileID ?? -1):\(group):\(tabID)"
    }
}

enum TabStoreError: LocalizedError {
    case open(Int32)
    case query(Int32)

    var errorDescription: String? {
        switch self {
        case .open(let code):
            return "Cannot read SafariTabs.db (SQLite \(code)). Grant this app Full Disk Access, then quit and reopen it."
        case .query(let code):
            return "Cannot query Safari tabs (SQLite \(code)). Safari may be busy or its database format may have changed."
        }
    }
}

/// Each lookup reads Safari's live database, including its WAL, without modifying it.
actor TabStore {
    static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db").path
    }

    private let path: String

    init(path: String = TabStore.defaultPath) {
        self.path = path
    }

    // Tab identity preserves query and fragment: different videos/documents must not match.
    nonisolated static func pageURL(_ url: String) -> String {
        let base = url
        guard var components = URLComponents(string: base) else { return base }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.isEmpty { components.path = "/" }
        return components.string ?? base
    }

    func tabs(matchingFullURL url: String) throws -> [SafariTabMatch] {
        try allTabs().filter { Self.pageURL($0.url) == Self.pageURL(url) }
    }

    func allTabs() throws -> [SafariTabMatch] {
        try Task.checkCancellation()
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw TabStoreError.open(status)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        // Saved tabs are metadata candidates only; live selection comes from AppleScript.
        let sql = """
        WITH pins AS (
            SELECT t.*, g.id AS pin_group, g.title AS pin_group_name,
                   ROW_NUMBER() OVER (PARTITION BY t.parent ORDER BY t.order_index, t.id) - 1 AS pin_index,
                   COUNT(*) OVER (PARTITION BY t.parent, t.order_index) AS order_count
            FROM bookmarks t JOIN bookmarks g ON g.id = t.parent
            JOIN bookmarks root ON root.id = g.parent
            WHERE t.deleted = 0 AND g.deleted = 0 AND t.type = 0
              AND g.external_uuid = 'pinned'
              AND root.parent IS NULL AND root.deleted = 0
        ), matches AS (
            SELECT DISTINCT t.id, t.title, t.url, g.id AS group_id, g.title AS group_name,
                   w.id AS window_id, w.uuid, w.active_profile_id, p.title AS profile_name,
                   w.active_tab_group_id = g.id AS active_group,
                   0 AS active_tab, 0 AS pinned, t.order_index AS tab_index
            FROM bookmarks t JOIN bookmarks g ON g.id = t.parent
            JOIN windows w ON w.active_tab_group_id = g.id OR w.local_tab_group_id = g.id OR EXISTS (
                SELECT 1 FROM windows_tab_groups m
                WHERE m.window_id = w.id AND m.tab_group_id = g.id
            ) OR EXISTS (
                SELECT 1 FROM windows_unnamed_tab_groups m
                WHERE m.window_id = w.id AND m.tab_group_id = g.id
            )
            LEFT JOIN windows_tab_groups wtg ON wtg.window_id = w.id AND wtg.tab_group_id = g.id
            LEFT JOIN bookmarks p ON p.id = w.active_profile_id
            WHERE t.deleted = 0 AND g.deleted = 0 AND t.type = 0
              AND w.date_closed IS NULL
            UNION ALL
            SELECT t.id, t.title, t.url, COALESCE(g.id, t.pin_group),
                   COALESCE(g.title, t.pin_group_name), w.id, w.uuid,
                   w.active_profile_id, p.title,
                   COALESCE(w.active_tab_group_id = g.id, 0),
                   0, 1, t.pin_index
            FROM pins t
            LEFT JOIN windows w ON w.date_closed IS NULL
                AND EXISTS (
                    SELECT 1 FROM bookmarks base
                    WHERE base.id = w.local_tab_group_id AND base.deleted = 0
                )
                AND w.active_profile_id IN (
                    SELECT id FROM bookmarks WHERE external_uuid = 'DefaultProfile' AND deleted = 0
                )
            LEFT JOIN bookmarks g ON g.id = w.local_tab_group_id AND g.deleted = 0
            LEFT JOIN bookmarks p ON p.id = w.active_profile_id
        )
        SELECT * FROM matches
        WHERE active_group = 1 AND window_id IS NOT NULL
          AND (url LIKE 'https://%' OR url LIKE 'http://%')
        ORDER BY active_profile_id, group_id, tab_index, id, window_id
        """
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            throw TabStoreError.query(prepared)
        }
        defer { sqlite3_finalize(statement) }
        func text(_ column: Int32) -> String? {
            guard let value = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: value)
        }

        var matches: [SafariTabMatch] = []
        while true {
            try Task.checkCancellation()
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return matches }
            guard result == SQLITE_ROW else { throw TabStoreError.query(result) }
            matches.append(SafariTabMatch(
                tabID: sqlite3_column_int64(statement, 0),
                title: text(1) ?? "",
                url: text(2) ?? "",
                groupID: sqlite3_column_int64(statement, 3),
                groupName: text(4) ?? "",
                windowID: sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(statement, 5),
                windowUUID: text(6),
                activeProfileID: sqlite3_column_type(statement, 7) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(statement, 7),
                activeProfileName: text(8),
                isActiveGroup: sqlite3_column_int(statement, 9) != 0,
                isActiveTab: sqlite3_column_int(statement, 10) != 0,
                tabIndex: sqlite3_column_int64(statement, 12)
            ))
        }
    }
}
