import AppKit
import CodeEditLanguages
import SwiftTreeSitter
import SwiftUI

// MARK: - NSTextView subclass

final class EditorTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    var onTextChange: ((String) -> Void)?

    // MARK: - Typing helpers

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let s = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        // Auto-indent on newline
        if s == "\n" {
            let ns = (string as NSString)
            let sel = selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let currentLine = ns.substring(with: NSRange(
                location: lineRange.location,
                length: max(0, sel.location - lineRange.location)
            ))
            let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
            super.insertText("\n" + indent, replacementRange: replacementRange)
            return
        }

        // Tab key — indent selection or insert indent
        if s == "\t" {
            let sel = selectedRange()
            if sel.length > 0 {
                indentSelectedLines()
                return
            }
            let store = SettingsStore.shared
            if store.indentUsingSpaces {
                let spaces = String(repeating: " ", count: store.tabWidth)
                super.insertText(spaces, replacementRange: replacementRange)
            } else {
                super.insertText("\t", replacementRange: replacementRange)
            }
            return
        }

        // Auto-close bracket pairs
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
        if let closing = pairs[s] {
            let sel = selectedRange()
            super.insertText(s + closing, replacementRange: replacementRange)
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let store = SettingsStore.shared
        guard store.indentUsingSpaces else {
            super.deleteBackward(sender)
            return
        }

        let sel = selectedRange()
        guard sel.length == 0, sel.location > 0 else {
            super.deleteBackward(sender)
            return
        }

        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let columnOffset = sel.location - lineRange.location
        let textBeforeCursor = ns.substring(with: NSRange(location: lineRange.location, length: columnOffset))

        // Only act if everything before cursor on this line is spaces
        guard !textBeforeCursor.isEmpty, textBeforeCursor.allSatisfy({ $0 == " " }) else {
            super.deleteBackward(sender)
            return
        }

        let width = store.tabWidth
        let toDelete = ((columnOffset - 1) % width) + 1
        let deleteRange = NSRange(location: sel.location - toDelete, length: toDelete)
        if shouldChangeText(in: deleteRange, replacementString: "") {
            textStorage?.replaceCharacters(in: deleteRange, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: deleteRange.location, length: 0))
        }
    }

    // MARK: - Block indent / unindent

    override func insertBacktab(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0 {
            unindentSelectedLines()
        } else {
            unindentCurrentLine()
        }
    }

    private func indentSelectedLines() {
        let store = SettingsStore.shared
        let indent = store.indentUsingSpaces ? String(repeating: " ", count: store.tabWidth) : "\t"
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)

        var newText = ""
        var addedChars = 0
        ns.substring(with: lineRange).enumerateLines { line, _ in
            newText += indent + line + "\n"
            addedChars += indent.count
        }
        // Remove trailing newline if original didn't end with one
        if lineRange.location + lineRange.length <= ns.length,
           !ns.substring(with: lineRange).hasSuffix("\n") {
            newText = String(newText.dropLast())
        }

        if shouldChangeText(in: lineRange, replacementString: newText) {
            textStorage?.replaceCharacters(in: lineRange, with: newText)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: newText.count))
        }
    }

    private func unindentCurrentLine() {
        let store = SettingsStore.shared
        let width = store.tabWidth
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = ns.substring(with: lineRange)

        let toRemove: Int
        if line.hasPrefix("\t") {
            toRemove = 1
        } else {
            let spaces = line.prefix { $0 == " " }
            toRemove = min(spaces.count, width)
        }
        guard toRemove > 0 else { return }

        let removeRange = NSRange(location: lineRange.location, length: toRemove)
        if shouldChangeText(in: removeRange, replacementString: "") {
            textStorage?.replaceCharacters(in: removeRange, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: max(lineRange.location, sel.location - toRemove), length: 0))
        }
    }

    private func unindentSelectedLines() {
        let store = SettingsStore.shared
        let width = store.tabWidth
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)

        var newText = ""
        ns.substring(with: lineRange).enumerateLines { line, _ in
            if line.hasPrefix("\t") {
                newText += String(line.dropFirst()) + "\n"
            } else {
                let spaces = line.prefix { $0 == " " }
                let toRemove = min(spaces.count, width)
                newText += String(line.dropFirst(toRemove)) + "\n"
            }
        }
        if lineRange.location + lineRange.length <= ns.length,
           !ns.substring(with: lineRange).hasSuffix("\n") {
            newText = String(newText.dropLast())
        }

        if shouldChangeText(in: lineRange, replacementString: newText) {
            textStorage?.replaceCharacters(in: lineRange, with: newText)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: newText.count))
        }
    }

    // MARK: - Duplicate line (Cmd+D)

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "d" {
            duplicateLine()
            return
        }
        super.keyDown(with: event)
    }

    private func duplicateLine() {
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)
        let lineText = ns.substring(with: lineRange)

        let insertAt: Int
        let insertion: String
        if lineText.hasSuffix("\n") {
            insertAt = lineRange.location + lineRange.length
            insertion = lineText
        } else {
            insertAt = lineRange.location + lineRange.length
            insertion = "\n" + lineText
        }

        let insertRange = NSRange(location: insertAt, length: 0)
        if shouldChangeText(in: insertRange, replacementString: insertion) {
            textStorage?.replaceCharacters(in: insertRange, with: insertion)
            didChangeText()
            let newCursorPos = sel.location + insertion.count
            setSelectedRange(NSRange(location: newCursorPos, length: sel.length))
        }
    }
}

