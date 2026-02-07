# Itsypad

A tiny, native macOS text editor that lives in your menu bar.

I made this for myself. I write all my ideas and thoughts as plain text and needed something super lightweight — not an IDE, not VS Code, not even a full-blown editor. Just a fast scratchpad that's always one hotkey away. But I also paste code snippets regularly, so syntax highlighting was a must.

Nothing I tried felt right, so I built Itsypad. It's a native Swift/AppKit app — no Electron, no web views, no bloat. If you like it, use it. It's free.

## Features

- **Menu bar app** — lives in the system tray, toggle with a global hotkey
- **Multi-tab** — work on multiple files/notes at once
- **Syntax highlighting** — 185+ languages via [Highlightr](https://github.com/raspu/Highlightr) (highlight.js), with automatic language detection
- **Themes** — 90+ built-in themes including all four Catppuccin flavors (Latte, Frappé, Macchiato, Mocha). The theme controls everything: editor background, tab bar, window chrome, caret color
- **Session persistence** — all tabs, content, and cursor positions are preserved across restarts. Never lose your work
- **Global hotkey** — configurable shortcut including triple-tap modifier keys (e.g. triple-tap Option)
- **Line numbers** — optional, off by default
- **Current line highlight** — optional, off by default
- **Auto-indent** — matches indentation of the previous line on Enter
- **Auto-close brackets** — `()`, `[]`, `{}`
- **Tab cycling** — Ctrl+Tab / Shift+Ctrl+Tab
- **Double-click tab bar** — creates a new tab
- **Save prompt** — asks to save when closing a dirty tab
- **Custom fonts** — pick any monospace font installed on your system
- **Font size controls** — Cmd+Plus, Cmd+Minus, Cmd+0 to reset
- **Find** — Cmd+F
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
