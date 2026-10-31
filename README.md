# Safari Quick Search 1.6

A small native macOS app with no menu-bar or Dock icon. Press **Option–Command–N** for a floating, Spotlight-style search panel. Search local Safari history, navigate to a typed or pasted web address, or search Google. Matching open Safari tabs are selected without requesting a reload. Optional **Launch at Login** is available in the gear menu. Built with AppKit and SwiftUI; SQLite comes with macOS. Requires macOS 13 or later. No third-party dependencies.

## Appearance

On macOS 26 and later, the floating panel uses Apple's native [Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) material with rounded corners. Older supported macOS versions use a translucent material fallback with a subtle edge highlight. Selection and hover use restrained tinted highlights. Reduce Transparency switches to an opaque surface, Increase Contrast strengthens selection, and Reduce Motion disables highlight animations. The AppKit window remains transparent and supplies the window shadow.

The gear icon brightens on hover and has a rounded hover background. The panel appears on the screen containing the pointer.

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

The app is created at `build/Safari Quick Search.app` for your Mac's architecture. Move it into Applications and launch it from Finder. The script builds for the current Mac and uses local ad-hoc signing; it does not notarize the app. The Xcode project enables Hardened Runtime and includes the Apple Events entitlement; the command-line script currently signs without those Xcode settings. Prefer the Xcode build for the configured Automation flow.

## Full Disk Access

Safari history normally lives at:

```text
~/Library/Safari/History.db
```

macOS protects this location. In **System Settings → Privacy & Security → Full Disk Access**, click **+**, select the installed **Safari Quick Search.app**, and turn its switch on. Quit and reopen the app afterward. The search panel’s **Options (gear) → Full Disk Access Setup…** command explains this and opens Settings; the app cannot grant itself access.

**Full Disk Access is broader than this app needs:** it can permit access to protected data from other apps too. macOS does not scope this grant to Safari history. This source uses it only for the selected history database. There is no telemetry, remote search-suggestion service, history export, or persistent search index. Site-icon requests are described below. The custom database path is saved in app preferences; macOS manages login-item registration separately. Search text and results are cleared when the panel closes. You can revoke access in Settings at any time.

Grant access to the installed app, rather than broadly granting it to Terminal or Xcode. Ad-hoc rebuilds or moving the app may invalidate its permission identity; if access stops working, remove the old entry, add the new installed copy, and relaunch. Managed Macs may restrict this setting, and wording can vary with macOS versions. The shortcut uses `RegisterEventHotKey`; no Accessibility or Input Monitoring permission is needed. Allow Automation access to Safari when prompted to select an existing tab with the exact same URL without reloading it. If no matching tab is found or Automation access is denied, the URL opens normally through `NSWorkspace`. Matching includes the query and fragment; Safari may itself restore discarded tabs when selected.

Apple's explanation of [Privacy & Security settings](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac) describes the scope of Full Disk Access.

## Use

- **Option–Command–N:** show or hide the panel. Launching the app or reopening it from Finder also shows the panel.
- Type or paste text to search history titles and URLs. Every edit starts a background search without a debounce; superseded searches are cancelled and their results discarded.
- **↑ / ↓:** select a suggestion, wrapping at either end. **Return** or clicking a row opens its destination in Safari. The first row is selected when results refresh.
- **Escape**, clicking another window, or toggling the shortcut closes the panel and clears the query and results.
- The gear menu contains **Launch at Login**, Full Disk Access setup, database selection/reset, and Quit. Quitting stops the global shortcut until the next launch.

### Suggestions and URL navigation

An empty query shows up to 20 recent history title groups. A nonblank query filters those groups by displayed title and representative URL, ordered by latest visit. Google search-results history is excluded; other Google pages such as Docs and Drive remain eligible.

Typing or pasting a recognized web address adds **Navigate to URL** as the first row, even if history is unavailable. Its subtitle shows the full destination, including query and fragment. HTTP and HTTPS addresses are supported. Bare dotted hosts such as `example.com/path` and `localhost` receive an HTTPS prefix. Leading/trailing whitespace is trimmed; input with internal whitespace, embedded credentials, or an unsupported scheme stays a search. Detection checks address syntax, not whether the site exists. There is no LinkPresentation title or page-preview fetch.

