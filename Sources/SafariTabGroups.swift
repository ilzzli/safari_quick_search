import Foundation
import SQLite3

actor SafariTabGroups: TabGroupsInterface {
    private let path: String

    init(path: String = TabStore.defaultPath) {
        self.path = path
    }

    func profiles() throws -> [SafariProfileGroups] {
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw TabStoreError.open(status)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        // Only profiles with open windows are shown. Base and active groups can
        // be linked directly from windows before membership rows are available.
        let sql = """
        WITH open_windows AS (
            SELECT * FROM windows WHERE date_closed IS NULL
        )
        SELECT COALESCE(w.active_profile_id, -1), p.title,
               w.id, w.uuid, w.active_tab_group_id, g.id, g.title
        FROM open_windows w
        LEFT JOIN bookmarks p ON p.id = w.active_profile_id AND p.deleted = 0
        LEFT JOIN bookmarks g ON g.id = w.active_tab_group_id AND g.deleted = 0
        ORDER BY COALESCE(w.active_profile_id, -1), w.id, g.order_index, g.id
        """
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw TabStoreError.query(prepared) }
        defer { sqlite3_finalize(statement) }
        func text(_ index: Int32) -> String? {
            guard let value = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: value)
        }
        struct WindowData {
            let title: String
            let active: String?
            var groups: [SafariTabGroup] = []
        }
        var profileOrder: [String] = []
        var titles: [String: String] = [:]
        var windowOrder: [String: [String]] = [:]
        var windows: [String: WindowData] = [:]
        while true {
            try Task.checkCancellation()
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw TabStoreError.query(result) }
            let profileID = String(sqlite3_column_int64(statement, 0))
            if titles[profileID] == nil {
                profileOrder.append(profileID)
                let title = text(1) ?? ""
                titles[profileID] = title.isEmpty ? "Default / unnamed profile" : title
            }
            guard sqlite3_column_type(statement, 2) != SQLITE_NULL else { continue }
            let windowID = String(sqlite3_column_int64(statement, 2))
            let key = profileID + ":" + windowID
            if windows[key] == nil {
                windowOrder[profileID, default: []].append(key)
                windows[key] = WindowData(
                    title: "Window " + windowID,
                    active: sqlite3_column_type(statement, 4) == SQLITE_NULL
                        ? nil : String(sqlite3_column_int64(statement, 4))
                )
            }
            if sqlite3_column_type(statement, 5) != SQLITE_NULL {
                let groupID = String(sqlite3_column_int64(statement, 5))
                let title = text(6) ?? ""
                if windows[key]?.groups.contains(where: { $0.id == groupID }) == false {
                    windows[key]?.groups.append(SafariTabGroup(
                        id: groupID, title: title.isEmpty ? "Unnamed" : title
                    ))
                }
            }
        }
        return profileOrder.map { profileID in
            SafariProfileGroups(
                id: profileID, title: titles[profileID] ?? "Unnamed profile",
                windows: (windowOrder[profileID] ?? []).compactMap { key in
                    guard let data = windows[key] else { return nil }
                    return SafariWindowTabGroups(
                        id: key, windowTitle: data.title, groups: data.groups, activeGroupID: data.active
                    )
                }
            )
        }
    }
}
