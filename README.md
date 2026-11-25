# Safari Quick Search

> **Personal Quality-of-Life Vibecoded Tool** — This is a personal, vibe-coded quality-of-life utility built for daily Safari workflows on macOS 26 (Tahoe) or later.

Safari Quick Search adds a Spotlight-style Liquid Glass quick-switcher panel for Safari's live open tabs, browsing history, direct URLs, and Google searches—plus an interactive 3-finger trackpad scrub gesture to switch between Safari Tab Groups with magnetic detent feedback.

---

## Functions & Features

### 1. Global Quick Search Panel (`⌥⌘N`)
- **Summon & Dismiss Anywhere**: Press **`⌥⌘N`** globally to toggle the floating panel from any app or full-screen Space. Press **`Esc`** or click outside the panel to dismiss it.
- **Live Open Tabs First**: Reads live open Safari windows via AppleScript and enriches them with profile and Tab Group metadata from `SafariTabs.db`. Matching open tabs are surfaced ahead of history items.
- **Deduplicated History Search**: Queries `History.db` in read-only mode (up to 20 recent matches), grouping entries by base URL (stripping query strings and fragments) and filtering out Google search results pages while keeping Google Docs/Drive/etc.
- **Smart Address & Google Search Actions**:
  - Typing a valid domain or HTTP(S) address inserts a **Navigate to URL** action at the top.
  - Typing any phrase offers an instant **Search Google** action.
- **Safari Navigation & Window Z-Order**:
  - Selecting an **opened tab** (`↩` or click) activates Safari, raises the frontmost matching on-screen window, and switches directly to that tab.
  - Holding **`⌘↩`** on an opened tab opens a fresh duplicate tab in Safari's frontmost on-screen window instead of switching to the existing one.
  - Selecting a **history item**, **URL**, or **Google search** opens it in a new tab in Safari's frontmost on-screen window (or opens a new Safari window if none exists).
- **Floating Profile & Tab Group Inspector**:
  - Hovering or keyboard-selecting an open-tab row displays a gliding Liquid Glass badge showing which Safari Profile and Tab Group own that tab.
  - Press **`⌥⇥` (Option-Tab)** while the panel is active to toggle between showing only matching profiles/groups vs. all open Safari profiles and tab groups.
  - Keyboard-selected rows scrolled above or below the viewport pin to the top or bottom edge as a sticky Liquid Glass card.
- **Options Menu**: The top-right gear button provides manual **Refresh**, **Launch at Startup** (via `SMAppService`), and **Quit**.

### 2. Three-Finger Trackpad Tab Group Scrubbing
- **Interactive Liquid Glass HUD**: When Safari is the frontmost app, swiping horizontally with **three fingers** presents a centered Liquid Glass multivalue toggle bubble over Safari's active window.
- **Magnetic Detents & Haptics**: Scrubbing across segments applies elastic pull resistance, `.alignment` trackpad haptic snaps, and seamless wraparound across the first and last Tab Groups.
- **Instant Commit & Live Panel Refresh**: Releasing your fingers switches Safari to the highlighted Tab Group (via macOS Shortcuts, falling back to Safari's `Window` menu) and automatically refreshes the search panel's tab rows if the panel is open.

---

## Requirements to Run

1. **Operating System**: **macOS 26.0** or later (uses native SwiftUI Liquid Glass APIs).
2. **Safari**: Safari must be installed (used for live tab inspection, navigation, and Tab Group switching).
3. **macOS Permissions** (*System Settings → Privacy & Security*):
   - **Full Disk Access** *(Required)*: Needed to read `~/Library/Safari/History.db` and `~/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db` in read-only mode. Quit and reopen the app after granting.
   - **Automation** *(Required)*: Allow Safari Quick Search to control **Safari** (reading/selecting tabs), **Shortcuts Events** (fast Tab Group switching), and **System Events** (menu-bar fallback for Tab Group switching).
   - **Accessibility** *(Required for 3-finger swipe & window raising)*: Needed so the `CGEvent` tap can intercept horizontal 3-finger swipes before Safari navigates Back/Forward, and so `AXRaise` can bring the target Safari window to the front.
4. **Trackpad Settings** *(For 3-finger Tab Group gesture)*:
   - In *System Settings → Trackpad → More Gestures*, enable three-finger horizontal swiping (e.g., set **Swipe between pages** to *Swipe with Three Fingers* or *Swipe with Two or Three Fingers*, and avoid conflicting 3-finger Mission Control/Spaces assignments).
5. **Apple Shortcut** *(Recommended for direct Tab Group jumping)*:
   - Create a shortcut in the macOS **Shortcuts** app named **`Open Safari Tab Group 3`** that accepts **Text** input and runs Safari's **Open Tab Group** action matching that name.
   - If this shortcut is not installed, the app automatically falls back to clicking `Window → Go To Previous/Next Tab Group` in Safari's menu bar.

---

## Build & Run

### Development (Xcode)
Open `SafariQuickSearch.xcodeproj` in Xcode, select **SafariQuickSearch → My Mac**, and press **Run (`⌘R`)**.
- Debug builds output **`Safari Quick Search Dev.app`** so development builds stay distinct from your installed copy.

### Production Build (`build.sh`)
Build an optimized release bundle from the terminal:

```sh
./build.sh
```

Move `build/Safari Quick Search.app` to `/Applications` and launch it. Keep only **one** instance running at a time so global hotkeys, swipe taps, and macOS permissions target the same binary.

---

## Keyboard & Gesture Reference

| Input | Scope | Action |
| :--- | :--- | :--- |
| **`⌥⌘N`** | Global | Show or hide the Safari Quick Search panel |
| **`↑` / `↓`** or **`⇥` / `⇧⇥`** | Panel | Move selection through results (wraps around) |
| **`↩`** | Panel | Switch to selected open tab, or open history / URL / search in Safari |
| **`⌘↩`** | Panel | Force-open selected item in a new tab in Safari's frontmost window |
| **`⌥⇥`** | Panel | Toggle profile badge between matched Tab Groups and all open windows |
| **`Esc`** / Outside Click | Panel | Hide the panel |
| **3-Finger Horizontal Swipe** | Safari Focused | Scrub and switch Safari Tab Groups via the Liquid Glass bubble |

---

## Architecture Notes

Core subsystems are decoupled behind `*Interface` protocols and wired in `Sources/App.swift` so alternative implementations remain preserved and swappable in one place:
- **Panel Actions**: `AppActionsInterface` (`AppActions`)
- **Tab Supply & Ranking**: `TabSupplierInterface` (`TabSupplier` + `LiveTabStore` + `HistoryStore` + `AppleScriptTabSupplier` + `TabStore`)
- **Tab Selection Actions**: `TabActionInterface` (`SafariTabActions`, or `TabActions` for debug inspection alerts)
- **Tab Group Metadata**: `TabGroupsInterface` (`SafariTabGroups`)
- **Swipe Handling & Monitoring**: `SafariSwipeHandlerInterface` (`BubbleSafariSwipeHandler` / `DiscreteSafariSwipeHandler`), `SwipeScrubMonitorInterface` (`SystemSwipeScrubMonitor`), `SwipeMonitorInterface` (`SystemSwipeOnReleaseMonitor` / `SystemSwipeEventMonitor` / `ThreeFingerSwipeMonitor`), and `SafariTabGroupSwitcherInterface` (`ShortcutTabGroupSwitcher` / `SafariControl`).

