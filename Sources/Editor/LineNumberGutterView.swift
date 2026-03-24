import AppKit

final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?

    var showLineNumbers = true { didSet { needsDisplay = true } }
    var lineFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular) { didSet { needsDisplay = true } }
    var lineColor: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    var bgColor: NSColor = .textBackgroundColor { didSet { needsDisplay = true } }

    /// The editor's text font – used for baseline alignment between gutter numbers and text.
    var textFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular) { didSet { needsDisplay = true } }

    static let rightPadding: CGFloat = 8

    func attach(to scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        self.scrollView = scrollView

        textView.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(needsRedisplay),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(needsRedisplay),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(needsRedisplay),
            name: NSView.frameDidChangeNotification,
            object: textView
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

        let string = textView.string as NSString
        let totalLength = string.length

        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineFont,
            .foregroundColor: lineColor,
        ]

        // Baseline offset: aligns gutter number baseline with text baseline.
        // In a flipped view, text baseline sits at fragmentRect.minY + font.ascender.
        let baselineOffset = textFont.ascender - lineFont.ascender

        // Convert text container origin to gutter coordinates.
        // This single conversion accounts for scrolling, insets, and coordinate systems.
        let containerOriginInGutter = self.convert(
            NSPoint(x: 0, y: textView.textContainerOrigin.y),
            from: textView
        )

        // Empty document
        guard totalLength > 0 else {
            let extraRect = layoutManager.extraLineFragmentRect
            if !extraRect.isEmpty {
                drawLineNumber(1, atFragmentY: extraRect.minY,
                               baselineOffset: baselineOffset,
                               yOffset: containerOriginInGutter.y, attrs: attrs)
            } else {
                drawLineNumber(1, atFragmentY: 0,
                               baselineOffset: baselineOffset,
                               yOffset: containerOriginInGutter.y, attrs: attrs)
            }
            return
        }

        // Determine visible character range
        let containerVisibleRect = textView.visibleRect.offsetBy(
            dx: -textView.textContainerOrigin.x,
            dy: -textView.textContainerOrigin.y
        )
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: containerVisibleRect,
            in: textContainer
        )
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange, actualGlyphRange: nil
        )

        var lineNumber = Self.lineNumber(atCharacterLocation: visibleCharRange.location, in: string)

        // Iterate by logical lines (not visual fragments)
        var charIndex = visibleCharRange.location
        while charIndex < NSMaxRange(visibleCharRange) {
            let lineRange = string.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )

            drawLineNumber(lineNumber, atFragmentY: lineRect.minY,
                           baselineOffset: baselineOffset,
                           yOffset: containerOriginInGutter.y, attrs: attrs)

            lineNumber += 1
            let nextIndex = NSMaxRange(lineRange)
            if nextIndex <= charIndex { break }
            charIndex = nextIndex
        }

        // Trailing empty line after final newline
        if string.character(at: totalLength - 1) == 0x0A,
           !layoutManager.extraLineFragmentRect.isEmpty {
            drawLineNumber(lineNumber, atFragmentY: layoutManager.extraLineFragmentRect.minY,
                           baselineOffset: baselineOffset,
                           yOffset: containerOriginInGutter.y, attrs: attrs)
        }
    }

    private func drawLineNumber(_ number: Int, atFragmentY fragmentY: CGFloat,
                                baselineOffset: CGFloat, yOffset: CGFloat,
                                attrs: [NSAttributedString.Key: Any]) {
        let lineStr = "\(number)" as NSString
        let size = lineStr.size(withAttributes: attrs)
        lineStr.draw(
            at: NSPoint(
                x: bounds.width - size.width - Self.rightPadding,
                y: yOffset + fragmentY + baselineOffset
            ),
            withAttributes: attrs
        )
    }

    // MARK: - Line number lookup

    static func lineNumber(atCharacterLocation location: Int, in text: NSString) -> Int {
        let scanEnd = min(max(0, location), text.length)
        guard scanEnd > 0 else { return 1 }

        var count = 1
        var searchStart = 0
        while searchStart < scanEnd {
            let found = text.range(of: "\n", range: NSRange(location: searchStart, length: scanEnd - searchStart))
            if found.location == NSNotFound { break }
            count += 1
            searchStart = found.location + 1
        }
        return count
    }
}
