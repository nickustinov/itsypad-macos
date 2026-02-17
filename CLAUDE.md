# Itsypad

macOS scratchpad and clipboard manager. Swift, AppKit, SwiftUI.

## Build

```bash
xcodegen generate
xcodebuild -scheme itsypad -configuration Debug build
xcodebuild -scheme itsypad -configuration Debug test
```

Always run `xcodegen generate` after changing `project.yml` or adding/removing source files.

## Project structure

- `Sources/` – app code (App, Editor, Clipboard, Settings, Hotkey, Resources)
- `Tests/` – unit tests (295 tests)
- `Packages/Bonsplit/` – local Swift package for split panes and tab bar
- `scripts/` – build and translation scripts
- `project.yml` – XcodeGen project definition

## Localization

All user-facing strings use `String(localized:defaultValue:)` with structured keys:

```swift
String(localized: "menu.file.new_tab", defaultValue: "New tab")
```

Key format: `{area}.{context}.{name}` – e.g. `menu.file.*`, `alert.save_changes.*`, `settings.general.*`, `clipboard.*`, `toolbar.*`, `tab.context.*`, `time.*`, `update.*`, `accessibility.*`.

After adding new strings:
1. Build (Xcode populates `Sources/Resources/Localizable.xcstrings`)
2. `scripts/push-translations.sh` (push English to Lokalise)
3. Translate in Lokalise
4. `scripts/pull-translations.sh` (pull translations back)

Lokalise config: `lokalise.yml` (gitignored). Copy from `lokalise.yml.example`.

## Distribution

Two schemes from one codebase:
- `itsypad` (Debug/Release) – direct/DMG with `itsypad-direct.entitlements`
- `itsypad-appstore` (Debug-AppStore/Release-AppStore) – App Store with `itsypad.entitlements`, sets `APPSTORE` compilation condition

## Conventions

- Version in `project.yml`: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
- European-style titles, not American Title Case
- En dashes (–), not em dashes (—)
