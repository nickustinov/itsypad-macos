# Changelog

## 1.0.5

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
