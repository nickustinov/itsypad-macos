import AppKit

struct EditorTheme {
    let isDark: Bool
    let background: NSColor
    let foreground: NSColor
    let captures: [String: NSColor]

    var insertionPointColor: NSColor { isDark ? .white : .black }

    func color(for captureName: String) -> NSColor {
        // Longest-prefix match: "keyword.function" → try "keyword.function", fall back to "keyword"
        var name = captureName
        while true {
            if let color = captures[name] { return color }
            guard let dot = name.lastIndex(of: ".") else { break }
            name = String(name[..<dot])
        }
        return foreground
    }

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
        foreground: hex(0xfcfcfa),
        captures: [
            // Keywords and control flow
            "keyword": hex(0xff6188),
            "keyword.function": hex(0xff6188),
            "keyword.return": hex(0xff6188),
            "keyword.operator": hex(0xff6188),
            "conditional": hex(0xff6188),
            "repeat": hex(0xff6188),
            "include": hex(0xff6188),
            "label": hex(0xff6188),

            // Functions
            "function": hex(0xa9dc76),
            "function.call": hex(0xa9dc76),
            "function.method": hex(0xa9dc76),
            "function.builtin": hex(0xa9dc76),
            "function.macro": hex(0xa9dc76),
            "method": hex(0xa9dc76),
            "constructor": hex(0xa9dc76),

            // Types
            "type": hex(0x78dce8),
            "type.builtin": hex(0x78dce8),

            // Strings
            "string": hex(0xffd866),
            "string.regex": hex(0xffd866),
            "string.special": hex(0xffd866),
            "string.special.key": hex(0xa9dc76),
            "escape": hex(0xfc9867),

            // Numbers, booleans, constants
            "number": hex(0xab9df2),
            "float": hex(0xab9df2),
            "boolean": hex(0xab9df2),
            "constant": hex(0xab9df2),
            "constant.builtin": hex(0xab9df2),

            // Comments
            "comment": hex(0x727072),

            // Operators and punctuation
            "operator": hex(0xff6188),
            "punctuation": hex(0x939293),
            "punctuation.delimiter": hex(0x939293),
            "punctuation.bracket": hex(0x939293),
            "punctuation.special": hex(0xff6188),

            // Variables and parameters
            "variable": hex(0xfcfcfa),
            "variable.builtin": hex(0xfc9867),
            "parameter": hex(0xfc9867),
            "property": hex(0x78dce8),

            // Tags (HTML/XML)
            "tag": hex(0xff6188),
            "tag.attribute": hex(0xa9dc76),
            "attribute": hex(0xa9dc76),

            // Embedded / interpolation
            "embedded": hex(0xfc9867),
            "spell": hex(0x727072),

            // Markdown / plain text
            "text.title": hex(0xff6188),
            "text.literal": hex(0xffd866),
            "text.emphasis": hex(0xfcfcfa),
            "text.strong": hex(0xfcfcfa),
            "text.uri": hex(0x78dce8),
            "text.reference": hex(0xa9dc76),
        ]
    )

    // MARK: - Monokai Pro light (inverted variant)

    static let light = EditorTheme(
        isDark: false,
        background: hex(0xffffff),
        foreground: hex(0x2d2a2e),
        captures: [
            "keyword": hex(0xd3284e),
            "keyword.function": hex(0xd3284e),
            "keyword.return": hex(0xd3284e),
            "keyword.operator": hex(0xd3284e),
            "conditional": hex(0xd3284e),
            "repeat": hex(0xd3284e),
            "include": hex(0xd3284e),
            "label": hex(0xd3284e),

            "function": hex(0x5a9e2f),
            "function.call": hex(0x5a9e2f),
            "function.method": hex(0x5a9e2f),
            "function.builtin": hex(0x5a9e2f),
            "function.macro": hex(0x5a9e2f),
            "method": hex(0x5a9e2f),
            "constructor": hex(0x5a9e2f),

            "type": hex(0x2990a4),
            "type.builtin": hex(0x2990a4),

            "string": hex(0xb68800),
            "string.regex": hex(0xb68800),
            "string.special": hex(0xb68800),
            "string.special.key": hex(0x5a9e2f),
            "escape": hex(0xc55715),

            "number": hex(0x7653c1),
            "float": hex(0x7653c1),
            "boolean": hex(0x7653c1),
            "constant": hex(0x7653c1),
            "constant.builtin": hex(0x7653c1),

            "comment": hex(0x9a9a9a),

            "operator": hex(0xd3284e),
            "punctuation": hex(0x6e6b6e),
            "punctuation.delimiter": hex(0x6e6b6e),
            "punctuation.bracket": hex(0x6e6b6e),
            "punctuation.special": hex(0xd3284e),

            "variable": hex(0x2d2a2e),
            "variable.builtin": hex(0xc55715),
            "parameter": hex(0xc55715),
            "property": hex(0x2990a4),

            "tag": hex(0xd3284e),
            "tag.attribute": hex(0x5a9e2f),
            "attribute": hex(0x5a9e2f),

            "embedded": hex(0xc55715),
            "spell": hex(0x9a9a9a),

            // Markdown / plain text
            "text.title": hex(0xd3284e),
            "text.literal": hex(0xb68800),
            "text.emphasis": hex(0x2d2a2e),
            "text.strong": hex(0x2d2a2e),
            "text.uri": hex(0x2990a4),
            "text.reference": hex(0x5a9e2f),
        ]
    )

    // MARK: - Hex color helper

    private static func hex(_ value: UInt32) -> NSColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
