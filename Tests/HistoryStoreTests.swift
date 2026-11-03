import Foundation
import SQLite3

@main
struct HistoryStoreTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("History.db").path
        var raw: OpaquePointer?
        precondition(sqlite3_open(path, &raw) == SQLITE_OK)
        let db = raw!
        defer { sqlite3_close(db) }
        func exec(_ sql: String) {
            precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, String(cString: sqlite3_errmsg(db)))
        }
        exec("""
        PRAGMA journal_mode=WAL;
        PRAGMA wal_autocheckpoint=0;
        CREATE TABLE history_items(id INTEGER PRIMARY KEY, url TEXT);
        CREATE TABLE history_visits(id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL, title TEXT);
        CREATE INDEX visits_item ON history_visits(history_item, visit_time);
        INSERT INTO history_items VALUES
        (1, 'https://example.com/alpha'), (2, 'https://example.org/beta'),
        (3, 'https://example.net/100%_done'), (4, 'javascript:alert(1)'),
        (5, 'https://example.com/日本語');
        INSERT INTO history_visits VALUES
        (1, 1, 10, 'Old Alpha'), (2, 1, 20, 'New Alpha'),
        (3, 2, 30, 'Bob''s Guide'), (4, 3, 40, '100%_done'),
        (5, 4, 50, 'Do not open'), (6, 5, 60, '日本語');
        """)
        let store = HistoryStore(path: path)
        func find(_ value: String) throws -> [HistoryEntry] { try store.search(value, ticket: SearchTicket()) }
        let alpha = try find("alpha")
        precondition(alpha.count == 1 && alpha[0].title == "New Alpha", "Deduplication / newest title")
        precondition(tryValue { try find("OLD").isEmpty }, "Old titles are not searchable")
        precondition(tryValue { try find("Bob's").map(\.id) } == [2], "Bound apostrophe")
        precondition(tryValue { try find("' OR 1=1 --").isEmpty }, "SQL injection is literal")
        precondition(tryValue { try find("%_").map(\.id) } == [3], "LIKE wildcards escaped")
        precondition(tryValue { try find("日本語").map(\.id) } == [5], "Unicode exact substring")
        precondition(tryValue { try find("").map(\.id) } == [5, 3, 2, 1], "Recency / web URLs only")
        precondition(tryValue { try find("missing").isEmpty }, "No matches")
        precondition(HistoryStore.escapeLike("a\\b%_") == "a\\\\b\\%\\_", "Backslash escape")
        let cancelled = SearchTicket(); cancelled.cancel()
        precondition(tryValue { try store.search("", ticket: cancelled).isEmpty }, "Cancelled before start")
        // A still-open writer leaves new data in the WAL; the reader must see it.
        exec("INSERT INTO history_items VALUES(6, 'https://wal.example/'); INSERT INTO history_visits VALUES(7, 6, 70, 'WAL only');")
        precondition(tryValue { try find("WAL only").map(\.id) } == [6], "Live WAL visibility")
        // Query variants of a URL become one row, regardless of title.
        // Navigation keeps the newest full URL; matching uses only visible fields.
        exec("""
        INSERT INTO history_items VALUES
        (7, 'https://example.com/alpha?version=2&sort=new#details'),
        (8, 'https://other.example/latest?token=a%2Fb#section'),
        (9, 'https://untitled.example/one'), (10, 'https://untitled.example/two');
        INSERT INTO history_visits VALUES
        (8, 7, 80, 'Updated Alpha'), (9, 8, 90, 'New Alpha'),
        (10, 9, 100, NULL), (11, 10, 110, '');
        """)
        let grouped = try find("alpha")
        precondition(grouped.count == 2 && grouped[1].title == "Updated Alpha", "Group by base URL, preserve distinct URLs with matching titles")
        precondition(grouped[1].url == "https://example.com/alpha?version=2&sort=new#details", "Latest full URL, including query and fragment")
        precondition(tryValue { try find("version=2").isEmpty }, "Query parameters are not searchable")
        precondition(tryValue { try find("Old Alpha").isEmpty }, "Historical titles do not leak into grouping")
        precondition(tryValue { try find("untitled.example").count } == 2, "Untitled pages use their distinct URLs")
        precondition(tryValue { try find("section").isEmpty }, "Fragments are not searchable")
        precondition(tryValue { try find("example.com/alpha").map(\.id) } == [7], "Query variants collapse to newest URL")
        precondition(tryValue { try find("other.example/latest").map(\.id) } == [8], "Base URL matches")
        precondition(tryValue { try find("NEW ALPHA").map(\.id) } == [8], "ASCII case-insensitive title match")
        precondition(grouped[0].displayURL == "https://other.example/latest", "Display URL excludes query and fragment")
        exec("INSERT INTO history_items VALUES(12, 'https://plain.example/page?q=rad1#hidden'); INSERT INTO history_visits VALUES(13, 12, 120, NULL);")
        precondition(tryValue { try find("rad1").isEmpty }, "Untitled fallback cannot match query parameters")
        precondition(tryValue { try find("hidden").isEmpty }, "Untitled fallback cannot match fragments")
        // Equal timestamps have a stable history-item-ID tie breaker.
        exec("INSERT INTO history_items VALUES(11, 'https://other.example/latest?q=1#end'); INSERT INTO history_visits VALUES(12, 11, 90, 'New Alpha');")
        precondition(tryValue { try find("New Alpha").map(\.id) } == [11], "Deterministic timestamp tie")
        for url in ["https://www.google.com/search?q=rad1", "https://google.co.uk/search?q=test",
                    "https://www.google.rs/search?tbm=isch&q=test", "https://google.com.au/webhp#q=test",
                    "https://google.com/?q=test", "https://www.google.com/#q=test",
                    "https://images.google.com/search?q=test"] {
            precondition(HistoryStore.isGoogleSearchURL(url), "Exclude Google search: \(url)")
        }
        for url in ["https://docs.google.com/document/d/123", "https://drive.google.com/drive/search?q=test",
                    "https://www.google.com/about", "https://example.com/search?q=google",
                    "https://google.com.example.org/search?q=test", "https://www.google.com/"] {
            precondition(!HistoryStore.isGoogleSearchURL(url), "Preserve ordinary pages: \(url)")
        }
        exec("""
        INSERT INTO history_items VALUES
        (20, 'https://www.google.com/search?q=needle'),
        (21, 'https://www.google.co.uk/search?q=needle'),
        (22, 'https://docs.google.com/document/d/needle');
        INSERT INTO history_visits VALUES
        (20, 20, 200, 'needle - Google Search'),
        (21, 21, 210, 'needle - Google Search'),
        (22, 22, 220, 'needle document');
        """)
        precondition(tryValue { try find("needle").map(\.id) } == [22], "Exclude search history but keep Google Docs")
        precondition(tryValue { try find("Google Search").isEmpty }, "Search titles cannot reintroduce excluded URLs")
        precondition(tryValue { try find("").allSatisfy { !HistoryStore.isGoogleSearchURL($0.url) } }, "Recent history also excludes Google searches")
        // Test SQLite's actual read-only enforcement, not just query_only.
        var readOnly: OpaquePointer?
        precondition(sqlite3_open_v2(path, &readOnly, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        precondition(sqlite3_exec(readOnly, "DELETE FROM history_items", nil, nil, nil) == SQLITE_READONLY)
        sqlite3_close(readOnly)
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        let walBefore = try Data(contentsOf: URL(fileURLWithPath: path + "-wal"))
        _ = try find("example")
        precondition(tryValue { try Data(contentsOf: URL(fileURLWithPath: path)) } == before, "Main database unchanged")
        precondition(tryValue { try Data(contentsOf: URL(fileURLWithPath: path + "-wal")) } == walBefore, "WAL content unchanged")
        do {
            _ = try HistoryStore(path: folder.appendingPathComponent("missing.db").path).search("", ticket: SearchTicket())
            fatalError("Missing DB must fail")
        } catch is HistoryError { }
        precondition(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("missing.db").path))
        print("PASS: URL grouping, latest title/full URL, literal search, Google exclusion, ordering, cancellation, WAL visibility, read-only access and missing-file handling")
    }
    static func tryValue<T>(_ body: () throws -> T) -> T { try! body() }
}
