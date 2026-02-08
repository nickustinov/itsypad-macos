import XCTest
import Carbon.HIToolbox
@testable import ItsypadCore

final class ModifierKeyDetectionTests: XCTestCase {

    func testLeftOption() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_Option), flags: .option)
        XCTAssertEqual(result, "left-option")
    }

    func testRightOption() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_RightOption), flags: .option)
        XCTAssertEqual(result, "right-option")
    }

    func testLeftCommand() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_Command), flags: .command)
        XCTAssertEqual(result, "left-command")
    }

    func testRightCommand() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_RightCommand), flags: .command)
        XCTAssertEqual(result, "right-command")
    }

    func testLeftControl() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_Control), flags: .control)
        XCTAssertEqual(result, "left-control")
    }

    func testRightControl() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_RightControl), flags: .control)
        XCTAssertEqual(result, "right-control")
    }

    func testLeftShift() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_Shift), flags: .shift)
        XCTAssertEqual(result, "left-shift")
    }

    func testRightShift() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_RightShift), flags: .shift)
        XCTAssertEqual(result, "right-shift")
    }

    func testKeyCodeWithWrongFlag() {
        // Option key code but command flag
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_Option), flags: .command)
        XCTAssertNil(result)
    }

    func testUnknownKeyCode() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_ANSI_A), flags: .option)
        XCTAssertNil(result)
    }

    func testEmptyFlags() {
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_Option), flags: [])
        XCTAssertNil(result)
    }

    func testMultipleFlags() {
        // Option key with both option and command flags should still work
        let result = ModifierKeyDetection.modifierName(for: UInt16(kVK_Option), flags: [.option, .command])
        XCTAssertEqual(result, "left-option")
    }
}
