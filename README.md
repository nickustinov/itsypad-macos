# Itsypad

[![Tests](https://github.com/nickustinov/itsypad-macos/actions/workflows/tests.yml/badge.svg)](https://github.com/nickustinov/itsypad-macos/actions/workflows/tests.yml)

A tiny, native macOS text editor + clipboard manager.

## Features

- **Text editor** — automatic code syntax highlighting and basic text editing capabilities
- **Clipboard manager** — suports textual content, always accessible via global hotkey
- **Menu bar app** — toggle via global hotkey, tripe-tap left Option key by default
- **Dock app** – show or hide in Dock, as you prefer
- **Lightweight** – nearly zero CPU and memory usage

### Editor
- **Monokai-inspired theme** — dark and light variants, controls editor background, tab bar, and window chrome
- **Multi-tab** — work on multiple files/notes at once, drag to reorder
- **Syntax highlighting** — 185+ languages via tree-sitter ([CodeEditLanguages](https://github.com/CodeEditApp/CodeEditLanguages)), with automatic language detection
- **Session persistence** — all tabs, content, and cursor positions are preserved across restarts. Never lose your work
- **Find and replace** — Cmd+F to find, Cmd+Option+F for find and replace
- **Line numbers** — optional, off by default
- **Current line highlight** — optional, off by default
- **Auto-indent** — matches indentation of the previous line on Enter
- **Configurable indentation** — spaces or tabs, tab width 1–8
- **Block indent/unindent** — select lines and press Tab / Shift+Tab
- **Duplicate line** — Cmd+D
- **Auto-close brackets** — `()`, `[]`, `{}`
- **Tab cycling** — Ctrl+Tab / Shift+Ctrl+Tab
- **New tab** — Cmd+T or Cmd+N, or click the + button in the tab bar
- **Save prompt** — asks to save when closing a dirty tab
- **Custom fonts** — pick any monospace font installed on your system
- **Font size controls** — Cmd+Plus, Cmd+Minus, Cmd+0 to reset
- **Window memory** — remembers size and position
- **Open at login** — optional

### Clipboard manager
- **Separate hotkey** — assign a global hotkey to show/hide
- **Searchable** — up to 1000 copied items in history


## Requirements

- macOS 14 (Sonoma) or later

## Building

```bash
# with Swift Package Manager
swift build

# or generate an Xcode project (requires xcodegen)
xcodegen generate
open itsypad.xcodeproj
```

## License

MIT — see [LICENSE](LICENSE).
