# Changelog

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
