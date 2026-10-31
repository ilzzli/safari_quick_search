import Foundation
import SQLite3

struct HistoryEntry: Identifiable, Equatable {
    let id: Int64
    let title: String
    let url: String
    var displayURL: String {
        String(url.prefix { $0 != "?" && $0 != "#" })
    }
}

enum HistoryError: LocalizedError {
    case open(Int32), query(Int32), timedOut
    var errorDescription: String? {
        switch self {
        case .open(let code):
            return "Cannot read Safari history (SQLite \(code)). Grant this app Full Disk Access, quit and reopen it. If access is already enabled, check the database location."
        case .query(let code):
            return "History search failed (SQLite \(code)). Safari may be busy, or its database format may have changed. Try again."
        case .timedOut:
            return "History search took too long. Try a more specific phrase."
        }
    }
}

// Shared between the main thread and one serial database queue.
final class SearchTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var deadline = Date.distantFuture
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func start() { lock.lock(); deadline = Date().addingTimeInterval(2); lock.unlock() }
    var shouldStop: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled || Date() >= deadline
    }
}

struct HistoryStore {
    let path: String
    static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/History.db").path
    }

    // Each search owns a short-lived read-only connection. Never copy a live DB
    // without its WAL, set immutable=1, change journal mode, or run a checkpoint.
    func search(_ input: String, ticket: SearchTicket) throws -> [HistoryEntry] {
        if ticket.shouldStop { return [] }
        ticket.start()
        var connection: OpaquePointer?
        let opened = sqlite3_open_v2(path, &connection,
                                    SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard opened == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw HistoryError.open(opened)
        }
        defer { sqlite3_close(db) }
        guard sqlite3_db_readonly(db, "main") == 1 else { throw HistoryError.open(SQLITE_READONLY) }
        let registered = sqlite3_create_function_v2(db, "is_google_search", 1,
            SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, _, arguments in
                guard let value = arguments?[0], let text = sqlite3_value_text(value) else {
                    sqlite3_result_int(context, 0)
                    return
                }
                sqlite3_result_int(context, HistoryStore.isGoogleSearchURL(String(cString: text)) ? 1 : 0)
            }, nil, nil, nil)
        guard registered == SQLITE_OK else { throw HistoryError.query(registered) }
        sqlite3_busy_timeout(db, 150)
        guard sqlite3_exec(db, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
            throw HistoryError.query(sqlite3_errcode(db))
        }
        sqlite3_progress_handler(db, 1000, { context in
            guard let context else { return 1 }
            return Unmanaged<SearchTicket>.fromOpaque(context).takeUnretainedValue().shouldStop ? 1 : 0
        }, Unmanaged.passUnretained(ticket).toOpaque())
        defer { sqlite3_progress_handler(db, 0, nil, nil) }

        // Match only the displayed title and the representative URL's base.
        // Query strings, fragments, older titles and older group URLs cannot
        // cause an unrelated row to appear. Keep the full URL for navigation.
        let sql = """
        WITH without_fragments AS (
            SELECT id, url, CASE WHEN instr(url, '#') > 0
                THEN substr(url, 1, instr(url, '#') - 1) ELSE url END AS no_fragment
            FROM history_items
            WHERE (url LIKE 'https://%' OR url LIKE 'http://%')
              AND is_google_search(url) = 0
        ), urls AS (
            SELECT id, url, CASE WHEN instr(no_fragment, '?') > 0
                THEN substr(no_fragment, 1, instr(no_fragment, '?') - 1)
                ELSE no_fragment END AS base_url FROM without_fragments
        ), pages AS (
            SELECT h.id, h.url, h.base_url, MAX(v.visit_time) AS last_visit,
                COALESCE((
                    SELECT t.title FROM history_visits t
                    WHERE t.history_item = h.id AND t.title IS NOT NULL AND t.title <> ''
                    ORDER BY t.visit_time DESC, t.id DESC LIMIT 1
                ), h.base_url) AS titleText
            FROM urls h JOIN history_visits v ON v.history_item = h.id
            GROUP BY h.id, h.url, h.base_url
        ), grouped AS (
            SELECT *, ROW_NUMBER() OVER (
                PARTITION BY titleText COLLATE BINARY
                ORDER BY last_visit DESC, id DESC
            ) AS position FROM pages
        )
        SELECT id, url, titleText FROM grouped
        WHERE position = 1
          AND (base_url LIKE ?1 ESCAPE '\\' OR titleText LIKE ?1 ESCAPE '\\')
        ORDER BY last_visit DESC, id DESC LIMIT ?2
        """
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw HistoryError.query(prepared) }
        defer { sqlite3_finalize(statement) }
        let pattern = "%" + Self.escapeLike(input) + "%"
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = pattern.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        guard bound == SQLITE_OK, sqlite3_bind_int(statement, 2, 20) == SQLITE_OK else {
            throw HistoryError.query(sqlite3_errcode(db))
        }
        var rows: [HistoryEntry] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            if result == SQLITE_INTERRUPT { throw HistoryError.timedOut }
            guard result == SQLITE_ROW else { throw HistoryError.query(result) }
            guard let urlText = sqlite3_column_text(statement, 1),
                  let titleText = sqlite3_column_text(statement, 2) else { continue }
            rows.append(HistoryEntry(id: sqlite3_column_int64(statement, 0),
                                     title: String(cString: titleText), url: String(cString: urlText)))
        }
        return rows
    }

    // Recognize search pages by URL, not their localized page titles. Other
    // Google products (Docs, Drive, etc.) remain eligible for suggestions.
    static func isGoogleSearchURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let rawHost = components.host?.lowercased() else { return false }
        let labels = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".").map(String.init)
        guard let googleIndex = labels.lastIndex(of: "google") else { return false }
        let suffix = Array(labels.dropFirst(googleIndex + 1))
        let isCountryCode: (String) -> Bool = { value in
            value.count == 2 && value.utf8.allSatisfy { (97...122).contains($0) }
        }
        let googleDomain = suffix == ["com"] || suffix == ["cat"]
            || (suffix.count == 1 && isCountryCode(suffix[0]))
            || (suffix.count == 2 && ["co", "com"].contains(suffix[0]) && isCountryCode(suffix[1]))
        guard googleDomain else { return false }
        let prefix = labels.prefix(googleIndex).joined(separator: ".")
        guard ["", "www", "m", "images", "news", "video"].contains(prefix) else { return false }
        let path = components.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if ["search", "webhp", "custom", "cse"].contains(path) { return true }
        guard path.isEmpty else { return false }
        let hasQuery = components.queryItems?.contains { $0.name.lowercased() == "q" } == true
        // Older Google search pages stored the query in their URL fragment.
        let fragment = components.fragment ?? ""
        let hasFragmentQuery = fragment.split(separator: "&").contains {
            $0.lowercased().hasPrefix("q=")
        }
        return hasQuery || hasFragmentQuery
    }

    static func escapeLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
