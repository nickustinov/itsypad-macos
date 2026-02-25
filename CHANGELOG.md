# Changelog

## 1.9.6

Features:
- Middle-click on a tab to close it (#55)

Fixes:
- Fixed files not opening when launched via `open -a Itsypad file.txt` with the app not running (#52)
- Fixed oversized dock icon on macOS Sequoia and Sonoma (#58)

## 1.9.5

Features:
- Menu bar icon now shows the window directly when Itsypad is hidden, and shows the menu only when the window is already active (#47)

## 1.9.4

Fixes:
- Fixed the app occasionally jumping to the foreground with no user interaction – the window restore logic now only activates when the frontmost app terminates, not background processes (#51)
- Fixed clearing the global shortcut not persisting across app restarts – the default triple-tap shortcut would silently reappear on relaunch (#50)

## 1.9.3

Features:
- The app now moves to the currently active desktop when activated via the hotkey, instead of switching back to the desktop where it was last visible

## 1.9.2

Features:
- Added a welcome tab with a markdown checklist on first launch to help new users discover features

## 1.9.1

Fixes:
- Fixed markdown preview showing a blank panel when toggled on a file tab – the sandbox blocked writing the temp HTML file next to the user's document; now writes to the app container instead

## 1.9.0

Features:
- Localization – the app is now fully localized in 12 languages: English, Spanish, French, German, Russian, Japanese, Simplified Chinese, Traditional Chinese, Korean, Portuguese (Brazil), Italian, and Polish

## 1.8.3

Fixes:
- Fixed tabs and clipboard history lost when switching from the direct-download version (≤1.6.0) to the App Store version – legacy iCloud KVS data is now imported on first launch

## 1.8.2

Fixes:
- Fixed pinned tabs not persisting between app restarts – pin state is now saved to the session file and restored on launch
- Fixed local tabs being overwritten or deleted by stale CloudKit data during first sync after upgrade from 1.6.0 to 1.8.x – local state is now treated as authoritative until the first sync cycle completes
- Fixed tabs and clipboard history lost when upgrading from 1.6.x to 1.8.x – session data is now migrated from the non-sandboxed path to the sandboxed container on first launch

## 1.8.1

Features:
- Added pin/unpin tab option to the tab context menu – pinned tabs stay fixed at the right end of the tab bar, with Clipboard always rightmost

Fixes:
- Pinned the Clipboard tab so it always stays visible at the right end of the tab bar (#38)

## 1.8.0

Features:
- Added Help menu with links to the Itsypad website, release notes, and issue tracker
- Added Labs settings tab with Even Realities G2 glasses sync

## 1.7.1

Features:
- Frontmatter support – YAML frontmatter blocks (`---` delimited) at the top of markdown files are now stripped from the rendered preview instead of being rendered as broken HTML (#32)

## 1.7.0

Features:
- Migrated iCloud sync from NSUbiquitousKeyValueStore to CloudKit with CKSyncEngine – per-record incremental sync replaces full-data rewrites, no practical size limit, native deletion handling (no more tombstones)
- Clipboard sync limit removed – all 1,000 entries now sync (was capped at 200 due to KVS 1MB limit)
- Added App Store distribution support with dual entitlements and scheme configuration

## 1.6.1

Fixes:
- Fixed plain text with common English words (`this`, `is`) being false-positive highlighted as Kotlin or C#

## 1.6.0

Features:
- Auto-delete clipboard history – configurable interval (1 hour to 30 days) in Settings → Clipboard → History; prunes expired entries on launch, periodically, and on setting change; syncs deletions to iCloud
- Added Solarized syntax theme (light and dark variants)
- Cross-device clipboard delete/clear – deleting or clearing clipboard entries now syncs across devices via tombstones (`deletedClipboardIDs`), matching the existing tab tombstone pattern

Fixes:
- Fixed clicking the same clipboard entry repeatedly creating duplicate entries at the top of the list
- Fixed clipboard duplicates caused by Universal Clipboard round-trip – merge now skips cloud entries whose text already exists locally

## 1.5.1

Fixes:
- Fixed tab content disappearing after closing a split pane on macOS 14 and 15 (#24)
- Fixed plain text (emails, short notes) being false-positive highlighted as Swift

## 1.5.0

Features:
- Markdown preview – toggle a side-by-side rendered preview for `.md` tabs via View → Toggle preview (⇧⌘P) or the toolbar button; live-updates as you type, uses the active syntax theme for code block highlighting, renders local images, opens links in the default browser
- iCloud sync now includes clipboard history – text-only entries sync across devices via the same iCloud KV store used for scratch tabs
- Unified sync manager (`ICloudSyncManager`) replaces the previous per-store sync orchestration

## 1.4.5

Fixes:
- Fixed ghost line appearing at the bottom of the editor when deleting text with backspace (word-wrap redraw regression)
- Fixed email addresses triggering false syntax highlighting (e.g. `@domain` highlighted as Swift)

## 1.4.4

Features:
- Configurable line spacing and letter spacing in Settings → Editor (#19)

Fixes:
- Fixed plain text (emails, notes) being false-positive syntax highlighted due to common English words overlapping programming keywords

## 1.4.3

Fixes:
- Theme now updates when switching macOS appearance while set to "system" (#20)
- Clickable URLs no longer include trailing punctuation from markdown links (#18)
- Language auto-detection on paste now works reliably — removed brittle custom heuristics in favour of highlight.js auto-detect restricted to supported languages
- Detected language now propagates to the syntax highlighter (was silently dropped before)
- Fixed thread safety issue between language detection and syntax highlighting

## 1.4.2

Fixes:
- Clipboard view mode (grid/panels) now updates immediately when changed in settings
- Removed GitHub syntax theme (rendering glitches)

## 1.4.1

Fixes:
- Clipboard search field now always receives focus when the clipboard is shown via hotkey (#16)
- Window no longer pops to front when quitting another app while dock icon is visible (#17)

## 1.4.0

Features:
- Syntax theme picker — choose from curated highlight.js themes in Settings → Appearance: Atom One, Catppuccin, Gruvbox, IntelliJ / Darcula, Itsypad (default), Stack Overflow, Tokyo Night, Visual Studio
- Each theme has dark and light variants that switch automatically with system appearance

Fixes:
- Theme switching — appearance changes (dark → light) now update editor content immediately instead of requiring a manual theme re-select
- Clipboard background now matches the active syntax theme
- Indenting a numbered list item with Tab resets the number to 1 (new sub-list)

## 1.3.0

Features:
- Always on top — pin the window above all other windows via View → Always on top (⇧⌘T)
- Check for updates — "Check for updates..." in the app menu and status bar menu checks GitHub releases and shows an alert when a new version is available
- Tab switching shortcuts — ⌘1–9 to jump to tabs by position in the editor (excludes clipboard tab)
- Split pane shortcuts — ⇧⌘D to split right, ⇧⌃⌘D to split down
- Clickable links — URLs in plain text and markdown tabs are highlighted and underlined; click to open in browser
- Clipboard settings tab — dedicated settings pane for all clipboard options, moved out of General
- Grid/panels toggle — switch between grid tiles and full-width panel rows in clipboard view
- Configurable preview lines — adjust how many lines of text are shown in clipboard cards (1–20)
- Configurable font size — adjust clipboard card text size (8–24pt)
- Keyboard navigation — arrow keys to move between clipboard items, Enter to copy, Space to preview, Escape to deselect
- Preview navigation — arrow keys change the previewed item while the overlay is open, Space toggles it closed
- Quick-access shortcuts — ⌘1–9 to copy the Nth visible item, ⌥1–9 to copy and paste it into the previously active app
- Default action setting — choose whether clicking or pressing Enter copies to clipboard (default) or pastes into the active app

Improvements:
- Editor performance — reduced input lag by limiting layout recalculation to visible range, tracking line highlight range instead of full-document attribute removal, and debouncing language detection

## 1.2.0

Features:
- Lists and checklists — bullet lists (`- `, `* `), numbered lists (`1. `), and checklists (`- [ ] `, `- [x] `) with auto-continuation on Enter, empty-item exit, Tab/Shift+Tab indent/outdent, Cmd+Return to toggle checkboxes, clickable checkboxes, Cmd+Shift+L to convert lines to/from checklists, Cmd+Option+Up/Down to move lines, strikethrough+dimmed styling for checked items, and wrapped-line alignment past the bullet

## 1.1.0

Improvements:
- Replaced Highlightr and tree-sitter with a lightweight custom highlight.js wrapper — fixes broken syntax coloring from compound CSS selectors in highlight.js v11, now correctly highlights all 185+ languages
- Language detection now uses highlight.js auto-detect as the primary content-based detector, replacing brittle hand-written scoring heuristics
- Added zoom preview for clipboard tiles — hover a tile and click the magnifying glass icon to view full content in a near-fullscreen overlay with rounded corners, scrollable text, and a copy button
- Added promotion section for other macOS apps
- Enabled window minimize (yellow traffic light button)
- Added standard Hide (Cmd+H), Hide others (Option+Cmd+H), and Show all menu items

Bug fixes:
- Fixed dock icon appearing when window is active even with "show in dock" disabled
- Fixed drag-and-drop files to dock icon not opening them (missing document type declarations)
- Fixed plain text being misdetected as code when mentioning keywords like `#include` or `:=`
- Fixed Python code starting with `import` not being detected as Python
- Fixed I-beam cursor appearing on clipboard tiles

## 1.0.5 (unreleased)

Improvements:
- Added zoom preview for clipboard tiles — hover a tile and click the magnifying glass icon to view full content in a near-fullscreen overlay with rounded corners, scrollable text, and a copy button

## 1.0.4

Bug fixes:
- Fixed plain text with bullet dashes being misdetected as markdown
- Removed iCloud debug logging

## 1.0.3

Bug fixes:
- Fixed inactive pane colors in split view — unfocused split panes now keep their themed tab bar color instead of turning gray; only the accent strip on the selected tab desaturates in unfocused panes

## 1.0.2

Bug fixes:
- Fixed clicking in editor area not switching active pane in split view
- Fixed clipboard tab jumping to a different pane after app restart

## 1.0.1

Bug fixes:
- Fixed dock icon click not showing window after hotkey hide
- Fixed app not launching from Finder (missing NSPrincipalClass)
- Fixed iCloud sync not updating tabs in the UI when changes arrived from another device
- Fixed iCloud sync toggle not persisting across app restarts
- Fixed editing conflict where two devices would overwrite each other's changes
- Fixed closed tabs reappearing after being deleted on another device
- Fixed line numbers not rendering when tab content was updated via iCloud sync

Improvements:
- Split pane layout now persists and restores across app restarts
- iCloud sync now fetches latest data when the app becomes active
- iCloud sync now pulls existing cloud data immediately when first enabled
- Added "Last synced" indicator in settings when iCloud sync is enabled

## 1.0.0

Initial release.
