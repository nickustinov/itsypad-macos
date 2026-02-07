import AppKit
import Highlightr
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
}

// MARK: - Syntax highlighting coordinator

class SyntaxHighlightCoordinator: NSObject, NSTextViewDelegate {
    weak var textView: EditorTextView?
    var language: String = "plain" {
        didSet {
            if language != oldValue { scheduleHighlightIfNeeded() }
        }
    }
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    private let highlightr: Highlightr
    private let highlightQueue = DispatchQueue(label: "Itsypad.SyntaxHighlight", qos: .userInitiated)
    private var pendingHighlight: DispatchWorkItem?
    private var highlightGeneration: Int = 0
    private var lastHighlightedText: String = ""
    private var lastLanguage: String?
    private var lastTheme: String?

    private static let catppuccinThemes: [String: String] = [
        "catppuccin-latte": "pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}.hljs{color:#4c4f69;background:#eff1f5}.hljs-keyword{color:#8839ef}.hljs-built_in{color:#d20f39}.hljs-type{color:#df8e1d}.hljs-literal{color:#fe640b}.hljs-number{color:#fe640b}.hljs-operator{color:#04a5e5}.hljs-punctuation{color:#5c5f77}.hljs-property{color:#179299}.hljs-regexp{color:#ea76cb}.hljs-string{color:#40a02b}.hljs-char.escape_{color:#40a02b}.hljs-subst{color:#6c6f85}.hljs-symbol{color:#dd7878}.hljs-variable{color:#8839ef}.hljs-variable.language_{color:#8839ef}.hljs-variable.constant_{color:#fe640b}.hljs-title{color:#1e66f5}.hljs-title.class_{color:#df8e1d}.hljs-title.function_{color:#1e66f5}.hljs-params{color:#4c4f69}.hljs-comment{color:#7c7f93}.hljs-doctag{color:#d20f39}.hljs-meta{color:#fe640b}.hljs-section{color:#8caaee}.hljs-tag{color:#179299}.hljs-name{color:#8839ef}.hljs-attr{color:#1e66f5}.hljs-attribute{color:#40a02b}.hljs-bullet{color:#179299}.hljs-code{color:#40a02b}.hljs-emphasis{color:#d20f39;font-style:italic}.hljs-strong{color:#d20f39;font-weight:700}.hljs-formula{color:#179299}.hljs-link{color:#209fb5;font-style:italic}.hljs-quote{color:#40a02b;font-style:italic}.hljs-selector-tag{color:#df8e1d}.hljs-selector-id{color:#1e66f5}.hljs-selector-class{color:#179299}.hljs-selector-attr{color:#8839ef}.hljs-selector-pseudo{color:#179299}.hljs-template-tag{color:#dd7878}.hljs-template-variable{color:#dd7878}.hljs-addition{color:#40a02b;background:rgba(64,160,43,.15)}.hljs-deletion{color:#d20f39;background:rgba(210,15,57,.15)}",
        "catppuccin-frappe": "pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}.hljs{color:#c6d0f5;background:#303446}.hljs-keyword{color:#ca9ee6}.hljs-built_in{color:#e78284}.hljs-type{color:#e5c890}.hljs-literal{color:#ef9f76}.hljs-number{color:#ef9f76}.hljs-operator{color:#99d1db}.hljs-punctuation{color:#b5bfe2}.hljs-property{color:#81c8be}.hljs-regexp{color:#f4b8e4}.hljs-string{color:#a6d189}.hljs-char.escape_{color:#a6d189}.hljs-subst{color:#a5adce}.hljs-symbol{color:#eebebe}.hljs-variable{color:#ca9ee6}.hljs-variable.language_{color:#ca9ee6}.hljs-variable.constant_{color:#ef9f76}.hljs-title{color:#8caaee}.hljs-title.class_{color:#e5c890}.hljs-title.function_{color:#8caaee}.hljs-params{color:#c6d0f5}.hljs-comment{color:#949cbb}.hljs-doctag{color:#e78284}.hljs-meta{color:#ef9f76}.hljs-section{color:#8caaee}.hljs-tag{color:#81c8be}.hljs-name{color:#ca9ee6}.hljs-attr{color:#8caaee}.hljs-attribute{color:#a6d189}.hljs-bullet{color:#81c8be}.hljs-code{color:#a6d189}.hljs-emphasis{color:#e78284;font-style:italic}.hljs-strong{color:#e78284;font-weight:700}.hljs-formula{color:#81c8be}.hljs-link{color:#85c1dc;font-style:italic}.hljs-quote{color:#a6d189;font-style:italic}.hljs-selector-tag{color:#e5c890}.hljs-selector-id{color:#8caaee}.hljs-selector-class{color:#81c8be}.hljs-selector-attr{color:#ca9ee6}.hljs-selector-pseudo{color:#81c8be}.hljs-template-tag{color:#eebebe}.hljs-template-variable{color:#eebebe}.hljs-addition{color:#a6d189;background:rgba(166,209,137,.15)}.hljs-deletion{color:#e78284;background:rgba(231,130,132,.15)}",
        "catppuccin-macchiato": "pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}.hljs{color:#cad3f5;background:#24273a}.hljs-keyword{color:#c6a0f6}.hljs-built_in{color:#ed8796}.hljs-type{color:#eed49f}.hljs-literal{color:#f5a97f}.hljs-number{color:#f5a97f}.hljs-operator{color:#91d7e3}.hljs-punctuation{color:#b8c0e0}.hljs-property{color:#8bd5ca}.hljs-regexp{color:#f5bde6}.hljs-string{color:#a6da95}.hljs-char.escape_{color:#a6da95}.hljs-subst{color:#a5adcb}.hljs-symbol{color:#f0c6c6}.hljs-variable{color:#c6a0f6}.hljs-variable.language_{color:#c6a0f6}.hljs-variable.constant_{color:#f5a97f}.hljs-title{color:#8aadf4}.hljs-title.class_{color:#eed49f}.hljs-title.function_{color:#8aadf4}.hljs-params{color:#cad3f5}.hljs-comment{color:#939ab7}.hljs-doctag{color:#ed8796}.hljs-meta{color:#f5a97f}.hljs-section{color:#8aadf4}.hljs-tag{color:#8bd5ca}.hljs-name{color:#c6a0f6}.hljs-attr{color:#8aadf4}.hljs-attribute{color:#a6da95}.hljs-bullet{color:#8bd5ca}.hljs-code{color:#a6da95}.hljs-emphasis{color:#ed8796;font-style:italic}.hljs-strong{color:#ed8796;font-weight:700}.hljs-formula{color:#8bd5ca}.hljs-link{color:#7dc4e4;font-style:italic}.hljs-quote{color:#a6da95;font-style:italic}.hljs-selector-tag{color:#eed49f}.hljs-selector-id{color:#8aadf4}.hljs-selector-class{color:#8bd5ca}.hljs-selector-attr{color:#c6a0f6}.hljs-selector-pseudo{color:#8bd5ca}.hljs-template-tag{color:#f0c6c6}.hljs-template-variable{color:#f0c6c6}.hljs-addition{color:#a6da95;background:rgba(166,218,149,.15)}.hljs-deletion{color:#ed8796;background:rgba(237,135,150,.15)}",
        "catppuccin-mocha": "pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}.hljs{color:#cdd6f4;background:#1e1e2e}.hljs-keyword{color:#cba6f7}.hljs-built_in{color:#f38ba8}.hljs-type{color:#f9e2af}.hljs-literal{color:#fab387}.hljs-number{color:#fab387}.hljs-operator{color:#89dceb}.hljs-punctuation{color:#bac2de}.hljs-property{color:#94e2d5}.hljs-regexp{color:#f5c2e7}.hljs-string{color:#a6e3a1}.hljs-char.escape_{color:#a6e3a1}.hljs-subst{color:#a6adc8}.hljs-symbol{color:#f2cdcd}.hljs-variable{color:#cba6f7}.hljs-variable.language_{color:#cba6f7}.hljs-variable.constant_{color:#fab387}.hljs-title{color:#89b4fa}.hljs-title.class_{color:#f9e2af}.hljs-title.function_{color:#89b4fa}.hljs-params{color:#cdd6f4}.hljs-comment{color:#9399b2}.hljs-doctag{color:#f38ba8}.hljs-meta{color:#fab387}.hljs-section{color:#89b4fa}.hljs-tag{color:#94e2d5}.hljs-name{color:#cba6f7}.hljs-attr{color:#89b4fa}.hljs-attribute{color:#a6e3a1}.hljs-bullet{color:#94e2d5}.hljs-code{color:#a6e3a1}.hljs-emphasis{color:#f38ba8;font-style:italic}.hljs-strong{color:#f38ba8;font-weight:700}.hljs-formula{color:#94e2d5}.hljs-link{color:#74c7ec;font-style:italic}.hljs-quote{color:#a6e3a1;font-style:italic}.hljs-selector-tag{color:#f9e2af}.hljs-selector-id{color:#89b4fa}.hljs-selector-class{color:#94e2d5}.hljs-selector-attr{color:#cba6f7}.hljs-selector-pseudo{color:#94e2d5}.hljs-template-tag{color:#f2cdcd}.hljs-template-variable{color:#f2cdcd}.hljs-addition{color:#a6e3a1;background:rgba(166,227,161,.15)}.hljs-deletion{color:#f38ba8;background:rgba(243,139,168,.15)}",
    ]

