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
        if let tsLanguage = codeLang.language {
            try? parser.setLanguage(tsLanguage)
            currentQuery = TreeSitterModel.shared.query(for: codeLang.id)
            // Fall back to loading highlights.scm directly if the model fails
            if currentQuery == nil, let url = codeLang.queryURL {
                currentQuery = try? Query(language: tsLanguage, url: url)
            }
        } else {
            currentQuery = nil
        }
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

        let parser = Parser()
        if let lang = LanguageDetector.shared.codeLanguage(for: language).language {
            try? parser.setLanguage(lang)
        }
        let query = currentQuery!

        let work = DispatchWorkItem { [weak self] in
            guard let tree = parser.parse(textSnapshot) else { return }

            // Use SwiftTreeSitter's built-in highlights() — sorted less-specific first
            let cursor = query.execute(in: tree)
            let namedRanges = cursor.highlights().filter { nr in
                // Skip non-highlight captures from folds/indents/locals .scm files
                let first = nr.nameComponents.first ?? ""
                return first != "fold" && first != "indent" && first != "local"
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let tv = self.textView else { return }
                guard self.highlightGeneration == generation else { return }
                guard tv.string == textSnapshot else { return }

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
