import XCTest
@testable import ItsypadCore

final class MultiCursorHelpersTests: XCTestCase {

    // MARK: - wordRange(at:)

    func testWordRangeAtReturnsAlphanumericWord() {
        let text = "hello_world foo"
        let range = MultiCursorHelpers.wordRange(at: 7, in: text)
        XCTAssertNotNil(range)
        XCTAssertEqual(range, NSRange(location: 0, length: 11))
    }

    func testWordRangeAtUsesInsideCharacter() {
        let text = "hello world"
        let range = MultiCursorHelpers.wordRange(at: 1, in: text)
        XCTAssertEqual(range, NSRange(location: 0, length: 5))
    }

    func testWordRangeAtRejectsPunctuation() {
        let text = "hello-world"
        XCTAssertNil(MultiCursorHelpers.wordRange(at: 5, in: text))
    }

    func testWordRangeAtEndOfDocument() {
        let text = "hello"
        let range = MultiCursorHelpers.wordRange(at: 5, in: text)
        XCTAssertEqual(range, NSRange(location: 0, length: 5))
    }

    // MARK: - nextWholeWordMatch(of:after:)

    func testNextWholeWordMatchIsCaseSensitive() {
        let text = "Cat cats cat"
        let first = MultiCursorHelpers.nextWholeWordMatch(of: "cat", after: 4, in: text)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, NSRange(location: 9, length: 3))
    }

    func testNextWholeWordMatchSkipsPartialMatches() {
        let text = "cat catalog cat"
        let first = MultiCursorHelpers.nextWholeWordMatch(of: "cat", after: 4, in: text)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, NSRange(location: 12, length: 3))
    }

    func testNextWholeWordMatchNoResultWhenNone() {
        let text = "concatenate"
        XCTAssertNil(MultiCursorHelpers.nextWholeWordMatch(of: "cat", after: 0, in: text))
    }

    // MARK: - splitSelectionIntoLineCursors(selectedRanges:in:)

    func testSplitSelectionIntoLineCursorsWithMultiLineRange() {
        let text = "a\nb\nc\n"
        let cursors = MultiCursorHelpers.splitSelectionIntoLineCursors(
            selectedRanges: [NSRange(location: 0, length: 5)],
            in: text
        )
        XCTAssertEqual(cursors, [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0), NSRange(location: 4, length: 0)])
    }

    func testSplitSelectionIntoLineCursorsWithEmptyLine() {
        let text = "a\n\n"
        let cursors = MultiCursorHelpers.splitSelectionIntoLineCursors(
            selectedRanges: [NSRange(location: 0, length: 3)],
            in: text
        )
        XCTAssertEqual(cursors, [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)])
    }

    func testSplitSelectionIntoLineCursorsIgnoresSingleLineSelection() {
        let text = "a\nb\n"
        let cursors = MultiCursorHelpers.splitSelectionIntoLineCursors(
            selectedRanges: [NSRange(location: 0, length: 1)],
            in: text
        )
        XCTAssertTrue(cursors.isEmpty)
    }

    // MARK: - addCursorToAdjacentLine(from:direction:in:)

    func testAddCursorToAdjacentLineClampsToLineLength() {
        let text = "short\nlo\n"
        let added = MultiCursorHelpers.addCursorToAdjacentLine(
            from: [NSRange(location: 4, length: 0)],
            direction: .down,
            in: text
        )
        XCTAssertEqual(added, [NSRange(location: 8, length: 0)])
    }

    func testAddCursorToAdjacentLineSkipsMissingLines() {
        let singleLine = "single"
        let addedUp = MultiCursorHelpers.addCursorToAdjacentLine(
            from: [NSRange(location: 2, length: 0)],
            direction: .up,
            in: singleLine
        )
        let addedDown = MultiCursorHelpers.addCursorToAdjacentLine(
            from: [NSRange(location: 2, length: 0)],
            direction: .down,
            in: singleLine
        )
        XCTAssertTrue(addedUp.isEmpty)
        XCTAssertTrue(addedDown.isEmpty)
    }
}
