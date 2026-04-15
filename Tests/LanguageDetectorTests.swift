import XCTest
@testable import ItsypadCore

final class LanguageDetectorTests: XCTestCase {
    private let detector = LanguageDetector.shared

    // MARK: - Extension detection

    func testDetectSwiftExtension() {
        let result = detector.detect(text: "", name: "file.swift", fileURL: nil)
        XCTAssertEqual(result.lang, "swift")
        XCTAssertEqual(result.confidence, 100)
    }

    func testDetectPythonExtension() {
        let result = detector.detect(text: "", name: "script.py", fileURL: nil)
        XCTAssertEqual(result.lang, "python")
        XCTAssertEqual(result.confidence, 100)
    }

    func testDetectTSXExtension() {
        let result = detector.detect(text: "", name: "App.tsx", fileURL: nil)
        XCTAssertEqual(result.lang, "typescript")
    }

    func testDetectRustExtension() {
        let result = detector.detect(text: "", name: "main.rs", fileURL: nil)
        XCTAssertEqual(result.lang, "rust")
    }

    func testDetectYAMLExtension() {
        let result = detector.detect(text: "", name: "config.yml", fileURL: nil)
        XCTAssertEqual(result.lang, "yaml")
    }

    func testDetectHTMExtension() {
        let result = detector.detect(text: "", name: "page.htm", fileURL: nil)
        XCTAssertEqual(result.lang, "html")
    }

    func testUnknownExtension() {
        let result = detector.detect(text: "", name: "file.xyz", fileURL: nil)
        XCTAssertEqual(result.lang, "plain")
        XCTAssertEqual(result.confidence, 0)
    }

    func testFileURLExtensionTakesPrecedence() {
        let url = URL(fileURLWithPath: "/tmp/file.py")
        let result = detector.detect(text: "import SwiftUI", name: "file.swift", fileURL: url)
        XCTAssertEqual(result.lang, "python")
    }

    // MARK: - Edge cases

    func testEmptyText() {
        let result = detector.detect(text: "", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "plain")
        XCTAssertEqual(result.confidence, 0)
    }

    func testAmbiguousText() {
        let result = detector.detect(text: "hello world", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "plain")
        XCTAssertEqual(result.confidence, 0)
    }

    func testBulletDashesStayPlainText() {
        let text = "New features\n    – Home Assistant support\n    – Dual RGB + color temperature\n\nBug fixes\n    – Fix camera snapshot timer"
        let result = detector.detect(text: text, name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "plain")
    }

    // MARK: - Markdown content detection

    func testBoldTextDetectedAsMarkdown() {
        let result = detector.detect(text: "**hello**\n", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "markdown")
    }

    func testHeadingDetectedAsMarkdown() {
        let result = detector.detect(text: "# My heading\nSome text", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "markdown")
    }

    func testChecklistDetectedAsMarkdown() {
        let result = detector.detect(text: "- [ ] todo item\n- [x] done item", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "markdown")
    }

    func testLinkDetectedAsMarkdown() {
        let result = detector.detect(text: "Visit [example](https://example.com) for details", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "markdown")
    }

    func testHighlightMarkerDetectedAsMarkdown() {
        let result = detector.detect(text: "This is ==important== text", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "markdown")
    }

    func testBlockquoteDetectedAsMarkdown() {
        let result = detector.detect(text: "> quoted text\nresponse", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "markdown")
    }

    func testTableDetectedAsMarkdown() {
        let table = """
        | Ingredient | 4:1 | 3:1 | 2:1 |
        | :--- | :--- | :--- | :--- |
        | A | 25.6 | 24.0 | 21.3 |
        | B | 6.4 | 8.0 | 10.7 |
        """
        let result = detector.detect(text: table, name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "markdown")
    }

    func testPipedPlainTextNotDetectedAsMarkdownTable() {
        let result = detector.detect(text: "a | b | c\nd | e | f", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "plain")
    }

    func testPlainTextNotDetectedAsMarkdown() {
        let result = detector.detect(text: "just some normal text", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "plain")
    }

    // MARK: - detectFromExtension

    func testDetectFromExtensionKnown() {
        XCTAssertEqual(detector.detectFromExtension(name: "file.swift"), "swift")
        XCTAssertEqual(detector.detectFromExtension(name: "file.py"), "python")
        XCTAssertEqual(detector.detectFromExtension(name: "file.js"), "javascript")
    }

    func testDetectFromExtensionUnknown() {
        XCTAssertNil(detector.detectFromExtension(name: "file.xyz"))
    }

    func testDetectFromExtensionNoExtension() {
        XCTAssertNil(detector.detectFromExtension(name: "Makefile"))
    }

    // MARK: - highlightrLanguage

    func testHighlightrLanguageSwift() {
        XCTAssertEqual(detector.highlightrLanguage(for: "swift"), "swift")
    }

    func testHighlightrLanguageObjectiveC() {
        XCTAssertEqual(detector.highlightrLanguage(for: "objective-c"), "objectivec")
    }

    func testHighlightrLanguageZsh() {
        XCTAssertEqual(detector.highlightrLanguage(for: "zsh"), "bash")
    }

    func testHighlightrLanguagePlain() {
        XCTAssertNil(detector.highlightrLanguage(for: "plain"))
    }

    func testHighlightrLanguagePassthrough() {
        XCTAssertEqual(detector.highlightrLanguage(for: "python"), "python")
        XCTAssertEqual(detector.highlightrLanguage(for: "javascript"), "javascript")
        XCTAssertEqual(detector.highlightrLanguage(for: "rust"), "rust")
    }
}
