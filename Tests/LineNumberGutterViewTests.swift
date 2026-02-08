import XCTest
@testable import ItsypadCore

final class LineNumberGutterViewTests: XCTestCase {

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
}
