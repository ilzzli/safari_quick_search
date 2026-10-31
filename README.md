# Safari Quick Search 1.6

A small native macOS app with no menu-bar or Dock icon. Press **Option–Command–N** for a floating, Spotlight-style search panel. Built with AppKit and SwiftUI; SQLite comes with macOS. Requires macOS 13 or later. No third-party dependencies.

## Appearance

On macOS 26 and later, the floating panel uses Apple's native [Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) material with rounded corners. Older supported macOS versions use a translucent material fallback with a subtle edge highlight. Selection and hover use restrained tinted highlights. Reduce Transparency switches to an opaque surface, Increase Contrast strengthens selection, and Reduce Motion disables highlight animations. The AppKit window remains transparent and supplies the window shadow.

The new appearance is compile-checked; its live translucency and desktop blending still need a local visual check on your Mac.

## Build and run

### Xcode

1. Open `SafariQuickSearch.xcodeproj` in Xcode 26 or later.
2. Select the **SafariQuickSearch** scheme and **My Mac**, then press Run.
3. For normal use, find **Safari Quick Search.app** under Products (Show in Finder), quit the running copy, and copy the app into `/Applications` or `~/Applications`.
4. Launch that installed copy and grant it Full Disk Access as below. Use one installed copy consistently.

The project uses local ad-hoc signing, so no paid developer account or signing team is required for local use. It intentionally has App Sandbox disabled to read Safari's protected database. To distribute a trusted release, configure your own Developer ID signing and notarization.

### Without opening Xcode

With Apple's command-line developer tools and the macOS 26 SDK or later installed, run from this folder:

```sh
./build.sh
./test.sh
```

The app is created at `build/Safari Quick Search.app` for your Mac's architecture. Move it into Applications and launch it from Finder. The separately supplied prebuilt app is **Apple silicon only**, locally ad-hoc signed, and **not notarized**. Building the source yourself is the recommended route if macOS blocks the downloaded app. Do not disable Gatekeeper globally.

## Full Disk Access

Safari history normally lives at:

```text
~/Library/Safari/History.db
```

macOS protects this location. In **System Settings → Privacy & Security → Full Disk Access**, click **+**, select the installed **Safari Quick Search.app**, and turn its switch on. Quit and reopen the app afterward. The search panel’s **Options (gear) → Full Disk Access Setup…** command explains this and opens Settings; the app cannot grant itself access.

**Full Disk Access is broader than this app needs:** it can permit access to protected data from other apps too. macOS does not scope this grant to Safari history. This source uses it only for the selected history database. There is no telemetry, remote search-suggestion service, history export, or persistent search index. Site-icon requests are described below. Only the custom database path is saved in preferences. Search text and results are cleared when the panel closes. You can revoke access in Settings at any time.

Grant access to the installed app, rather than broadly granting it to Terminal or Xcode. Ad-hoc rebuilds or moving the app may invalidate its permission identity; if access stops working, remove the old entry, add the new installed copy, and relaunch. Managed Macs may restrict this setting, and wording can vary with macOS versions. The shortcut uses `RegisterEventHotKey`; no Accessibility or Input Monitoring permission is needed. Allow Automation access to Safari when prompted to select an existing tab with the exact same URL without reloading it. If no matching tab is found or Automation access is denied, the URL opens normally through `NSWorkspace`. Matching includes the query and fragment; Safari may itself restore discarded tabs when selected.

Apple's explanation of [Privacy & Security settings](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac) describes the scope of Full Disk Access.

## Use

- **Option–Command–N:** show/hide the panel. Reopening the app from Finder also shows the panel. The panel’s gear menu contains database settings, permission setup, and Quit.
- Type or paste: every text edit starts a title/URL substring search on a background queue. There is no debounce. Superseded searches are cancelled and their results discarded.
- **↑ / ↓:** select a suggestion. **Return:** open it in Safari. Clicking works too.
- **Escape** or focus another window: dismiss and clear the query/results.
- Google search-results history is excluded before grouping and limiting results, including common country-domain and legacy search URLs. Other Google pages such as Docs and Drive remain eligible. The direct **Search: <input>** action remains available.
- An empty query shows recent pages. Up to 20 matching title groups appear, ordered by their latest visit. Rows with the same displayed title are combined; selecting a group opens its most recently visited full URL, including its query string and fragment.
- A direct **Search: <input>** Google option appears for every nonblank query, even when history is unavailable. It is the second row when matches exist (after the first match), and the only row when none exist. **Only choosing this row sends the query to Google**, by opening its search URL in Safari. Typing does not request internet search suggestions. Visible rows load favicons directly from each site’s HTTPS `/favicon.ico`, including Google for the direct search row. These requests disclose the site hostname and your IP address to that site, but do not send your search text, visited page URL, cookies, or credentials. Icons and failed lookups are cached in memory; unavailable icons show a globe or search placeholder. Sites that only declare a custom icon in their HTML may show the placeholder.

History and Google destinations always open in Safari, even if another browser is your default. Only HTTP/HTTPS history URLs can open. Safari decides whether to use a new window or tab based on its settings; this app does not target a particular Safari profile.