    override init() {
        highlightr = Highlightr()!
        super.init()
        installCustomThemes()
        highlightr.setTheme(to: "horizon-dark")
        SettingsStore.shared.availableThemes = highlightr.availableThemes().sorted()
    }

    private func installCustomThemes() {
        // Extract the private bundle from Highlightr via Mirror
        let mirror = Mirror(reflecting: highlightr)
        guard let bundleChild = mirror.children.first(where: { $0.label == "bundle" }),
              let hljsBundle = bundleChild.value as? Bundle,
              let resourcePath = hljsBundle.resourcePath else { return }

        for (name, css) in Self.catppuccinThemes {
            let filePath = (resourcePath as NSString).appendingPathComponent("\(name).min.css")
            try? css.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }

    var themeBackgroundColor: NSColor? {
        highlightr.theme?.themeBackgroundColor
    }

    func setTheme(to theme: String) {
        highlightr.setTheme(to: theme)
        lastTheme = nil
    }

    func scheduleHighlightIfNeeded() {
        guard let tv = textView else { return }
        let text = tv.string
        let lang = language
        let theme = highlightr.theme?.themeBackgroundColor?.description ?? ""

        if (text as NSString).length > 200_000 {
            lastHighlightedText = text
            lastLanguage = lang
            lastTheme = theme
            return
        }

        if text == lastHighlightedText && lastLanguage == lang && lastTheme == theme {
            return
        }

        rehighlight()
    }

    func rehighlight() {
        guard let tv = textView else { return }
        let textSnapshot = tv.string
        let userFont = font

        // Plain text — uniform color, no syntax highlighting
        if language == "plain" {
            let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
            let sel = tv.selectedRange()
            let fg: NSColor = { [highlightr = self.highlightr] in
                guard let bg = highlightr.theme?.themeBackgroundColor else { return .labelColor }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                (bg.usingColorSpace(.sRGB) ?? bg).getRed(&r, green: &g, blue: &b, alpha: nil)
                return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5 ? .white : .black
            }()
            tv.textStorage?.beginEditing()
            tv.textStorage?.setAttributes([.font: userFont, .foregroundColor: fg], range: fullRange)
            tv.textStorage?.endEditing()
            let safeLocation = min(sel.location, (tv.string as NSString).length)
            let safeLength = min(sel.length, (tv.string as NSString).length - safeLocation)
            tv.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            lastHighlightedText = textSnapshot
            lastLanguage = language
            lastTheme = highlightr.theme?.themeBackgroundColor?.description ?? ""
            return
        }

        highlightGeneration += 1
        let generation = highlightGeneration
        pendingHighlight?.cancel()

        let highlightr = self.highlightr
        let lang = language
        let work = DispatchWorkItem { [weak self] in
            guard let highlighted = highlightr.highlight(textSnapshot, as: lang) else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self, let tv = self.textView else { return }
                guard self.highlightGeneration == generation else { return }
                guard tv.string == textSnapshot else { return }

                let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
                let sel = tv.selectedRange()

                tv.textStorage?.beginEditing()

                // Apply Highlightr attributes
                highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length), options: []) { attrs, range, _ in
                    guard range.location + range.length <= fullRange.length else { return }
                    for (key, value) in attrs {
                        if key == .font { continue } // Skip Highlightr's font
                        tv.textStorage?.addAttribute(key, value: value, range: range)
                    }
                }

                // Override font with user's choice
                tv.textStorage?.addAttribute(.font, value: userFont, range: fullRange)

                tv.textStorage?.endEditing()

                // Restore selection
                let safeLocation = min(sel.location, (tv.string as NSString).length)
                let safeLength = min(sel.length, (tv.string as NSString).length - safeLocation)
                tv.setSelectedRange(NSRange(location: safeLocation, length: safeLength))

                self.lastHighlightedText = textSnapshot
                self.lastLanguage = self.language
                self.lastTheme = highlightr.theme?.themeBackgroundColor?.description ?? ""
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
