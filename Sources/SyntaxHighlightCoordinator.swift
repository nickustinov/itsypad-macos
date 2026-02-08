import AppKit
import CodeEditLanguages
import SwiftTreeSitter

class SyntaxHighlightCoordinator: NSObject, NSTextViewDelegate {
    weak var textView: EditorTextView?
    var language: String = "plain" {
        didSet {
            if language != oldValue { setLanguage(language) }
        }
    }
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    private let parser = Parser()
    private var currentQuery: Query?
    private var injectionQuery: Query?
    private static let skipCapturePrefixes: Set<String> = ["fold", "indent", "local", "injection", "none"]
    private(set) var theme: EditorTheme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)

    private let highlightQueue = DispatchQueue(label: "Itsypad.SyntaxHighlight", qos: .userInitiated)

    override init() {
        super.init()
        setLanguage(language)
    }
    private var pendingHighlight: DispatchWorkItem?
    private var highlightGeneration: Int = 0
    private var lastHighlightedText: String = ""
    private var lastLanguage: String?
    private var lastAppearance: String?

    var themeBackgroundColor: NSColor { theme.background }

    func updateTheme() {
        theme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
        lastAppearance = nil
        rehighlight()
    }

    private func setLanguage(_ lang: String) {
        let codeLang = LanguageDetector.shared.codeLanguage(for: lang)
        NSLog("[SyntaxHL] setLanguage(\"%@\") → codeLang.id=%@ tsLanguage=%@ queryURL=%@",
              lang, String(describing: codeLang.id), codeLang.language == nil ? "nil" : "present",
              codeLang.queryURL?.absoluteString ?? "nil")
        if let tsLanguage = codeLang.language {
            try? parser.setLanguage(tsLanguage)
            currentQuery = TreeSitterModel.shared.query(for: codeLang.id)
            if currentQuery == nil, let url = codeLang.queryURL {
                currentQuery = try? Query(language: tsLanguage, url: url)
            }
        } else {
            currentQuery = nil
        }

        // Prepare injection parser for markdown inline
        injectionQuery = nil
        if codeLang.id == .markdown {
            let inlineLang = CodeLanguage.markdownInline
            if let tsInline = inlineLang.language {
                injectionQuery = TreeSitterModel.shared.query(for: inlineLang.id)
                if injectionQuery == nil, let url = inlineLang.queryURL {
                    injectionQuery = try? Query(language: tsInline, url: url)
                }
            }
        }
        NSLog("[SyntaxHL] setLanguage(\"%@\") → query=%@, injectionQuery=%@",
              lang, currentQuery == nil ? "nil" : "present", injectionQuery == nil ? "nil" : "present")
        scheduleHighlightIfNeeded()
    }

    func scheduleHighlightIfNeeded() {
        guard let tv = textView else { return }
        let text = tv.string
        let lang = language
        let appearance = SettingsStore.shared.appearanceOverride

        if (text as NSString).length > 200_000 {
            lastHighlightedText = text
            lastLanguage = lang
            lastAppearance = appearance
            return
        }

        if text == lastHighlightedText && lastLanguage == lang && lastAppearance == appearance {
            return
        }

        rehighlight()
    }

    func rehighlight() {
        guard let tv = textView else { return }
        let textSnapshot = tv.string
        let userFont = font
        let currentTheme = theme

        // No query available — plain text with bullet dash highlighting only
        if currentQuery == nil {
            let ns = textSnapshot as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            let sel = tv.selectedRange()
            tv.textStorage?.beginEditing()
            tv.textStorage?.setAttributes([
                .font: userFont,
                .foregroundColor: currentTheme.foreground,
            ], range: fullRange)

            // Highlight bullet dashes at any indent level
            let dashColor = currentTheme.color(for: "punctuation.special")
            if let regex = try? NSRegularExpression(pattern: "^[ \\t]*-(?= )", options: .anchorsMatchLines) {
                for match in regex.matches(in: textSnapshot, range: fullRange) {
                    let r = match.range
                    let dashRange = NSRange(location: r.location + r.length - 1, length: 1)
                    tv.textStorage?.addAttribute(.foregroundColor, value: dashColor, range: dashRange)
                }
            }

            tv.textStorage?.endEditing()
            applyWrapIndent(to: tv, font: userFont)
            let safeLocation = min(sel.location, ns.length)
            let safeLength = min(sel.length, ns.length - safeLocation)
            tv.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            lastHighlightedText = textSnapshot
            lastLanguage = language
            lastAppearance = SettingsStore.shared.appearanceOverride
            return
        }

        highlightGeneration += 1
        let generation = highlightGeneration
        pendingHighlight?.cancel()

        let blockParser = Parser()
        let codeLang = LanguageDetector.shared.codeLanguage(for: language)
        if let lang = codeLang.language {
            try? blockParser.setLanguage(lang)
        }
        let query = currentQuery!
        let inlineQuery = injectionQuery

        let work = DispatchWorkItem { [weak self] in
            guard let tree = blockParser.parse(textSnapshot) else { return }

            let cursor = query.execute(in: tree)
            let allCaptures = cursor.highlights()

            // Separate highlight captures from injection captures
            var namedRanges: [NamedRange] = []
            var injectionRanges: [NSRange] = []
            for nr in allCaptures {
                let first = nr.nameComponents.first ?? ""
                if Self.skipCapturePrefixes.contains(first) {
                    if nr.name == "injection.content" {
                        injectionRanges.append(nr.range)
                    }
                    continue
                }
                namedRanges.append(nr)
            }

            // Run inline parser on injection regions (e.g. markdown inline)
            if let inlineQuery, let inlineLang = CodeLanguage.markdownInline.language {
                let inlineParser = Parser()
                try? inlineParser.setLanguage(inlineLang)
                let nsText = textSnapshot as NSString

                for region in injectionRanges {
                    guard region.location + region.length <= nsText.length else { continue }
                    let snippet = nsText.substring(with: region)
                    guard let inlineTree = inlineParser.parse(snippet) else { continue }
                    let inlineCursor = inlineQuery.execute(in: inlineTree)
                    for nr in inlineCursor.highlights() {
                        let first = nr.nameComponents.first ?? ""
                        if Self.skipCapturePrefixes.contains(first) { continue }
                        // Offset range back to document coordinates
                        let adjusted = NSRange(location: nr.range.location + region.location, length: nr.range.length)
                        namedRanges.append(NamedRange(name: nr.name, range: adjusted))
                    }
                }
            }

            NSLog("[SyntaxHL] rehighlight: captures=%d, injectionRegions=%d, names=%@",
                  namedRanges.count, injectionRanges.count,
                  Array(Set(namedRanges.map(\.name))).sorted().joined(separator: ", "))

            DispatchQueue.main.async { [weak self] in
                guard let self, let tv = self.textView else {
                    NSLog("[SyntaxHL] main: self or textView nil, skipping")
                    return
                }
                guard self.highlightGeneration == generation else {
                    NSLog("[SyntaxHL] main: generation mismatch (current=%d, expected=%d), skipping",
                          self.highlightGeneration, generation)
                    return
                }
                guard tv.string == textSnapshot else {
                    NSLog("[SyntaxHL] main: text changed since parse, skipping")
                    return
                }

                NSLog("[SyntaxHL] main: applying %d captures to text of length %d",
                      namedRanges.count, (tv.string as NSString).length)

                let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
                let sel = tv.selectedRange()

                tv.textStorage?.beginEditing()

                // Base: foreground + font
                tv.textStorage?.setAttributes([
                    .font: userFont,
                    .foregroundColor: currentTheme.foreground,
                ], range: fullRange)

                // Apply capture colors (sorted: less-specific first, more-specific overrides)
                for nr in namedRanges {
                    let range = nr.range
                    guard range.location + range.length <= fullRange.length else { continue }
                    let color = currentTheme.color(for: nr.name)
                    tv.textStorage?.addAttribute(.foregroundColor, value: color, range: range)
                }

                tv.textStorage?.endEditing()
                self.applyWrapIndent(to: tv, font: userFont)

                // Restore selection
                let safeLocation = min(sel.location, (tv.string as NSString).length)
                let safeLength = min(sel.length, (tv.string as NSString).length - safeLocation)
                tv.setSelectedRange(NSRange(location: safeLocation, length: safeLength))

                self.lastHighlightedText = textSnapshot
                self.lastLanguage = self.language
                self.lastAppearance = SettingsStore.shared.appearanceOverride
            }
        }

        pendingHighlight = work
        highlightQueue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func applyWrapIndent(to textView: EditorTextView, font: NSFont) {
        guard let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let totalLength = ns.length
        guard totalLength > 0 else { return }

        let tabWidth = SettingsStore.shared.tabWidth
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let tabPixelWidth = spaceWidth * CGFloat(tabWidth)

        storage.beginEditing()
        var pos = 0
        while pos < totalLength {
            let lineRange = ns.lineRange(for: NSRange(location: pos, length: 0))

            // Measure leading whitespace
            var indent: CGFloat = 0
            var i = lineRange.location
            let lineEnd = lineRange.location + lineRange.length
            while i < lineEnd {
                let ch = ns.character(at: i)
                if ch == 0x20 { indent += spaceWidth }
                else if ch == 0x09 { indent += tabPixelWidth }
                else { break }
                i += 1
            }

            let para = NSMutableParagraphStyle()
            para.headIndent = indent
            storage.addAttribute(.paragraphStyle, value: para, range: lineRange)

            pos = lineRange.location + lineRange.length
        }
        storage.endEditing()
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? EditorTextView else { return }
        tv.onTextChange?(tv.string)
        updateCaretStatusAndHighlight()
        scheduleHighlightIfNeeded()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateCaretStatusAndHighlight()
    }

    private func updateCaretStatusAndHighlight() {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        tv.textStorage?.beginEditing()
        tv.textStorage?.removeAttribute(.backgroundColor, range: fullRange)

        if SettingsStore.shared.highlightCurrentLine {
            let sel = tv.selectedRange()
            let location = min(sel.location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            tv.textStorage?.addAttribute(
                .backgroundColor,
                value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.12),
                range: lineRange
            )
        }

        tv.textStorage?.endEditing()
    }
}