## Database safety and search details

`HistoryStore.swift` opens a fresh connection with `SQLITE_OPEN_READONLY`, checks `sqlite3_db_readonly`, and also sets `PRAGMA query_only = ON`. It uses a prepared query with `sqlite3_bind_text`; no user text is interpolated into SQL. `%`, `_`, and backslashes are escaped so they match literally. Results are capped at 20; busy waits are capped at 150 ms and the SQLite progress handler interrupts long-running work after approximately two seconds. An existing filesystem operation may still take longer than that deadline.

The app reads Safari's live database with SQLite's normal transaction and WAL handling. It never changes Safari tables, runs migrations, checkpoints the database, changes journal mode, or copies a live `History.db` in isolation. It does **not** use `immutable=1`, since Safari's database changes while the browser runs. Read-only protects database content; SQLite may still coordinate through or create WAL/shared-memory sidecar files as required by its own locking protocol. See SQLite's [read-only WAL documentation](https://www.sqlite.org/wal.html#read_only_databases) and [open flags](https://www.sqlite.org/c3ref/open.html).

The implementation expects Safari's `history_items(id, url)` and `history_visits(id, history_item, visit_time, title)` tables. That is an internal, undocumented Safari schema and can change. Unsupported schemas produce an error while Google remains available. Private browsing and removed history cannot be recovered by this app.

Each URL uses its newest nonempty title as `titleText` (or its URL without query parameters/fragments when untitled). Rows are grouped by exact, case-sensitive `titleText`, with the latest full URL retained for navigation. Matching uses only the group’s displayed title and latest URL without query parameters or fragments. Past titles, older group URLs, query parameters, fragments, and other history data cannot produce matches. The subtitle shows the same URL without parameters/fragments. Equal visit times are resolved by descending history-item ID. Built-in SQLite LIKE is case-insensitive for ASCII; full Unicode case folding/accent folding is not implemented. Unicode exact substrings work. Searches scan history and can time out on unusually large databases; this design deliberately avoids maintaining a second sensitive index.

## Profiles and troubleshooting

Use **Choose History Database…** in the panel’s gear menu to select another Safari profile's `History.db`, or a consistent SQLite backup with the same schema. The default database does not necessarily include all Safari profiles. Profile locations can vary; the app does not crawl your Library to discover them. In the file picker, Command–Shift–G lets you enter a known folder. **Use Default Safari Database** resets the choice.

- **Cannot read history:** confirm the selected file exists, grant access to the correct app copy, and relaunch. If SQLite cannot use the live database's sidecars, try again with Safari open; do not delete or edit its database files.
- **Search failed / busy:** retry. A changed Safari schema may require adapting the SQL in `HistoryStore.swift`.
- **Shortcut unavailable:** another app may have claimed Option–Command–N. Reopen the app from Finder, change the other app's shortcut, or edit the key/modifier constants in `GlobalHotKey.register()` in `App.swift` and rebuild. This version has no shortcut recorder.
- **Permission settings link does not work:** navigate to Privacy & Security → Full Disk Access manually.

## Verification

`./test.sh` creates and removes an isolated synthetic Safari-shaped SQLite database. It verifies Google search-history exclusion while retaining other Google pages; exclusion of query parameters, fragments and old titles/URLs; no-match behavior; Google row ordering and destination; title/URL matching; recency, title grouping, newest full-URL selection, timestamp ties, untitled pages, quotes, injection-like strings, literal wildcard escaping, Unicode substrings, pre-cancellation, visibility of uncheckpointed WAL entries, rejection of writes through a read-only connection, unchanged database/WAL contents after search, and failure without file creation for a missing database. It never reads real Safari history.

Version 1.6 was checked with the separately installed command-line developer tools. Its Xcode build could not be checked because the installed Xcode requires license acceptance. Earlier versions passed both builds and the automated database tests; this update changes app controls only. Interactive hotkey/focus behavior, the Full Disk Access flow, and opening a page in the user's Safari still require a local smoke test:

1. Install and launch; grant Full Disk Access and relaunch.
2. From another app, press the shortcut and type a known page title or URL.
3. Arrow through results and press Return; confirm Safari opens the selected page.
4. Repeat with a phrase that has no matches: only **Search: <input>** should appear. With matches, that row should be second. Select it and confirm the Google query.
5. Try a string present only in a URL query parameter: it should not match that history row.
6. Check paste, Escape, click-away, shortcut toggle, and a full-screen Space.

## Files

- `Sources/App.swift`: background app lifecycle and panel options, global hotkey, floating AppKit panel and setup.
- `Sources/SearchView.swift`: SwiftUI panel and AppKit text field/keyboard handling.
- `Sources/SearchModel.swift`: asynchronous searches, stale-result rejection and Safari opening.
- `Sources/HistoryStore.swift`: read-only parameterized SQLite access.
- `Tests/HistoryStoreTests.swift`: isolated database checks.
- `SafariQuickSearch.xcodeproj`: shared Xcode scheme, local signing, no dependencies.
- `build.sh`, `test.sh`: command-line build and database tests.
