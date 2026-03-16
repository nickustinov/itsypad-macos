import XCTest
@testable import ItsypadCore

final class LineNumberGutterViewTests: XCTestCase {

    private func firstVisibleLineNumber(in textView: NSTextView) -> Int? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }

        let origin = textView.textContainerOrigin
        let visibleRect = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: visibleRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return 1 }

        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        return LineNumberGutterView.lineNumber(
            atCharacterLocation: visibleCharRange.location,
            in: textView.string as NSString
        )
    }

    func testSingleDigitUsesMinThreeDigitsWidth() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let width1 = LineNumberGutterView.calculateWidth(lineCount: 1, font: font)
        let width9 = LineNumberGutterView.calculateWidth(lineCount: 9, font: font)
        // Both single-digit, both should use min 3 digits
        XCTAssertEqual(width1, width9)
    }

    func testWidthGrowsWithDigitCount() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let width3 = LineNumberGutterView.calculateWidth(lineCount: 999, font: font)
        let width4 = LineNumberGutterView.calculateWidth(lineCount: 1000, font: font)
        XCTAssertGreaterThan(width4, width3)
    }

    func testWidthIsAlwaysPositive() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let width = LineNumberGutterView.calculateWidth(lineCount: 0, font: font)
        XCTAssertGreaterThan(width, 0)
    }

    func testWidthConsistentForSameDigitCount() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let width100 = LineNumberGutterView.calculateWidth(lineCount: 100, font: font)
        let width500 = LineNumberGutterView.calculateWidth(lineCount: 500, font: font)
        XCTAssertEqual(width100, width500)
    }

    func testLineNumberLookupCountsDigitLedLinesNormally() {
        let content = (["a", "b", "c", "d", "e"] + (1...30).map { "\($0). item" }).joined(separator: "\n")
        let ns = content as NSString
        let targetLocation = ns.range(of: "15. item").location

        XCTAssertEqual(LineNumberGutterView.lineNumber(atCharacterLocation: targetLocation, in: ns), 20)
    }

    @MainActor
    func testFirstVisibleLineNumberAdvancesWhenScrollingOrderedLines() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 160))
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 220, height: 1200))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 12)
        textView.string = (["a", "b", "c", "d", "e"] + (1...40).map { "\($0). item" }).joined(separator: "\n")

        let highlighter = SyntaxHighlightCoordinator()
        highlighter.textView = textView
        highlighter.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        highlighter.language = "markdown"
        textView.delegate = highlighter
        highlighter.applyWrapIndent(to: textView, font: highlighter.font)

        scrollView.documentView = textView
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let gutter = LineNumberGutterView(frame: NSRect(x: 0, y: 0, width: 40, height: 160))
        gutter.attach(to: scrollView, textView: textView)

        XCTAssertEqual(firstVisibleLineNumber(in: textView), 1)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 220))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertEqual(firstVisibleLineNumber(in: textView), 15)
    }
}
