import XCTest
@testable import ItsypadCore

final class ClipboardShortcutTests: XCTestCase {

    func testKeyCodeMappings() {
        XCTAssertEqual(clipboardNumberFromKeyCode(18), 1)
        XCTAssertEqual(clipboardNumberFromKeyCode(19), 2)
        XCTAssertEqual(clipboardNumberFromKeyCode(20), 3)
        XCTAssertEqual(clipboardNumberFromKeyCode(21), 4)
        XCTAssertEqual(clipboardNumberFromKeyCode(23), 5)
        XCTAssertEqual(clipboardNumberFromKeyCode(22), 6)
        XCTAssertEqual(clipboardNumberFromKeyCode(26), 7)
        XCTAssertEqual(clipboardNumberFromKeyCode(28), 8)
        XCTAssertEqual(clipboardNumberFromKeyCode(25), 9)
    }

    func testInvalidKeyCodesReturnNil() {
        XCTAssertNil(clipboardNumberFromKeyCode(0))
        XCTAssertNil(clipboardNumberFromKeyCode(17))
        XCTAssertNil(clipboardNumberFromKeyCode(24))
        XCTAssertNil(clipboardNumberFromKeyCode(27))
        XCTAssertNil(clipboardNumberFromKeyCode(29))
        XCTAssertNil(clipboardNumberFromKeyCode(100))
        XCTAssertNil(clipboardNumberFromKeyCode(UInt16.max))
    }
}
