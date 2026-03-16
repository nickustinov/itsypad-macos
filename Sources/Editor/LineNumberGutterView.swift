import AppKit

final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?

    var showLineNumbers = true { didSet { needsDisplay = true } }
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

    // MARK: - Width calculation

    static func calculateWidth(lineCount: Int, font: NSFont) -> CGFloat {
        let digits = max(3, "\(lineCount)".count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        return CGFloat(digits) * digitWidth + 16
    }

    // MARK: - Visibility

    func updateVisibility(_ visible: Bool, lineCount: Int) {
        showLineNumbers = visible

        if let constraint = constraints.first(where: { $0.identifier == "gutterWidth" }) {
            constraint.constant = visible ? Self.calculateWidth(lineCount: lineCount, font: lineFont) : 1
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        bgColor.setFill()
        dirtyRect.fill()

        guard showLineNumbers,
              let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let textVisibleRect = textView.visibleRect
        let textContainerVisibleRect = visibleTextContainerRect(for: textView)
        let textContainerOrigin = textView.textContainerOrigin
        let ns = textView.string as NSString
        let totalLength = ns.length

        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineFont,
            .foregroundColor: lineColor,
        ]

        guard totalLength > 0 else {
            let s = "1" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(
                at: NSPoint(
                    x: bounds.width - size.width - Self.rightPadding,
                    y: textContainerOrigin.y
                ),
                withAttributes: attrs
            )
            return
        }

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: textContainerVisibleRect,
            in: textContainer
        )
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var lineNumber = Self.lineNumber(atCharacterLocation: visibleCharRange.location, in: ns)

        let glyphEnd = min(visibleGlyphRange.location + visibleGlyphRange.length, layoutManager.numberOfGlyphs)
        guard glyphEnd > visibleGlyphRange.location else { return }
        let drawRange = NSRange(location: visibleGlyphRange.location, length: glyphEnd - visibleGlyphRange.location)
        var lastCharIndex = -1

        var lastFragRect = NSRect.zero
        layoutManager.enumerateLineFragments(forGlyphRange: drawRange) { fragRect, _, _, fragGlyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: fragGlyphRange, actualGlyphRange: nil)
            guard charRange.location > lastCharIndex else { return }

            let isNewLine = charRange.location == 0 || ns.character(at: charRange.location - 1) == 0x0A
            if isNewLine {
                let y = fragRect.origin.y + textContainerOrigin.y - textVisibleRect.origin.y
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
            lastFragRect = fragRect
        }

        // Draw line number for trailing empty line after final newline
        if totalLength > 0, ns.character(at: totalLength - 1) == 0x0A {
            let y = lastFragRect.maxY + textContainerOrigin.y - textVisibleRect.origin.y
            let lineStr = "\(lineNumber)" as NSString
            let size = lineStr.size(withAttributes: attrs)
            lineStr.draw(
                at: NSPoint(x: bounds.width - size.width - Self.rightPadding,
                            y: y + (lastFragRect.height - size.height) / 2),
                withAttributes: attrs
            )
        }
    }

    static func lineNumber(atCharacterLocation location: Int, in text: NSString) -> Int {
        let scanEnd = min(max(0, location), text.length)
        guard scanEnd > 0 else { return 1 }

        var completedLines = 0
        (text as String).enumerateSubstrings(
            in: Range(NSRange(location: 0, length: scanEnd), in: text as String) ?? (text as String).startIndex..<(text as String).startIndex,
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in
            completedLines += 1
        }
        return completedLines + 1
    }

    private func visibleTextContainerRect(for textView: NSTextView) -> NSRect {
        let origin = textView.textContainerOrigin
        return textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
    }
}
