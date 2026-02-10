import XCTest
@testable import ItsypadCore

final class ListHelperTests: XCTestCase {

    // MARK: - parseLine: bullets

    func testParseBulletDash() {
        let match = ListHelper.parseLine("- hello")
        XCTAssertEqual(match?.kind, .bullet("-"))
        XCTAssertEqual(match?.prefix, "- ")
        XCTAssertEqual(match?.indent, "")
        XCTAssertEqual(match?.contentStart, 2)
    }

    func testParseBulletAsterisk() {
        let match = ListHelper.parseLine("* hello")
        XCTAssertEqual(match?.kind, .bullet("*"))
        XCTAssertEqual(match?.prefix, "* ")
        XCTAssertEqual(match?.contentStart, 2)
    }

    func testParseBulletWithIndent() {
        let match = ListHelper.parseLine("    - indented")
        XCTAssertEqual(match?.indent, "    ")
        XCTAssertEqual(match?.prefix, "- ")
        XCTAssertEqual(match?.contentStart, 6)
    }

    func testParseBulletWithTabIndent() {
        let match = ListHelper.parseLine("\t- tabbed")
        XCTAssertEqual(match?.indent, "\t")
        XCTAssertEqual(match?.prefix, "- ")
        XCTAssertEqual(match?.contentStart, 3)
    }

    func testParseDashWithoutSpaceIsNotBullet() {
        let match = ListHelper.parseLine("-nospace")
        XCTAssertNil(match)
    }

    // MARK: - parseLine: ordered

    func testParseOrdered() {
        let match = ListHelper.parseLine("1. first")
        XCTAssertEqual(match?.kind, .ordered(1))
        XCTAssertEqual(match?.prefix, "1. ")
        XCTAssertEqual(match?.contentStart, 3)
    }

    func testParseOrderedMultiDigit() {
        let match = ListHelper.parseLine("  12. twelfth")
        XCTAssertEqual(match?.kind, .ordered(12))
        XCTAssertEqual(match?.indent, "  ")
        XCTAssertEqual(match?.prefix, "12. ")
        XCTAssertEqual(match?.contentStart, 6)
    }

    func testParseOrderedWithoutSpaceIsNotList() {
        let match = ListHelper.parseLine("1.nospace")
        XCTAssertNil(match)
    }

    // MARK: - parseLine: checkboxes

    func testParseUnchecked() {
        let match = ListHelper.parseLine("- [ ] todo")
        XCTAssertEqual(match?.kind, .unchecked)
        XCTAssertEqual(match?.prefix, "- [ ] ")
        XCTAssertEqual(match?.contentStart, 6)
    }

    func testParseChecked() {
        let match = ListHelper.parseLine("- [x] done")
        XCTAssertEqual(match?.kind, .checked)
        XCTAssertEqual(match?.prefix, "- [x] ")
        XCTAssertEqual(match?.contentStart, 6)
    }

    func testParseUncheckedWithIndent() {
        let match = ListHelper.parseLine("  - [ ] indented task")
        XCTAssertEqual(match?.kind, .unchecked)
        XCTAssertEqual(match?.indent, "  ")
        XCTAssertEqual(match?.contentStart, 8)
    }

    func testParseCheckedWithAsterisk() {
        let match = ListHelper.parseLine("* [x] done")
        XCTAssertEqual(match?.kind, .checked)
        XCTAssertEqual(match?.prefix, "* [x] ")
    }

    // MARK: - parseLine: non-matches

    func testParsePlainText() {
        XCTAssertNil(ListHelper.parseLine("hello world"))
    }

    func testParseEmptyString() {
        XCTAssertNil(ListHelper.parseLine(""))
    }

    func testParseOnlyWhitespace() {
        XCTAssertNil(ListHelper.parseLine("   "))
    }

    // MARK: - nextPrefix

    func testNextPrefixForBullet() {
        let match = ListHelper.parseLine("- item")!
        XCTAssertEqual(ListHelper.nextPrefix(for: match), "- ")
    }

    func testNextPrefixForAsterisk() {
        let match = ListHelper.parseLine("* item")!
        XCTAssertEqual(ListHelper.nextPrefix(for: match), "* ")
    }

    func testNextPrefixForOrdered() {
        let match = ListHelper.parseLine("1. first")!
        XCTAssertEqual(ListHelper.nextPrefix(for: match), "2. ")
    }

    func testNextPrefixForOrderedMultiDigit() {
        let match = ListHelper.parseLine("9. ninth")!
        XCTAssertEqual(ListHelper.nextPrefix(for: match), "10. ")
    }

    func testNextPrefixForUnchecked() {
        let match = ListHelper.parseLine("- [ ] task")!
        XCTAssertEqual(ListHelper.nextPrefix(for: match), "- [ ] ")
    }

    func testNextPrefixForChecked() {
        let match = ListHelper.parseLine("- [x] done")!
        XCTAssertEqual(ListHelper.nextPrefix(for: match), "- [ ] ")
    }

    func testNextPrefixPreservesIndent() {
        let match = ListHelper.parseLine("    - item")!
        XCTAssertEqual(ListHelper.nextPrefix(for: match), "    - ")
    }

    func testNextPrefixPreservesIndentOrdered() {
        let match = ListHelper.parseLine("  3. third")!
        XCTAssertEqual(ListHelper.nextPrefix(for: match), "  4. ")
    }