A **Search: <input>** Google action appears for every nonblank query:

| Input | With history matches | Without history matches |
| --- | --- | --- |
| Ordinary text | First history match, Google, remaining matches | Google |
| Recognized URL | Navigate to URL, first history match, Google, remaining matches | Navigate to URL, Google |

Selecting a history group uses its most recently visited full URL, including query and fragment. History subtitles omit those components. Navigation and Google actions remain available when reading history fails.

### Existing Safari tabs

All destinations use Safari, regardless of the default browser. If Safari is running, the app checks its script-accessible windows and tabs for an exact, case-sensitive full-URL match, including query and fragment. The first matching tab is selected, its window is unminimized and brought forward, and Safari is activated. The app does not assign the tab's URL or request a reload; Safari may itself reload a discarded tab.

Allow **Safari Quick Search → Safari** in **System Settings → Privacy & Security → Automation** when prompted. If Safari is not running, no tab matches, permission is denied, or scripting fails or times out, the app opens the URL normally. Safari then decides whether to use a new window or tab. The app does not target a specific Safari profile or search open tabs as a separate source of suggestions. Selecting a history database does not select a browser profile.

### Launch at Login

Enable **Options (gear) → Launch at Login** from the installed app copy. This registers the main app with macOS using `SMAppService`; disabling the toggle unregisters it. It is not automatically enabled on first launch.

If macOS requires approval, the app opens Login Items settings and shows **Approve in Login Items Settings…** in the gear menu. The toggle is checked only when macOS reports the item as enabled; status refreshes when the panel opens or the search refreshes. Registration failures appear in an alert.

Login launches show the search panel just like a manual launch; there is no silent startup mode. Quitting the app does not turn off its login registration. Use one installed copy consistently and manage approval in **System Settings → General → Login Items**.

### Network activity and icons

Typing does not request internet search suggestions. Choosing the Google row opens its search URL or selects an existing matching tab. Visible rows request icons from each destination's HTTPS `/favicon.ico`, including Google for its search row. Requests omit the entered search text, visited path, query, fragment, cookies, and credentials. They disclose the requested hostname and your IP address; redirects may contact another host.

Icons and failed lookups are cached only in memory. Missing icons use a globe or search symbol. Sites that declare only custom icons in HTML may show the placeholder. No page metadata is fetched.

## Database safety and search details

`HistoryStore.swift` opens a fresh connection with `SQLITE_OPEN_READONLY`, checks `sqlite3_db_readonly`, and also sets `PRAGMA query_only = ON`. It uses a prepared query with `sqlite3_bind_text`; no user text is interpolated into SQL. `%`, `_`, and backslashes are escaped so they match literally. Results are capped at 20; busy waits are capped at 150 ms and the SQLite progress handler interrupts long-running work after approximately two seconds. An existing filesystem operation may still take longer than that deadline.

