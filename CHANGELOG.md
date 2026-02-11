# Changelog

## 1.4.1

Fixes:
- Clipboard search field now always receives focus when the clipboard is shown via hotkey (#16)

## 1.4.0

Features:
- Syntax theme picker — choose from 9 curated highlight.js themes in Settings → Appearance: Atom One, Catppuccin, GitHub, Gruvbox, IntelliJ / Darcula, Itsypad (default), Stack Overflow, Tokyo Night, Visual Studio
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
