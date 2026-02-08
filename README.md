# Itsypad

[![Tests](https://github.com/nickustinov/itsypad-macos/actions/workflows/tests.yml/badge.svg)](https://github.com/nickustinov/itsypad-macos/actions/workflows/tests.yml)

A tiny, native macOS text editor + clipboard manager.

![Itsypad screenshot](itsypad-screenshot-v1.png)

## Features

- **Text editor** — syntax highlighting, multi-tab, split view, find and replace
- **Clipboard manager** — 500-item history, searchable, click to copy
- **Global hotkeys** — tap left ⌥ three times to show/hide, or define your own hotkey
- **Lightweight** — nearly zero CPU and memory usage
- **Menu bar app** — show or hide in menu bar
- **Dock app** — show or hide in Dock, as you prefer
- **Open at login** — optional auto-start
- **iCloud sync** — sync scratch tabs across Macs via iCloud

## Editor
- **Multi-tab and split view** — work on multiple files/notes at once, drag to reorder
- **Syntax highlighting** — 185+ languages via tree-sitter ([CodeEditLanguages](https://github.com/CodeEditApp/CodeEditLanguages)), with automatic language detection
- **Find and replace** — built-in find bar with next/previous match and use selection for find
- **Session persistence** — all tabs, content, and cursor positions are preserved across restarts
- **Auto-save** — content is continuously saved to session, never lose your work
- **Monokai-inspired theme** — dark and light variants with system appearance support

## Clipboard manager
- **Text and images** — stores clipboard content
- **Searchable** — filter history with highlighted search matches
- **Click to copy** — click any entry to copy it back to clipboard
- **Delete entries** — remove individual items on hover
- **Separate hotkey** — assign a dedicated global hotkey to show/hide

## Install

```bash
brew install --cask nickustinov/tap/itsypad
```

Or download the latest DMG from [GitHub releases](https://github.com/nickustinov/itsypad-macos/releases).

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘T / ⌘N | New tab |
| ⌘W | Close tab |
| ⌘O | Open file |
| ⌘S | Save |
| ⇧⌘S | Save as |
| ⌃Tab | Next tab |
| ⇧⌃Tab | Previous tab |
| ⌘F | Find |
| ⌥⌘F | Find and replace |
| ⌘G | Find next |
| ⇧⌘G | Find previous |
| ⌘E | Use selection for find |
| ⌘D | Duplicate line |
| ⌘+ | Increase font size |
| ⌘- | Decrease font size |
| ⌘0 | Reset font size |
| ⇧⌘L | Toggle line numbers |
| Tab | Indent selection |
| ⇧Tab | Unindent selection |
| Fn↓ / Fn↑ | Page down / up (moves cursor) |

## Architecture

```
Sources/
├── App/
│   ├── Launch.swift                    # App entry point
│   ├── AppDelegate.swift               # Menu bar, toolbar, window, and menu setup
│   ├── BonsplitRootView.swift          # SwiftUI root view rendering editor and clipboard tabs
│   ├── Models.swift                    # ShortcutKeys and shared data types
│   └── TabStore.swift                  # Tab data model with persistence
├── Editor/
│   ├── EditorTextView.swift            # NSTextView subclass with editing helpers and file drops
│   ├── EditorContentView.swift         # NSViewRepresentable wrapping text view, scroll view, and gutter
│   ├── EditorCoordinator.swift         # Tab/pane orchestrator bridging TabStore and Bonsplit
│   ├── EditorTheme.swift               # Monokai-inspired dark/light color palettes
│   ├── SyntaxHighlightCoordinator.swift # Tree-sitter syntax highlighting with injection support
│   ├── LanguageDetector.swift          # File extension → language mapping via CodeEditLanguages
│   ├── LineNumberGutterView.swift      # Line number gutter drawn alongside the text view
│   └── FileWatcher.swift                # DispatchSource-based file change monitoring
├── Clipboard/
│   ├── ClipboardStore.swift            # Clipboard monitoring and history persistence
│   ├── ClipboardContentView.swift      # NSCollectionView grid of clipboard cards with search
│   └── ClipboardTabView.swift          # NSViewRepresentable wrapper for ClipboardContentView
├── Settings/
│   ├── SettingsStore.swift             # UserDefaults-backed settings with change notifications
│   ├── SettingsView.swift              # SwiftUI settings window (general, editor, appearance)
│   └── ShortcutRecorder.swift          # SwiftUI hotkey recorder control
├── Hotkey/
│   ├── HotkeyManager.swift             # Global hotkeys and triple-tap modifier detection
│   └── ModifierKeyDetection.swift      # Left/right modifier key identification from key codes
├── Resources/
│   └── Assets.xcassets                 # App icon and custom images
├── Info.plist                          # Bundle metadata and document types
└── itsypad.entitlements                # Entitlements (unsigned executable memory for tree-sitter)
Executable/
└── main.swift                          # Executable target entry point
Packages/
└── Bonsplit/                           # Local package: split pane and tab bar framework
Tests/
├── ClipboardStoreTests.swift
├── EditorThemeTests.swift
├── LanguageDetectorTests.swift
├── LineNumberGutterViewTests.swift
├── ModifierKeyDetectionTests.swift
├── SettingsStoreTests.swift
├── ShortcutKeysTests.swift
└── TabStoreTests.swift
```

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for Xcode project generation

## Building

```bash
xcodegen generate
open itsypad.xcodeproj
```

Then build and run with ⌘R in Xcode. Tests run with ⌘U.

## Releasing

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
2. Build, sign, and package the DMG:

```bash
bash scripts/build-release.sh
```

3. Notarize and staple:

```bash
xcrun notarytool submit dist/itsypad-<VERSION>.dmg \
    --apple-id <APPLE_ID> --team-id <TEAM_ID> \
    --password <APP_SPECIFIC_PASSWORD> --wait
xcrun stapler staple dist/itsypad-<VERSION>.dmg
```

4. Create the GitHub release:

```bash
gh release create v<VERSION> dist/itsypad-<VERSION>.dmg \
    --title "v<VERSION>" --notes "Release notes here"
```

5. Update the Homebrew tap:

```bash
# Get SHA256 of the notarized DMG
shasum -a 256 dist/itsypad-<VERSION>.dmg

# Update Casks/itsypad.rb in homebrew-tap with new version and sha256
cd ../homebrew-tap
# Edit Casks/itsypad.rb
git commit -am "Update itsypad to <VERSION>"
git push
```

## License

MIT — see [LICENSE](LICENSE).