The app reads Safari's live database with SQLite's normal transaction and WAL handling. It never changes Safari tables, runs migrations, checkpoints the database, changes journal mode, or copies a live `History.db` in isolation. It does **not** use `immutable=1`, since Safari's database changes while the browser runs. Read-only protects database content; SQLite may still coordinate through or create WAL/shared-memory sidecar files as required by its own locking protocol. See SQLite's [read-only WAL documentation](https://www.sqlite.org/wal.html#read_only_databases) and [open flags](https://www.sqlite.org/c3ref/open.html).

The implementation expects Safari's `history_items(id, url)` and `history_visits(id, history_item, visit_time, title)` tables. That is an internal, undocumented Safari schema and can change. Unsupported schemas produce an error while Google and recognized-URL navigation remain available. Private browsing and removed history cannot be recovered by this app.

Each URL uses its newest nonempty title as `titleText` (or its URL without query parameters/fragments when untitled). Rows are grouped by exact, case-sensitive `titleText`, with the latest full URL retained for navigation. Matching uses only the group’s displayed title and latest URL without query parameters or fragments. Past titles, older group URLs, query parameters, fragments, and other history data cannot produce matches. The subtitle shows the same URL without parameters/fragments. Equal visit times are resolved by descending history-item ID. Built-in SQLite LIKE is case-insensitive for ASCII; full Unicode case folding/accent folding is not implemented. Unicode exact substrings work. Searches scan history and can time out on unusually large databases; this design deliberately avoids maintaining a second sensitive index.

## Profiles and troubleshooting

Use **Choose History Database…** in the panel’s gear menu to select another Safari profile's `History.db`, or a consistent SQLite backup with the same schema. The default database does not necessarily include all Safari profiles. Profile locations can vary; the app does not crawl your Library to discover them. In the file picker, Command–Shift–G lets you enter a known folder. **Use Default Safari Database** resets the choice.

- **Cannot read history:** confirm the selected file exists, grant access to the correct app copy, and relaunch. If SQLite cannot use the live database's sidecars, try again with Safari open; do not delete or edit its database files.
- **Search failed / busy:** retry. A changed Safari schema may require adapting the SQL in `HistoryStore.swift`.
- **Shortcut unavailable:** another app may have claimed Option–Command–N. Reopen the app from Finder, change the other app's shortcut, or edit the key/modifier constants in `GlobalHotKey.register()` in `App.swift` and rebuild. This version has no shortcut recorder.
- **An existing tab is not selected:** check Automation access for the installed app and compare the full URLs, including query and fragment. A redirect or a differently formatted URL can prevent an exact match; scripting failures fall back to normal opening.
- **Launch at Login is unchecked:** look for pending approval in Login Items settings. Run the installed copy, retry the toggle, and review any registration error shown by the app.
- **Permission settings link does not work:** navigate to Privacy & Security → Full Disk Access manually.

## Verification

`./test.sh` creates and removes an isolated synthetic Safari-shaped SQLite database. It verifies Google search-history exclusion while retaining other Google pages; exclusion of query parameters, fragments and old titles/URLs; no-match behavior; Google row ordering and destination; title/URL matching; recency, title grouping, newest full-URL selection, timestamp ties, untitled pages, quotes, injection-like strings, literal wildcard escaping, Unicode substrings, pre-cancellation, visibility of uncheckpointed WAL entries, rejection of writes through a read-only connection, unchanged database/WAL contents after search, and failure without file creation for a missing database. It never reads real Safari history.

The current source has built successfully in Xcode. The database checks above describe the existing test script; they do not verify real Safari Automation, login registration, or visual appearance. URL detection and suggestion ordering were also checked with a temporary Xcode snippet. Interactive behavior needs a local smoke test:

1. Install and launch; grant Full Disk Access and relaunch.
2. Search a known page, use arrow keys, and press Return.
3. Try ordinary text with and without history matches; verify Google ordering against the table above.
4. Paste a full URL and a bare domain; verify the navigation row stays first and preserves query/fragment.
5. Open a matching Safari tab, change its scroll position, then select that URL in the app. Allow Automation and confirm the existing tab is focused with its page state preserved.
6. Try a URL with no matching tab and verify normal Safari opening.
7. Enable and disable Launch at Login, including any pending approval. Verify a login launch separately.
8. Check paste, Escape, click-away, shortcut toggle, a full-screen Space, gear hover, and accessibility display settings.

## Files

- `Sources/App.swift`: background app lifecycle and panel options, global hotkey, floating AppKit panel and setup.
- `Sources/SearchView.swift`: SwiftUI panel, gear-menu settings, site icons, and AppKit text field/keyboard handling.
- `Sources/SearchModel.swift`: asynchronous history searches, suggestion ordering, URL detection, Safari tab selection/opening, and login-item registration.
- `Sources/HistoryStore.swift`: read-only parameterized SQLite access.
- `Tests/HistoryStoreTests.swift`: isolated database checks.
- `SafariQuickSearch.xcodeproj`: shared Xcode scheme, local signing, Hardened Runtime, no third-party dependencies.
- `SafariQuickSearch.entitlements`: Apple Events entitlement for Safari Automation.
- `Info.plist`: app identity, minimum OS version, accessory-app behavior, and Automation permission explanation.
- `build.sh`, `test.sh`: command-line build and database tests.
