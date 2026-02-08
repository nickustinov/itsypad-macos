import XCTest
@testable import ItsypadCore

final class ShortcutKeysTests: XCTestCase {

    func testCodableRoundtrip() throws {
        let keys = ShortcutKeys(modifiers: 256, keyCode: 58, isTripleTap: true, tapModifier: "left-option")
        let data = try JSONEncoder().encode(keys)
        let decoded = try JSONDecoder().decode(ShortcutKeys.self, from: data)
        XCTAssertEqual(keys, decoded)
    }

    func testCodableRoundtripWithNilTapModifier() throws {
        let keys = ShortcutKeys(modifiers: 256, keyCode: 58, isTripleTap: false, tapModifier: nil)
        let data = try JSONEncoder().encode(keys)
        let decoded = try JSONDecoder().decode(ShortcutKeys.self, from: data)
        XCTAssertEqual(keys, decoded)
        XCTAssertNil(decoded.tapModifier)
    }

    func testEqualSameValues() {
        let a = ShortcutKeys(modifiers: 256, keyCode: 58, isTripleTap: true, tapModifier: "left-option")
        let b = ShortcutKeys(modifiers: 256, keyCode: 58, isTripleTap: true, tapModifier: "left-option")
        XCTAssertEqual(a, b)
    }

    func testNotEqualDifferentValues() {
        let a = ShortcutKeys(modifiers: 256, keyCode: 58, isTripleTap: true, tapModifier: "left-option")
        let b = ShortcutKeys(modifiers: 512, keyCode: 58, isTripleTap: false, tapModifier: "left-command")
        XCTAssertNotEqual(a, b)
    }
}
