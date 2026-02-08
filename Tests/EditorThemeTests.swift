import XCTest
@testable import ItsypadCore

final class EditorThemeTests: XCTestCase {

    // MARK: - color(for:)

    func testExactCaptureMatch() {
        let color = EditorTheme.dark.color(for: "keyword")
        XCTAssertNotEqual(color, EditorTheme.dark.foreground)
    }

    func testPrefixFallback() {
        // "keyword.function" exists, but "keyword.function.definition" should fall back to "keyword.function"
        let exact = EditorTheme.dark.color(for: "keyword.function")
        let fallback = EditorTheme.dark.color(for: "keyword.function.definition")
        XCTAssertEqual(exact, fallback)
    }

    func testDeepNesting() {
        // "string.special.key" exists in the theme
        let color = EditorTheme.dark.color(for: "string.special.key")
        let stringColor = EditorTheme.dark.color(for: "string")
        XCTAssertNotEqual(color, stringColor, "Deep nesting should match the more specific key")
    }

    func testUnknownCaptureFallsToForeground() {
        let color = EditorTheme.dark.color(for: "nonexistent.category")
        XCTAssertEqual(color, EditorTheme.dark.foreground)
    }

    func testEmptyCaptureFallsToForeground() {
        let color = EditorTheme.dark.color(for: "")
        XCTAssertEqual(color, EditorTheme.dark.foreground)
    }

    // MARK: - Theme properties

    func testDarkThemeIsDark() {
        XCTAssertTrue(EditorTheme.dark.isDark)
    }

    func testLightThemeIsNotDark() {
        XCTAssertFalse(EditorTheme.light.isDark)
    }

    func testDarkInsertionPointColor() {
        XCTAssertEqual(EditorTheme.dark.insertionPointColor, .white)
    }

    func testLightInsertionPointColor() {
        XCTAssertEqual(EditorTheme.light.insertionPointColor, .black)
    }

    // MARK: - current(for:)

    func testCurrentForLight() {
        let theme = EditorTheme.current(for: "light")
        XCTAssertFalse(theme.isDark)
    }

    func testCurrentForDark() {
        let theme = EditorTheme.current(for: "dark")
        XCTAssertTrue(theme.isDark)
    }

    // MARK: - Structural

    func testLightAndDarkHaveSameCaptureKeys() {
        let darkKeys = Set(EditorTheme.dark.captures.keys)
        let lightKeys = Set(EditorTheme.light.captures.keys)
        XCTAssertEqual(darkKeys, lightKeys)
    }
}
