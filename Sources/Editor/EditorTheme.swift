import AppKit

struct EditorTheme {
    let isDark: Bool
    let background: NSColor
    let foreground: NSColor

    var insertionPointColor: NSColor { isDark ? .white : .black }

    // MARK: - Resolve theme for current appearance setting

    static func current(for appearance: String) -> EditorTheme {
        switch appearance {
        case "light": return light
        case "dark": return dark
        default: return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: - Monokai Pro dark

    static let dark = EditorTheme(
        isDark: true,
        background: hex(0x25252c),
        foreground: hex(0xd4d4d4)
    )

    // MARK: - Monokai Pro light (inverted variant)

    static let light = EditorTheme(
        isDark: false,
        background: hex(0xffffff),
        foreground: hex(0x403e41)
    )

    // Bullet-dash color (matches punctuation.special from old captures)
    var bulletDashColor: NSColor { isDark ? Self.hex(0xff6188) : Self.hex(0xd3284e) }

    // MARK: - Hex color helper

    private static func hex(_ value: UInt32) -> NSColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
