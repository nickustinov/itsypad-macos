# Itsypad

[![Tests](https://github.com/nickustinov/itsypad-macos/actions/workflows/tests.yml/badge.svg)](https://github.com/nickustinov/itsypad-macos/actions/workflows/tests.yml)

A tiny, fast scratchpad and clipboard manager for Mac. Free forever.

![Itsypad screenshot](itsypad-screenshot-v2.png)

## Features

- **Text editor** — syntax highlighting, multi-tab, split view, find and replace
- **Clipboard manager** — 500-item history, searchable, click to copy
- **Global hotkeys** — tap left ⌥ three times to show/hide, or define your own hotkey
- **Lightweight** — nearly zero CPU and memory usage
- **No AI, no telemetry** — your data stays on your machine
- **Menu bar icon** — show or hide in menu bar
- **Dock icon** — show or hide in Dock, as you prefer
- **Open at login** — optional auto-start
- **iCloud sync** — sync scratch tabs across Macs via iCloud

## Editor
- **Multi-tab and split view** — work on multiple files/notes at once, drag to reorder (tab bar by [Bonsplit](https://github.com/almonk/bonsplit))
- **Syntax highlighting** — 185+ languages via [highlight.js](https://highlightjs.org), with automatic language detection
- **Find and replace** — built-in find bar with next/previous match and use selection for find
- **Session persistence** — all tabs, content, and cursor positions are preserved across restarts
- **Auto-save** — content is continuously saved to session, never lose your work
- **Monokai-inspired theme** — dark and light variants with system appearance support

## Clipboard manager
- **Text and images** — stores clipboard content
- **Searchable** — filter history with highlighted search matches
- **Click to copy** — click any entry to copy it back to clipboard
- **Zoom preview** — hover a tile and click the magnifying glass to view full content in a near-fullscreen overlay
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

## Also by me

If you like Itsypad, check out my other macOS apps - same philosophy of native, lightweight, no-bloat design.

**[Itsyhome](https://itsyhome.app)** - Control your entire smart home from the macOS menu bar. Cameras, lights, thermostats, locks, scenes, and 18+ HomeKit device types. Global keyboard shortcuts, Stream Deck support, deeplinks, and webhooks for power users. Free and [open source](https://github.com/nickustinov/itsyhome-macos).

**[Itsytv](https://itsytv.app)** - The missing Apple TV remote for macOS. Full D-pad and playback controls, now-playing widget, app launcher, text input, and multi-device support. Free and [open source](https://github.com/nickustinov/itsytv-macos).

## Architecture

```
Sources/
├── App/
│   ├── Launch.swift                    # App entry point
│   ├── AppDelegate.swift               # Menu bar, toolbar, window, and menu setup
│   ├── BonsplitRootView.swift          # SwiftUI root view rendering editor and clipboard tabs
│   ├── Models.swift                    # ShortcutKeys and shared data types
│   └── TabStore.swift                  # Tab data model with persistence and iCloud sync
├── Editor/
│   ├── EditorTextView.swift            # NSTextView subclass with editing helpers and file drops
│   ├── EditorContentView.swift         # NSViewRepresentable wrapping text view, scroll view, and gutter
│   ├── EditorCoordinator.swift         # Tab/pane orchestrator bridging TabStore, Bonsplit, and iCloud
│   ├── EditorTheme.swift               # Monokai-inspired dark/light color palettes
│   ├── HighlightJS.swift               # JSContext wrapper for highlight.js with CSS/HTML parsing
│   ├── SyntaxHighlightCoordinator.swift # Syntax highlighting coordinator using HighlightJS
│   ├── LanguageDetector.swift          # File extension → language mapping for highlight.js
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
└── itsypad.entitlements                # Entitlements (unsigned executable memory for highlight.js)
Executable/
└── main.swift                          # Executable target entry point
Packages/
└── Bonsplit/                           # Local package: split pane and tab bar framework
Tests/
├── ClipboardStoreTests.swift
├── EditorThemeTests.swift
├── FileWatcherTests.swift
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
