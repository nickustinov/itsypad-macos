import AppKit
import JavaScriptCore

/// Lightweight highlight.js wrapper with proper compound CSS selector support.
/// NOT thread-safe — caller must serialize access (e.g., via a serial DispatchQueue).
class HighlightJS {
    static let shared = HighlightJS()

    private var hljs: JSValue?
    private var didLoadJS = false

    private(set) var backgroundColor: NSColor = .black
    private(set) var foregroundColor: NSColor = .white
    private var themeDict: [String: [NSAttributedString.Key: Any]] = [:]
    private var codeFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)

    private static let appBundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }()

    init() {}

    /// Lazily creates the JSContext and loads highlight.js on first use.
    private func ensureLoaded() -> JSValue? {
        if didLoadJS { return hljs }
        didLoadJS = true
        guard let jsContext = JSContext(),
              let jsPath = Self.appBundle.path(forResource: "highlight.min", ofType: "js"),
              let jsSource = try? String(contentsOfFile: jsPath) else {
            return nil
        }
        jsContext.evaluateScript(jsSource)
        hljs = jsContext.objectForKeyedSubscript("hljs")
        return hljs
    }

    // MARK: - Public API

    func setTheme(css: String) {
        let parsed = parseCSS(css)
        themeDict = buildThemeDict(from: parsed)

        if let base = parsed[".hljs"] {
            if let bg = base["background"] ?? base["background-color"] {
                backgroundColor = colorFromCSS(bg)
            }
            if let fg = base["color"] {
                foregroundColor = colorFromCSS(fg)
            }
        }
    }

    func loadTheme(named name: String) -> Bool {
        guard let url = Self.appBundle.url(forResource: name, withExtension: "css"),
              let css = try? String(contentsOf: url) else {
            return false
        }
        setTheme(css: css)
        return true
    }

    func setCodeFont(_ font: NSFont) {
        codeFont = font
    }

    func highlight(_ code: String, as language: String) -> NSAttributedString? {
        guard let hljs = ensureLoaded(), let ctx = hljs.context else { return nil }
        let options = JSValue(object: ["language": language, "ignoreIllegals": true], in: ctx)
        let result = hljs.invokeMethod("highlight", withArguments: [code, options as Any])
        if result?.isUndefined == true {
            return nil
        }
        guard let html = result?.objectForKeyedSubscript("value")?.toString() else {
            return nil
        }
        return processHTML(html)
    }

    struct AutoResult {
        let language: String
        let relevance: Int
        let attributed: NSAttributedString
    }

    func highlightAuto(_ code: String, subset: [String]? = nil) -> AutoResult? {
        guard let hljs = ensureLoaded() else { return nil }
        var args: [Any] = [code]
        if let subset { args.append(subset) }
        let result = hljs.invokeMethod("highlightAuto", withArguments: args)
        if result?.isUndefined == true { return nil }
        guard let lang = result?.objectForKeyedSubscript("language")?.toString(),
              let html = result?.objectForKeyedSubscript("value")?.toString() else {
            return nil
        }
        let relevance = result?.objectForKeyedSubscript("relevance")?.toInt32() ?? 0
        return AutoResult(language: lang, relevance: Int(relevance), attributed: processHTML(html))
    }

    func supportedLanguages() -> [String] {
        guard let hljs = ensureLoaded() else { return [] }
        return (hljs.invokeMethod("listLanguages", withArguments: [])?.toArray() as? [String]) ?? []
    }

    // MARK: - CSS parser

    /// Parses minified CSS into a dict of selector → {property: value}.
    private func parseCSS(_ css: String) -> [String: [String: String]] {
        let rulePattern = try! NSRegularExpression(pattern: "([^{}]+)\\{([^}]*)\\}")
        let ns = css as NSString
        var result: [String: [String: String]] = [:]

        for match in rulePattern.matches(in: css, range: NSRange(location: 0, length: ns.length)) {
            let selectorsStr = ns.substring(with: match.range(at: 1))
            let propsStr = ns.substring(with: match.range(at: 2))

            var props: [String: String] = [:]
            for pair in propsStr.components(separatedBy: ";") {
                let parts = pair.components(separatedBy: ":")
                if parts.count == 2 {
                    props[parts[0].trimmingCharacters(in: .whitespaces)] =
                        parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            guard !props.isEmpty else { continue }

            for selector in selectorsStr.components(separatedBy: ",") {
                let sel = selector.trimmingCharacters(in: .whitespaces)
                if !sel.isEmpty {
                    result[sel, default: [:]].merge(props) { _, new in new }
                }
            }
        }

        return result
    }

    /// Converts parsed CSS into a themeDict keyed by normalized class names.
    private func buildThemeDict(from parsed: [String: [String: String]]) -> [String: [NSAttributedString.Key: Any]] {
        var dict: [String: [NSAttributedString.Key: Any]] = [:]

        for (selector, props) in parsed {
            var attrs: [NSAttributedString.Key: Any] = [:]
            if let c = props["color"] { attrs[.foregroundColor] = colorFromCSS(c) }
            if let c = props["background-color"] { attrs[.backgroundColor] = colorFromCSS(c) }
            guard !attrs.isEmpty else { continue }

            if let key = normalizeSelector(selector) {
                dict[key, default: [:]].merge(attrs) { _, new in new }
            }
        }

        return dict
    }

    /// Normalizes a CSS selector to a lookup key.
    ///   `.hljs-keyword`          → `"hljs-keyword"`
    ///   `.hljs-title.function_`  → `"function_.hljs-title"` (sorted compound)
    ///   `.hljs-class .hljs-title`→ `nil` (descendant selectors skipped)
    private func normalizeSelector(_ selector: String) -> String? {
        let s = selector.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix(".") else { return nil }
        let body = String(s.dropFirst())
        // Descendant selectors contain spaces
        if body.contains(" ") { return nil }
        let classes = body.components(separatedBy: ".")
        return classes.sorted().joined(separator: ".")
    }

    // MARK: - HTML parser

    /// Converts highlight.js HTML output to NSAttributedString.
    private func processHTML(_ html: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(html.utf16)
        let count = chars.count
        var i = 0
        var classStack: [[String]] = []

        while i < count {
            // Scan text until '<'
            let textStart = i
            while i < count && chars[i] != 0x3C { i += 1 } // '<'
            if i > textStart {
                let text = string(from: chars, start: textStart, end: i)
                let decoded = decodeHTMLEntities(text)
                result.append(NSAttributedString(string: decoded, attributes: currentAttrs(classStack)))
            }
            if i >= count { break }

            // Skip '<'
            i += 1
            if i >= count { break }

            if chars[i] == 0x73 { // 's' → <span class="...">
                // Skip 'span class="'
                let prefix = Array("span class=\"".utf16)
                i += prefix.count
                // Scan class value until '">'
                let classStart = i
                while i < count - 1 && !(chars[i] == 0x22 && chars[i + 1] == 0x3E) { i += 1 } // '">'
                let classStr = string(from: chars, start: classStart, end: i)
                classStack.append(classStr.components(separatedBy: " "))
                i += 2 // skip '">'
            } else if chars[i] == 0x2F { // '/' → </span>
                // Skip '/span>'
                i += 6 // "/span>"
                if !classStack.isEmpty { classStack.removeLast() }
            } else {
                // Literal '<'
                result.append(NSAttributedString(string: "<", attributes: currentAttrs(classStack)))
            }
        }

        return result
    }

    private func string(from utf16: [UInt16], start: Int, end: Int) -> String {
        String(utf16CodeUnits: Array(utf16[start..<end]), count: end - start)
    }

    private func currentAttrs(_ classStack: [[String]]) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: foregroundColor,
        ]

        // Apply base "hljs" style
        if let base = themeDict["hljs"] {
            attrs.merge(base) { _, new in new }
        }

        // Apply styles for each span level
        for classes in classStack {
            let sorted = classes.sorted()

            // Try full compound key first (sorted, dot-joined)
            if sorted.count > 1 {
                let compoundKey = sorted.joined(separator: ".")
                if let style = themeDict[compoundKey] {
                    attrs.merge(style) { _, new in new }
                    continue
                }
            }

            // Try 2-class subsets when 3+ classes don't match as a full compound
            if sorted.count > 2 {
                var matched = false
                for i in 0..<sorted.count {
                    for j in (i + 1)..<sorted.count {
                        let pairKey = "\(sorted[i]).\(sorted[j])"
                        if let style = themeDict[pairKey] {
                            attrs.merge(style) { _, new in new }
                            matched = true
                            break
                        }
                    }
                    if matched { break }
                }
                if matched { continue }
            }

            // Fall back to individual classes
            for cls in sorted {
                if let style = themeDict[cls] {
                    attrs.merge(style) { _, new in new }
                }
            }
        }

        return attrs
    }

    // MARK: - Color parsing

    private func colorFromCSS(_ value: String) -> NSColor {
        let s = value.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else {
            switch s {
            case "white": return .white
            case "black": return .black
            default: return .gray
            }
        }

        let hex = String(s.dropFirst())
        var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0
        let divisor: CGFloat

        if hex.count == 6 {
            Scanner(string: String(hex.prefix(2))).scanHexInt64(&r)
            Scanner(string: String(hex.dropFirst(2).prefix(2))).scanHexInt64(&g)
            Scanner(string: String(hex.dropFirst(4).prefix(2))).scanHexInt64(&b)
            divisor = 255
        } else if hex.count == 3 {
            Scanner(string: String(hex.prefix(1))).scanHexInt64(&r)
            Scanner(string: String(hex.dropFirst(1).prefix(1))).scanHexInt64(&g)
            Scanner(string: String(hex.dropFirst(2).prefix(1))).scanHexInt64(&b)
            r = r * 17; g = g * 17; b = b * 17
            divisor = 255
        } else {
            return .gray
        }

        return NSColor(red: CGFloat(r) / divisor, green: CGFloat(g) / divisor,
                        blue: CGFloat(b) / divisor, alpha: 1)
    }

    // MARK: - HTML entity decoding

    private static let entityMap: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    private func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        result.reserveCapacity(string.count)
        var i = string.startIndex

        while i < string.endIndex {
            if string[i] == "&" {
                let rest = string[i...]
                if let semi = rest.firstIndex(of: ";"), string.distance(from: i, to: semi) < 10 {
                    let entity = String(string[string.index(after: i)..<semi])
                    if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                        if let cp = UInt32(entity.dropFirst(2), radix: 16),
                           let scalar = Unicode.Scalar(cp) {
                            result.append(Character(scalar))
                            i = string.index(after: semi)
                            continue
                        }
                    } else if entity.hasPrefix("#") {
                        if let cp = UInt32(entity.dropFirst(), radix: 10),
                           let scalar = Unicode.Scalar(cp) {
                            result.append(Character(scalar))
                            i = string.index(after: semi)
                            continue
                        }
                    } else if let char = Self.entityMap[entity] {
                        result.append(char)
                        i = string.index(after: semi)
                        continue
                    }
                }
            }
            result.append(string[i])
            i = string.index(after: i)
        }

        return result
    }
}
