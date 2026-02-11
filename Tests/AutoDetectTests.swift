import XCTest
@testable import ItsypadCore

final class AutoDetectTests: XCTestCase {
    private let detector = LanguageDetector.shared

    // MARK: - Content-based auto-detection via highlight.js

    func testAutoDetectPython() {
        let code = "import os\n\n# comment\ndef greet(name):\n    print(f\"Hello {name}\")\n    x = 42\n    return True"
        assertDetects(code, as: "python")
    }

    func testAutoDetectJavaScript() {
        let code = "// comment\nconst x = 42;\nfunction greet(name) {\n    return `Hello ${name}`;\n}\nconsole.log(greet('world'));"
        assertDetects(code, as: "javascript")
    }

    func testAutoDetectJavaScriptClass() {
        let code = """
        export default class MonokaiPro {
            constructor() {
                this.theme = 'Monokai Pro';
                this.numIcons = 70;
            }

            // set color scheme, UI, icon pack
            setTheme(theme) {
                this.theme = theme;

                console.log(`theme: ${theme}`)
            }
        }
        """
        assertDetects(code, as: "javascript")
    }

    func testAutoDetectSwift() {
        let code = "import SwiftUI\n\n// comment\nstruct App {\n    let name = \"Itsypad\"\n    func run() {\n        guard let x = opt else { return }\n        print(x)\n    }\n}"
        assertDetects(code, as: "swift")
    }

    func testAutoDetectPHP() {
        let code = "<?php\n$name = \"World\";\nfunction greet($who) {\n    echo \"Hello \" . $who;\n}\nforeach ($items as $item) {\n    print_r($item);\n}"
        assertDetects(code, as: "php")
    }

    func testAutoDetectGo() {
        let code = "package main\n\nimport \"fmt\"\n\nfunc main() {\n    x := 42\n    fmt.Println(\"hello\")\n}"
        assertDetects(code, as: "go")
    }

    func testAutoDetectRust() {
        let code = "use std::collections::HashMap;\n\n// comment\nfn main() {\n    let mut x = 42;\n    println!(\"value: {}\", x);\n}"
        assertDetects(code, as: "rust")
    }

    func testAutoDetectCpp() {
        let code = "#include <stdio.h>\n\n// comment\nint main() {\n    printf(\"hello %d\", 42);\n    return 0;\n}"
        assertDetects(code, as: "cpp")
    }

    func testAutoDetectBash() {
        let code = "#!/bin/bash\n# comment\nNAME=\"World\"\necho \"Hello $NAME\"\nx=42"
        assertDetects(code, as: "bash")
    }

    func testAutoDetectJSON() {
        let code = "{\n    \"name\": \"Itsypad\",\n    \"version\": 1,\n    \"enabled\": true,\n    \"data\": null\n}"
        assertDetects(code, as: "json")
    }

    func testAutoDetectHTML() {
        let code = "<!DOCTYPE html>\n<html>\n<body>\n    <div class=\"main\">\n        <a href=\"https://example.com\">Link</a>\n    </div>\n</body>\n</html>"
        assertDetects(code, as: "html")
    }

    // MARK: - Plain text stays plain

    func testPlainTextNotMisdetected() {
        let texts = [
            "Hello world",
            "Meeting at 3pm tomorrow",
            "Good ones to test:\n\n    1. Python — decorators\n    2. Go — goroutines\n    3. Rust — lifetimes",
            "New features\n    – Home Assistant support\n    – Dual RGB + color temperature",
            // Checklists with words that overlap SQL/CSS keywords
            "App release checklist\n\n– [x] Write release notes\n– [x] Update version to 1.5.0\n– [ ] Submit to App Store review\n\nPriority tasks\n\n1. Final round of QA testing\n2. Record demo video for product page\n3. Update landing page\n4. Send preview build to beta testers",
            // Todo lists with nested dashes
            "itsyhome.app – todo\n    – tomorrow\n        – HN post follow up\n        – No doorbell ring in HA\n    – fix streamdeck for HA\n\napps\n    – itsyhome\n    – itsytv\n    – itsypad\n        – global search",
            // Meeting notes with "key: value"-like patterns
            "Meeting notes\n\nAttendees: John, Sarah, Mike\nAction items:\n- Review the Q4 report by Friday\n- Send updated proposal to client\nBudget approved for $50,000.\nDeadline is March 15.",
        ]
        for text in texts {
            let result = detector.detect(text: text, name: nil, fileURL: nil)
            XCTAssertEqual(result.lang, "plain", "Plain text misdetected as \(result.lang): \(text.prefix(40))...")
        }
    }

    // MARK: - Helpers

    private func assertDetects(_ code: String, as expected: String, file: StaticString = #file, line: UInt = #line) {
        let result = detector.detect(text: code, name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, expected, "Expected \(expected) but got \(result.lang) (confidence \(result.confidence))", file: file, line: line)
        XCTAssertGreaterThan(result.confidence, 0, file: file, line: line)
    }
}
