import AppKit

class SyntaxHighlightCoordinator: NSObject, NSTextViewDelegate {
    weak var textView: EditorTextView?
    var language: String = "plain" {
        didSet {
            if language != oldValue { setLanguage(language) }
        }
    }
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    // Shared across all coordinators — JSContext created lazily on first highlight call.
    // All access serialized via highlightQueue.
    private static let highlightJS = HighlightJS.shared
    private static let highlightQueue = DispatchQueue(label: "Itsypad.SyntaxHighlight", qos: .userInitiated)

    private(set) var theme: EditorTheme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
    private(set) var themeBackgroundColor: NSColor = EditorTheme.current(for: SettingsStore.shared.appearanceOverride).background
    private(set) var themeIsDark: Bool = EditorTheme.current(for: SettingsStore.shared.appearanceOverride).isDark

    private var pendingHighlight: DispatchWorkItem?
    private var lastHighlightedText: String = ""
    private var lastLanguage: String?
    private var lastAppearance: String?
    private var previousHighlightedLineRange: NSRange?

    override init() {
        super.init()
        applyTheme()
        setLanguage(language)
    }

    func updateTheme() {
        theme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
        applyTheme()
        lastAppearance = nil
        rehighlight()
    }

    private func applyTheme() {
        let isDark = theme.isDark
        let themeId = SettingsStore.shared.syntaxTheme
        let themeName = SyntaxThemeRegistry.cssResource(for: themeId, isDark: isDark)
        let currentFont = font

        Self.highlightQueue.sync {
            if Self.highlightJS.loadTheme(named: themeName) {
                NSLog("[SyntaxHighlight] Loaded theme '%@'", themeName)
            } else {
                NSLog("[SyntaxHighlight] FAILED to load theme '%@'", themeName)
            }
            Self.highlightJS.setCodeFont(currentFont)
        }

        themeBackgroundColor = Self.highlightJS.backgroundColor
        if let srgb = themeBackgroundColor.usingColorSpace(.sRGB) {
            let luminance = 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
            themeIsDark = luminance < 0.5
        } else {
            themeIsDark = isDark
        }

        let cssTheme = EditorTheme(
            isDark: themeIsDark,
            background: themeBackgroundColor,
            foreground: Self.highlightJS.foregroundColor
        )
        EditorTheme.setCurrent(cssTheme)
        theme = cssTheme
    }

    private func setLanguage(_ lang: String) {
        scheduleHighlightIfNeeded()
    }

    func scheduleHighlightIfNeeded(text: String? = nil) {
        guard let tv = textView else { return }
        let text = text ?? tv.string
        let lang = language
        let appearance = SettingsStore.shared.appearanceOverride

        if (text as NSString).length > 200_000 {
            lastHighlightedText = text
            lastLanguage = lang
            lastAppearance = appearance
            return
        }

        if text == lastHighlightedText && lastLanguage == lang
            && lastAppearance == appearance {
            return
        }

        rehighlight()
    }

