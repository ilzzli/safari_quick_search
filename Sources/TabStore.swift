import Foundation
import SQLite3

struct SafariTabMatch: Sendable {
    let tabID: Int64
    let title: String
    let url: String
    let groupID: Int64
    let groupName: String
    let windowID: Int64
    let windowUUID: String
    let activeProfileID: Int64?
    let activeProfileName: String?
    let isActiveGroup: Bool
    let isActiveTab: Bool
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

    func tabs(matchingFullURL url: String) throws -> [SafariTabMatch] {
        try Task.checkCancellation()
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw TabStoreError.open(status)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        let sql = """
        SELECT DISTINCT t.id, t.title, t.url, g.id, g.title,
               w.id, w.uuid, w.active_profile_id, p.title,
               CASE WHEN w.active_tab_group_id = g.id THEN 1 ELSE 0 END,
               CASE WHEN wtg.active_tab_id = t.id THEN 1 ELSE 0 END
        FROM bookmarks t
        JOIN bookmarks g ON g.id = t.parent
        JOIN windows_tab_groups wtg ON wtg.tab_group_id = g.id
        JOIN windows w ON w.id = wtg.window_id
        LEFT JOIN bookmarks p ON p.id = w.active_profile_id
        WHERE t.url = ?1 COLLATE BINARY
          AND t.deleted = 0 AND g.deleted = 0
          AND w.date_closed IS NULL
        ORDER BY 10 DESC, 11 DESC, w.id, g.id, t.id
        """
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            throw TabStoreError.query(prepared)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = url.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        guard bound == SQLITE_OK else { throw TabStoreError.query(bound) }

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
                url: text(2) ?? url,
                groupID: sqlite3_column_int64(statement, 3),
                groupName: text(4) ?? "",
                windowID: sqlite3_column_int64(statement, 5),
                windowUUID: text(6) ?? "",
                activeProfileID: sqlite3_column_type(statement, 7) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(statement, 7),
                activeProfileName: text(8),
                isActiveGroup: sqlite3_column_int(statement, 9) != 0,
                isActiveTab: sqlite3_column_int(statement, 10) != 0
            ))
        }
    }
}
