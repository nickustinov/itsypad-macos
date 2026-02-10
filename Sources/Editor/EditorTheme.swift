import AppKit

struct EditorTheme {
    let isDark: Bool
    let background: NSColor
    let foreground: NSColor

    var insertionPointColor: NSColor { isDark ? .white : .black }

    // MARK: - Cached CSS-derived themes

    private static var activeDark: EditorTheme?
    private static var activeLight: EditorTheme?

    static func setCurrent(_ theme: EditorTheme) {
        if theme.isDark {
            activeDark = theme
        } else {
            activeLight = theme
        }
    }

    // MARK: - Resolve theme for current appearance setting

    static func current(for appearance: String) -> EditorTheme {
        switch appearance {
        case "light": return activeLight ?? light
        case "dark": return activeDark ?? dark
        default:
            let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return systemIsDark ? (activeDark ?? dark) : (activeLight ?? light)
        }
    }

    // MARK: - Hardcoded fallback (Itsypad)

    static let dark = EditorTheme(
        isDark: true,
        background: hex(0x25252c),
        foreground: hex(0xd4d4d4)
    )

    static let light = EditorTheme(
        isDark: false,
        background: hex(0xffffff),
        foreground: hex(0x403e41)
    )

    // Bullet-dash color (matches punctuation.special from old captures)
    var bulletDashColor: NSColor { isDark ? Self.hex(0xff6188) : Self.hex(0xd3284e) }

    // Checkbox bracket color
    var checkboxColor: NSColor { isDark ? Self.hex(0xab9df2) : Self.hex(0x7c6bb7) }

    // Link color
    var linkColor: NSColor { isDark ? Self.hex(0x78b9f2) : Self.hex(0x0969b2) }

    // MARK: - Hex color helper

    private static func hex(_ value: UInt32) -> NSColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