    // MARK: - isEmptyItem

    func testIsEmptyItemTrue() {
        let line = "- "
        let match = ListHelper.parseLine(line)!
        XCTAssertTrue(ListHelper.isEmptyItem(line, match: match))
    }

    func testIsEmptyItemTrueOrdered() {
        let line = "1. "
        let match = ListHelper.parseLine(line)!
        XCTAssertTrue(ListHelper.isEmptyItem(line, match: match))
    }

    func testIsEmptyItemTrueChecklist() {
        let line = "- [ ] "
        let match = ListHelper.parseLine(line)!
        XCTAssertTrue(ListHelper.isEmptyItem(line, match: match))
    }

    func testIsEmptyItemFalse() {
        let line = "- content"
        let match = ListHelper.parseLine(line)!
        XCTAssertFalse(ListHelper.isEmptyItem(line, match: match))
    }

    func testIsEmptyItemWithIndent() {
        let line = "  - "
        let match = ListHelper.parseLine(line)!
        XCTAssertTrue(ListHelper.isEmptyItem(line, match: match))
    }

    // MARK: - toggleCheckbox

    func testToggleCheckboxUncheckedToChecked() {
        XCTAssertEqual(ListHelper.toggleCheckbox(in: "- [ ] task"), "- [x] task")
    }

    func testToggleCheckboxCheckedToUnchecked() {
        XCTAssertEqual(ListHelper.toggleCheckbox(in: "- [x] done"), "- [ ] done")
    }

    func testToggleCheckboxWithIndent() {
        XCTAssertEqual(ListHelper.toggleCheckbox(in: "  - [ ] task"), "  - [x] task")
    }

    func testToggleCheckboxNonCheckbox() {
        XCTAssertEqual(ListHelper.toggleCheckbox(in: "- plain"), "- plain")
    }

    func testToggleCheckboxPlainText() {
        XCTAssertEqual(ListHelper.toggleCheckbox(in: "hello"), "hello")
    }

    // MARK: - toggleChecklist

    func testToggleChecklistPlainToChecklist() {
        XCTAssertEqual(ListHelper.toggleChecklist(line: "some text"), "- [ ] some text")
    }

    func testToggleChecklistBulletToChecklist() {
        XCTAssertEqual(ListHelper.toggleChecklist(line: "- some text"), "- [ ] some text")
    }

    func testToggleChecklistAsteriskToChecklist() {
        XCTAssertEqual(ListHelper.toggleChecklist(line: "* some text"), "- [ ] some text")
    }

    func testToggleChecklistUncheckedToPlain() {
        XCTAssertEqual(ListHelper.toggleChecklist(line: "- [ ] some text"), "some text")
    }

    func testToggleChecklistCheckedToPlain() {
        XCTAssertEqual(ListHelper.toggleChecklist(line: "- [x] some text"), "some text")
    }

    func testToggleChecklistPreservesIndent() {
        XCTAssertEqual(ListHelper.toggleChecklist(line: "  - item"), "  - [ ] item")
    }

    func testToggleChecklistCheckedWithIndentToPlain() {
        XCTAssertEqual(ListHelper.toggleChecklist(line: "  - [x] done"), "  done")
    }

    func testToggleChecklistEmptyLine() {
        XCTAssertEqual(ListHelper.toggleChecklist(line: ""), "- [ ] ")
    }

    // MARK: - swapLines

    func testSwapLinesDown() {
        let text = "line one\nline two\nline three"
        let lineRange = NSRange(location: 0, length: 9) // "line one\n"
        let result = ListHelper.swapLines(text, lineRange: lineRange, direction: .down)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newText, "line two\nline one\nline three")
    }

    func testSwapLinesUp() {
        let text = "line one\nline two\nline three"
        let lineRange = NSRange(location: 9, length: 9) // "line two\n"
        let result = ListHelper.swapLines(text, lineRange: lineRange, direction: .up)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newText, "line two\nline one\nline three")
    }

    func testSwapLinesDownAtEnd() {
        let text = "line one\nline two"
        let lineRange = NSRange(location: 9, length: 8) // "line two"
        let result = ListHelper.swapLines(text, lineRange: lineRange, direction: .down)
        XCTAssertNil(result)
    }

    func testSwapLinesUpAtStart() {
        let text = "line one\nline two"
        let lineRange = NSRange(location: 0, length: 9) // "line one\n"
        let result = ListHelper.swapLines(text, lineRange: lineRange, direction: .up)
        XCTAssertNil(result)
    }

    func testSwapLinesDownLastTwoLines() {
        let text = "first\nsecond"
        let lineRange = NSRange(location: 0, length: 6) // "first\n"
        let result = ListHelper.swapLines(text, lineRange: lineRange, direction: .down)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newText, "second\nfirst")
    }

    func testSwapLinesCursorFollows() {
        let text = "line one\nline two\nline three"
        let lineRange = NSRange(location: 0, length: 9) // "line one\n"
        let result = ListHelper.swapLines(text, lineRange: lineRange, direction: .down)
        XCTAssertNotNil(result)
        // Cursor should be in the swapped-down line (now at position 9)
        XCTAssertEqual(result?.newSelection.location, 9)
    }
}
