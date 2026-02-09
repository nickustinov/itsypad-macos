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

    // MARK: - Strong early returns

    func testImportSwiftUI() {
        let result = detector.detect(text: "import SwiftUI\nstruct ContentView: View {}", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "swift")
        XCTAssertEqual(result.confidence, 95)
    }

    func testImportAppKit() {
        let result = detector.detect(text: "import AppKit", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "swift")
        XCTAssertEqual(result.confidence, 95)
    }

    func testAtMainStruct() {
        let result = detector.detect(text: "@main\nstruct MyApp {}", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "swift")
        XCTAssertEqual(result.confidence, 90)
    }

    func testGuardStatement() {
        let result = detector.detect(text: "guard let x = y else { return }", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "swift")
        XCTAssertEqual(result.confidence, 85)
    }

    func testPublishedProperty() {
        let result = detector.detect(text: "@Published var name: String", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "swift")
        XCTAssertEqual(result.confidence, 85)
    }

    // MARK: - Quick checks

    func testJSONObject() {
        let result = detector.detect(text: "{\"key\": \"value\"}", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "json")
        XCTAssertEqual(result.confidence, 80)
    }

    func testJSONArray() {
        let result = detector.detect(text: "[{\"id\": 1}]", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "json")
        XCTAssertEqual(result.confidence, 80)
    }

    func testHTMLDoctype() {
        let result = detector.detect(text: "<!DOCTYPE html>\n<html>", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "html")
        XCTAssertEqual(result.confidence, 85)
    }

    func testBashShebang() {
        let result = detector.detect(text: "#!/bin/bash\necho hello", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "bash")
        XCTAssertEqual(result.confidence, 90)
    }

    func testZshShebang() {
        let result = detector.detect(text: "#!/bin/zsh\necho hello", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "zsh")
        XCTAssertEqual(result.confidence, 90)
    }

    // MARK: - Scoring

    func testCppInclude() {
        let result = detector.detect(text: "#include <iostream>\nstd::cout << \"hello\";", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "cpp")
    }

    func testGoPackageAndFunc() {
        let result = detector.detect(text: "package main\n\nfunc main() {\n\tfmt.Println(\"hello\")\n}", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "go")
    }

    func testPythonDef() {
        let result = detector.detect(text: "\ndef hello():\n    print('hi')", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "python")
    }

    func testPythonImportAtStart() {
        let result = detector.detect(text: "import os\nimport sys\n\ndef main():\n    print('hi')", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "python")
    }

    func testPythonFromImportAtStart() {
        let result = detector.detect(text: "from collections import defaultdict\n\ndef solve():\n    pass", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "python")
    }

    func testPlainTextWithCodeKeywords() {
        let text = "This article discusses #include directives, Go's := operator, and the function keyword."
        let result = detector.detect(text: text, name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "plain")
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
