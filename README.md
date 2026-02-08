# Itsypad

[![Tests](https://github.com/nickustinov/itsypad-macos/actions/workflows/tests.yml/badge.svg)](https://github.com/nickustinov/itsypad-macos/actions/workflows/tests.yml)

A tiny, native macOS text editor + clipboard manager that lives in your menu bar.

I write all my ideas and thoughts as plain text and needed something super lightweight — not an IDE, not VS Code, not even a full-blown editor. Just a fast scratchpad that's always one hotkey away. 

Itsypad is a native Swift/AppKit app — no Electron, no web views, no bloat. If you like it, use it. It's free.

## Features

- **Menu bar app** — toggle with a hotkey
- **Clipboard manager** — supports textual content only, always accessible via global hotkey
- **Monokai-inspired theme** — dark and light variants, controls editor background, tab bar, and window chrome
- **Global hotkeys** — configurable shortcuts including triple-tap modifier keys (e.g. triple-tap Left Option). Distinguishes left and right modifier keys

## Editor
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