// MARK: - Syntax highlighting coordinator

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

        // No query available — uniform color, no syntax highlighting
        if currentQuery == nil {
            let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
            let sel = tv.selectedRange()
            tv.textStorage?.beginEditing()
            tv.textStorage?.setAttributes([
                .font: userFont,
                .foregroundColor: currentTheme.foreground,
            ], range: fullRange)
            tv.textStorage?.endEditing()
            let safeLocation = min(sel.location, (tv.string as NSString).length)
            let safeLength = min(sel.length, (tv.string as NSString).length - safeLocation)
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

        let isPlain = language == "plain"

        let work = DispatchWorkItem { [weak self] in
            guard let tree = parser.parse(textSnapshot) else { return }

            // Use SwiftTreeSitter's built-in highlights() — sorted less-specific first
            let cursor = query.execute(in: tree)
            let namedRanges = cursor.highlights().filter { nr in
                // Skip non-highlight captures from folds/indents/locals .scm files
                let first = nr.nameComponents.first ?? ""
                return first != "fold" && first != "indent" && first != "local"
            }

            // For plain text, find leading dashes at any indent level (regex on background queue)
            var dashRanges: [NSRange] = []
            if isPlain {
                let ns = textSnapshot as NSString
                if let regex = try? NSRegularExpression(pattern: "^[ \\t]+-(?= )", options: .anchorsMatchLines) {
                    let matches = regex.matches(in: textSnapshot, range: NSRange(location: 0, length: ns.length))
                    for match in matches {
                        let r = match.range
                        // Color just the dash: last character before the space
                        dashRanges.append(NSRange(location: r.location + r.length - 1, length: 1))
                    }
                }
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

                // Apply indented dash colors for plain text
                let dashColor = currentTheme.color(for: "punctuation.special")
                for range in dashRanges {
                    guard range.location + range.length <= fullRange.length else { continue }
                    tv.textStorage?.addAttribute(.foregroundColor, value: dashColor, range: range)
                }

                tv.textStorage?.endEditing()

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

// MARK: - Line number gutter

final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?

    var lineFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular) { didSet { needsDisplay = true } }
    var lineColor: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    var bgColor: NSColor = .textBackgroundColor { didSet { needsDisplay = true } }

    private static let rightPadding: CGFloat = 8

    func attach(to scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        self.scrollView = scrollView

        NotificationCenter.default.addObserver(
            self, selector: #selector(needsRedisplay),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(needsRedisplay),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @objc private func needsRedisplay() { needsDisplay = true }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        bgColor.setFill()
        dirtyRect.fill()

        guard let textView, let scrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView.contentView.bounds
        let inset = textView.textContainerInset
        let ns = textView.string as NSString
        let totalLength = ns.length

        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineFont,
            .foregroundColor: lineColor,
        ]

        guard totalLength > 0 else {
            let s = "1" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: bounds.width - size.width - Self.rightPadding, y: inset.height), withAttributes: attrs)
            return
        }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        let scanEnd = min(visibleCharRange.location, totalLength)
        if scanEnd > 0 {
            let pre = ns.substring(with: NSRange(location: 0, length: scanEnd))
            for ch in pre where ch == "\n" { lineNumber += 1 }
        }

        let glyphEnd = min(visibleGlyphRange.location + visibleGlyphRange.length, layoutManager.numberOfGlyphs)
        guard glyphEnd > visibleGlyphRange.location else { return }
        let drawRange = NSRange(location: visibleGlyphRange.location, length: glyphEnd - visibleGlyphRange.location)
        var lastCharIndex = -1

        layoutManager.enumerateLineFragments(forGlyphRange: drawRange) { fragRect, _, _, fragGlyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: fragGlyphRange, actualGlyphRange: nil)
            guard charRange.location > lastCharIndex else { return }

            let isNewLine = charRange.location == 0 || ns.character(at: charRange.location - 1) == 0x0A
            if isNewLine {
                let y = fragRect.origin.y + inset.height - visibleRect.origin.y
                let lineStr = "\(lineNumber)" as NSString
                let size = lineStr.size(withAttributes: attrs)
                lineStr.draw(
                    at: NSPoint(x: self.bounds.width - size.width - Self.rightPadding,
                                y: y + (fragRect.height - size.height) / 2),
                    withAttributes: attrs
                )
                lineNumber += 1
            }
            lastCharIndex = charRange.location
        }
    }
}