    func rehighlight() {
        guard let tv = textView else { return }
        let textSnapshot = tv.string
        let userFont = font
        let currentTheme = theme
        let hlLang = LanguageDetector.shared.highlightrLanguage(for: language)

        pendingHighlight?.cancel()

        // No language — plain text with bullet dash highlighting only
        guard let hlLang else {
            applyPlainText(tv: tv, text: textSnapshot, font: userFont, theme: currentTheme)
            return
        }

        let highlightJS = Self.highlightJS

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            highlightJS.setCodeFont(userFont)
            let highlighted = highlightJS.highlight(textSnapshot, as: hlLang)
            if highlighted == nil {
                NSLog("[SyntaxHighlight] highlight() returned nil for language '%@'", hlLang)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let tv = self.textView else { return }
                guard tv.string == textSnapshot else { return }

                let ns = textSnapshot as NSString
                let fullRange = NSRange(location: 0, length: ns.length)
                let sel = tv.selectedRange()

                tv.textStorage?.beginEditing()

                if let highlighted {
                    tv.textStorage?.replaceCharacters(in: fullRange, with: highlighted)
                    // Override font uniformly
                    let newLength = (tv.textStorage?.length ?? ns.length)
                    tv.textStorage?.addAttribute(.font, value: userFont, range: NSRange(location: 0, length: newLength))
                } else {
                    tv.textStorage?.setAttributes([
                        .font: userFont,
                        .foregroundColor: currentTheme.foreground,
                    ], range: fullRange)
                }

                // Apply bullet dash highlighting on top
                self.applyListMarkers(tv: tv, text: textSnapshot, theme: currentTheme)
                self.applyLinkHighlighting(tv: tv, text: textSnapshot, theme: currentTheme)

                tv.textStorage?.endEditing()
                self.applyWrapIndent(to: tv, font: userFont)

                let safeLocation = min(sel.location, ns.length)
                let safeLength = min(sel.length, ns.length - safeLocation)
                tv.setSelectedRange(NSRange(location: safeLocation, length: safeLength))

                self.previousHighlightedLineRange = nil
                self.lastHighlightedText = textSnapshot
                self.lastLanguage = self.language
                self.lastAppearance = SettingsStore.shared.appearanceOverride
            }
        }

        pendingHighlight = work
        Self.highlightQueue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func applyPlainText(tv: EditorTextView, text: String, font: NSFont, theme: EditorTheme) {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let sel = tv.selectedRange()

        tv.textStorage?.beginEditing()
        tv.textStorage?.setAttributes([
            .font: font,
            .foregroundColor: theme.foreground,
        ], range: fullRange)

        applyListMarkers(tv: tv, text: text, theme: theme)
        applyLinkHighlighting(tv: tv, text: text, theme: theme)

        tv.textStorage?.endEditing()
        applyWrapIndent(to: tv, font: font)

        let safeLocation = min(sel.location, ns.length)
        let safeLength = min(sel.length, ns.length - safeLocation)
        tv.setSelectedRange(NSRange(location: safeLocation, length: safeLength))

        previousHighlightedLineRange = nil
        lastHighlightedText = text
        lastLanguage = language
        lastAppearance = SettingsStore.shared.appearanceOverride
    }

    // Custom attribute key for clickable link URLs
    static let linkURLKey = NSAttributedString.Key("ItsypadLinkURL")

    // Pre-compiled regex for URL highlighting
    private static let urlRegex = try! NSRegularExpression(
        pattern: "https?://\\S+", options: []
    )

    // Pre-compiled regex for list marker highlighting
    private static let bulletMarkerRegex = try! NSRegularExpression(
        pattern: "^[ \\t]*[-*](?= )", options: .anchorsMatchLines
    )
    private static let orderedMarkerRegex = try! NSRegularExpression(
        pattern: "^[ \\t]*\\d+\\.(?= )", options: .anchorsMatchLines
    )
    private static let checkboxRegex = try! NSRegularExpression(
        pattern: "^([ \\t]*[-*] )(\\[[ x]\\])( )(.*)",
        options: .anchorsMatchLines
    )

    private func applyListMarkers(tv: EditorTextView, text: String, theme: EditorTheme) {
        guard language == "plain" || language == "markdown" else { return }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let dashColor = theme.bulletDashColor
        let checkboxColor = theme.checkboxColor

        let store = SettingsStore.shared

        // Bullet dashes and asterisks
        if store.bulletListsEnabled {
            for match in Self.bulletMarkerRegex.matches(in: text, range: fullRange) {
                let r = match.range
                let markerRange = NSRange(location: r.location + r.length - 1, length: 1)
                tv.textStorage?.addAttribute(.foregroundColor, value: dashColor, range: markerRange)
            }
        }

        // Ordered numbers
        if store.numberedListsEnabled {
            for match in Self.orderedMarkerRegex.matches(in: text, range: fullRange) {
                let r = match.range
                tv.textStorage?.addAttribute(.foregroundColor, value: dashColor, range: r)
            }
        }

        // Checkbox styling
        guard store.checklistsEnabled else { return }
        for match in Self.checkboxRegex.matches(in: text, range: fullRange) {
            let bracketRange = match.range(at: 2)
            tv.textStorage?.addAttribute(.foregroundColor, value: checkboxColor, range: bracketRange)

            let bracketText = ns.substring(with: bracketRange)
            if bracketText == "[x]" {
                // Dim the entire line (prefix + content) for checked items
                let lineRange = match.range
                tv.textStorage?.addAttribute(.foregroundColor, value: theme.foreground.withAlphaComponent(0.4), range: lineRange)
                // Re-apply checkbox color on brackets so they stay visible
                tv.textStorage?.addAttribute(.foregroundColor, value: checkboxColor.withAlphaComponent(0.4), range: bracketRange)
                // Strikethrough on content
                let contentRange = match.range(at: 4)
                if contentRange.length > 0 {
                    tv.textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    tv.textStorage?.addAttribute(.strikethroughColor, value: theme.foreground.withAlphaComponent(0.4), range: contentRange)
                }
            }
        }
    }

