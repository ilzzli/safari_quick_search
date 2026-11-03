# Safari Quick Search

Just a vibe-coded personal quality-of-life tool for Safari on macOS 26 or later.

- **⌥⌘N** shows or hides the panel from anywhere in macOS.
- Search up to 20 recent Safari history results as you type.
- Results are grouped by URL without query parameters or fragments. Google search pages are excluded.
- Click outside the panel to hide it.
- Use the gear menu to enable Launch at Startup or quit.

## Run

Open `SafariQuickSearch.xcodeproj` in Xcode, select **SafariQuickSearch → My Mac**, and press **Run**. Debug builds are named **Safari Quick Search Dev.app**.

Or build the production app:

```sh
./build.sh
```

Move `build/Safari Quick Search.app` to Applications and launch it. Keep only one copy running.

Grant the app **Full Disk Access** in **System Settings → Privacy & Security** to read Safari history, then quit and reopen it.

## Use

Type in the search field to filter history by title or URL. Clearing it restores recent history. Results remain visible and dimmed while refreshing.

The current version displays history only; opening results and gesture controls are not implemented.