    private func applyLinkHighlighting(tv: EditorTextView, text: String, theme: EditorTheme) {
        guard SettingsStore.shared.clickableLinks else { return }
        guard language == "plain" || language == "markdown" else { return }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let linkColor = theme.linkColor

        for match in Self.urlRegex.matches(in: text, range: fullRange) {
            let r = match.range
            tv.textStorage?.addAttribute(.foregroundColor, value: linkColor, range: r)
            tv.textStorage?.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            tv.textStorage?.addAttribute(.underlineColor, value: linkColor, range: r)
            let urlString = ns.substring(with: r)
            tv.textStorage?.addAttribute(Self.linkURLKey, value: urlString, range: r)
        }
    }

    func applyWrapIndent(to textView: EditorTextView, font: NSFont) {
        guard let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let totalLength = ns.length
        guard totalLength > 0 else { return }
        let wrapStart = CFAbsoluteTimeGetCurrent()

        let tabWidth = SettingsStore.shared.tabWidth
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let tabPixelWidth = spaceWidth * CGFloat(tabWidth)

        storage.beginEditing()
        var pos = 0
        while pos < totalLength {
            let lineRange = ns.lineRange(for: NSRange(location: pos, length: 0))
            let lineText = ns.substring(with: lineRange)

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

            // For list lines, indent wrapped text to content start (past the prefix)
            var headIndent = indent
            let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
            if (language == "plain" || language == "markdown"),
               let match = ListHelper.parseLine(cleanLine), ListHelper.isKindEnabled(match.kind) {
                headIndent = CGFloat(match.contentStart) * spaceWidth
            }

            let para = NSMutableParagraphStyle()
            para.headIndent = headIndent
            storage.addAttribute(.paragraphStyle, value: para, range: lineRange)

            pos = lineRange.location + lineRange.length
        }
        storage.endEditing()
        let wrapElapsed = (CFAbsoluteTimeGetCurrent() - wrapStart) * 1000
        if wrapElapsed > 4 {
            NSLog("[Perf] applyWrapIndent: %.1fms (%d chars)", wrapElapsed, totalLength)
        }
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? EditorTextView else { return }
        let text = tv.string
        tv.onTextChange?(text)
        updateCaretStatusAndHighlight()
        scheduleHighlightIfNeeded(text: text)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateCaretStatusAndHighlight()
    }

    private func updateCaretStatusAndHighlight() {
        guard let tv = textView else { return }
        let ns = tv.string as NSString

        tv.textStorage?.beginEditing()

        // Only clear the previously highlighted line, not the entire document
        if let prev = previousHighlightedLineRange, prev.location + prev.length <= ns.length {
            tv.textStorage?.removeAttribute(.backgroundColor, range: prev)
        }

        if SettingsStore.shared.highlightCurrentLine {
            let sel = tv.selectedRange()
            let location = min(sel.location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            tv.textStorage?.addAttribute(
                .backgroundColor,
                value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.12),
                range: lineRange
            )
            previousHighlightedLineRange = lineRange
        } else {
            previousHighlightedLineRange = nil
        }

        tv.textStorage?.endEditing()
    }
}
