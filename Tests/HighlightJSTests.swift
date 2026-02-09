import XCTest
@testable import ItsypadCore

final class HighlightJSTests: XCTestCase {
    private static let hljs: HighlightJS = {
        let h = HighlightJS()
        let loaded = h.loadTheme(named: "itsypad-dark.min")
        assert(loaded, "Failed to load itsypad-dark theme")
        return h
    }()

    private let detector = LanguageDetector.shared

    // MARK: - Dark theme colors

    private static let keyword   = "#ff6188"
    private static let builtIn   = "#a9dc76"
    private static let function_ = "#a9dc76"
    private static let class_    = "#78dce8"
    private static let type_     = "#78dce8"
    private static let variable  = "#78dce8"
    private static let string_   = "#ffd866"
    private static let number_   = "#ab9df2"
    private static let literal   = "#ab9df2"
    private static let comment   = "#727072"
    private static let meta      = "#ff6188"
    private static let params    = "#fc9867"
    private static let attr      = "#a9dc76"
    private static let name_     = "#ff6188"
    private static let selClass  = "#a9dc76"
    private static let strong    = "#fc9867"
    private static let defaultFg = "#d4d4d4"

    // MARK: - Helpers

    /// Detect language from code, then highlight. Verifies detection returns expected language.
    private func detectAndHighlight(_ code: String, expected: String, file: StaticString = #file, line: UInt = #line) -> NSAttributedString {
        let detected = detector.detect(text: code, name: nil, fileURL: nil)
        XCTAssertEqual(detected.lang, expected, "Detection expected \(expected) but got \(detected.lang)", file: file, line: line)

        let hlLang = detector.highlightrLanguage(for: detected.lang)
        XCTAssertNotNil(hlLang, "highlightrLanguage returned nil for \(detected.lang)", file: file, line: line)

        let result = Self.hljs.highlight(code, as: hlLang ?? detected.lang)
        XCTAssertNotNil(result, "highlight returned nil for \(hlLang ?? detected.lang)", file: file, line: line)
        return result ?? NSAttributedString()
    }

    /// Highlight with explicit language (for languages without content-based detection).
    private func highlight(_ code: String, as language: String) -> NSAttributedString {
        let result = Self.hljs.highlight(code, as: language)
        XCTAssertNotNil(result, "highlight returned nil for \(language)")
        return result ?? NSAttributedString()
    }

    private func foregroundColor(in attrStr: NSAttributedString, at token: String, file: StaticString = #file, line: UInt = #line) -> NSColor? {
        let plainText = attrStr.string
        guard let range = plainText.range(of: token) else {
            XCTFail("Token \"\(token)\" not found in: \(plainText.prefix(200))", file: file, line: line)
            return nil
        }
        let nsRange = NSRange(range, in: plainText)
        return attrStr.attributes(at: nsRange.location, effectiveRange: nil)[.foregroundColor] as? NSColor
    }

    private func assertToken(_ token: String, in attrStr: NSAttributedString, hasColor hex: String, file: StaticString = #file, line: UInt = #line) {
        guard let color = foregroundColor(in: attrStr, at: token, file: file, line: line) else { return }
        let expected = colorFromHex(hex)
        guard let srgb = color.usingColorSpace(.sRGB),
              let eSrgb = expected.usingColorSpace(.sRGB) else {
            XCTFail("Could not convert colors to sRGB for \"\(token)\"", file: file, line: line)
            return
        }
        let tolerance: CGFloat = 0.02
        let dr = abs(srgb.redComponent - eSrgb.redComponent)
        let dg = abs(srgb.greenComponent - eSrgb.greenComponent)
        let db = abs(srgb.blueComponent - eSrgb.blueComponent)
        XCTAssert(
            dr <= tolerance && dg <= tolerance && db <= tolerance,
            "Color mismatch for \"\(token)\": got \(colorHex(srgb)), expected \(hex)",
            file: file, line: line
        )
    }

    /// Assert token is NOT the default foreground (i.e., it IS highlighted).
    private func assertHighlighted(_ token: String, in attrStr: NSAttributedString, file: StaticString = #file, line: UInt = #line) {
        guard let color = foregroundColor(in: attrStr, at: token, file: file, line: line) else { return }
        let srgb = color.usingColorSpace(.sRGB)
        let defaultColor = colorFromHex(Self.defaultFg).usingColorSpace(.sRGB)
        if let s = srgb, let d = defaultColor {
            let isSame = abs(s.redComponent - d.redComponent) < 0.02
                && abs(s.greenComponent - d.greenComponent) < 0.02
                && abs(s.blueComponent - d.blueComponent) < 0.02
            XCTAssertFalse(isSame, "\"\(token)\" has default color — not highlighted", file: file, line: line)
        }
    }

    private func colorFromHex(_ hex: String) -> NSColor {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0
        Scanner(string: String(h.prefix(2))).scanHexInt64(&r)
        Scanner(string: String(h.dropFirst(2).prefix(2))).scanHexInt64(&g)
        Scanner(string: String(h.dropFirst(4).prefix(2))).scanHexInt64(&b)
        return NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private func colorHex(_ c: NSColor) -> String {
        guard let srgb = c.usingColorSpace(.sRGB) else { return "?" }
        let r = Int(round(srgb.redComponent * 255))
        let g = Int(round(srgb.greenComponent * 255))
        let b = Int(round(srgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    // MARK: - End-to-end: detect + highlight

    func testPython() {
        let code = "import os\n\n# comment\ndef greet(name):\n    print(f\"Hello {name}\")\n    x = 42\n    return True"
        let result = detectAndHighlight(code, expected: "python")

        assertToken("import", in: result, hasColor: Self.keyword)
        assertToken("# comment", in: result, hasColor: Self.comment)
        assertToken("def", in: result, hasColor: Self.keyword)
        assertToken("greet", in: result, hasColor: Self.function_)
        assertToken("name", in: result, hasColor: Self.params)
        assertToken("print", in: result, hasColor: Self.builtIn)
        assertToken("42", in: result, hasColor: Self.number_)
        assertToken("True", in: result, hasColor: Self.literal)
    }

    func testJavaScript() {
        let code = "// comment\nconst x = 42;\nfunction greet(name) {\n    return `Hello ${name}`;\n}\nconsole.log(greet('world'));"
        let result = detectAndHighlight(code, expected: "javascript")

        assertToken("// comment", in: result, hasColor: Self.comment)
        assertToken("const", in: result, hasColor: Self.keyword)
        assertToken("42", in: result, hasColor: Self.number_)
        assertToken("function", in: result, hasColor: Self.keyword)
        assertToken("greet", in: result, hasColor: Self.function_)
    }

    func testSwift() {
        let code = "import SwiftUI\n\n// comment\nstruct App {\n    let name = \"Itsypad\"\n    func run() {\n        guard let x = opt else { return }\n        print(x)\n    }\n}"
        let result = detectAndHighlight(code, expected: "swift")

        assertToken("// comment", in: result, hasColor: Self.comment)
        assertToken("struct", in: result, hasColor: Self.keyword)
        assertToken("let", in: result, hasColor: Self.keyword)
        assertToken("\"Itsypad\"", in: result, hasColor: Self.string_)
        assertToken("func", in: result, hasColor: Self.keyword)
        assertToken("guard", in: result, hasColor: Self.keyword)
    }

    func testPHP() {
        let code = "<?php\n$name = \"World\";\nfunction greet($who) {\n    echo \"Hello \" . $who;\n}\nforeach ($items as $item) {\n    print_r($item);\n}"
        let result = detectAndHighlight(code, expected: "php")

        assertToken("<?php", in: result, hasColor: Self.meta)
        assertToken("$name", in: result, hasColor: Self.variable)
        assertToken("function", in: result, hasColor: Self.keyword)
        assertToken("\"World\"", in: result, hasColor: Self.string_)
        assertToken("foreach", in: result, hasColor: Self.keyword)
    }

    func testGo() {
        let code = "package main\n\nimport \"fmt\"\n\nfunc main() {\n    x := 42\n    fmt.Println(\"hello\")\n}"
        let result = detectAndHighlight(code, expected: "go")

        assertToken("package", in: result, hasColor: Self.keyword)
        assertToken("import", in: result, hasColor: Self.keyword)
        assertToken("func", in: result, hasColor: Self.keyword)
        assertToken("42", in: result, hasColor: Self.number_)
        assertToken("\"fmt\"", in: result, hasColor: Self.string_)
        assertToken("\"hello\"", in: result, hasColor: Self.string_)
    }

    func testRust() {
        let code = "use std::collections::HashMap;\n\n// comment\nfn main() {\n    let mut x = 42;\n    println!(\"value: {}\", x);\n}"
        let result = detectAndHighlight(code, expected: "rust")

        assertToken("// comment", in: result, hasColor: Self.comment)
        assertToken("fn", in: result, hasColor: Self.keyword)
        assertToken("let", in: result, hasColor: Self.keyword)
        assertToken("mut", in: result, hasColor: Self.keyword)
        assertToken("42", in: result, hasColor: Self.number_)
    }

    func testC() {
        let code = "#include <stdio.h>\n\n// comment\nint main() {\n    printf(\"hello %d\", 42);\n    return 0;\n}"
        let result = detectAndHighlight(code, expected: "cpp")

        assertToken("// comment", in: result, hasColor: Self.comment)
        assertToken("\"hello %d\"", in: result, hasColor: Self.string_)
        assertToken("42", in: result, hasColor: Self.number_)
        assertToken("0", in: result, hasColor: Self.number_)
    }

    func testCPP() {
        let code = "#include <iostream>\n\n// comment\nclass Greeter {\npublic:\n    auto greet() {\n        std::cout << \"hello\" << 42;\n    }\n};"
        let result = detectAndHighlight(code, expected: "cpp")

        assertToken("// comment", in: result, hasColor: Self.comment)
        assertToken("class", in: result, hasColor: Self.keyword)
        assertToken("Greeter", in: result, hasColor: Self.class_)
        assertToken("auto", in: result, hasColor: Self.keyword)
        assertToken("\"hello\"", in: result, hasColor: Self.string_)
        assertToken("42", in: result, hasColor: Self.number_)
    }

    func testBash() {
        let code = "#!/bin/bash\n# comment\nNAME=\"World\"\necho \"Hello $NAME\"\nx=42"
        let result = detectAndHighlight(code, expected: "bash")

        assertToken("# comment", in: result, hasColor: Self.comment)
        assertToken("echo", in: result, hasColor: Self.builtIn)
        assertToken("\"Hello ", in: result, hasColor: Self.string_)
    }

    func testJSON() {
        let code = "{\n    \"name\": \"Itsypad\",\n    \"version\": 1,\n    \"enabled\": true,\n    \"data\": null\n}"
        let result = detectAndHighlight(code, expected: "json")

        assertToken("\"name\"", in: result, hasColor: Self.attr)
        assertToken("\"Itsypad\"", in: result, hasColor: Self.string_)
        assertToken("1", in: result, hasColor: Self.number_)
        assertToken("true", in: result, hasColor: Self.keyword)
        assertToken("null", in: result, hasColor: Self.keyword)
    }

    func testHTML() {
        let code = "<!DOCTYPE html>\n<html>\n<body>\n    <div class=\"main\">\n        <a href=\"https://example.com\">Link</a>\n    </div>\n</body>\n</html>"
        let result = detectAndHighlight(code, expected: "html")

        assertToken("div", in: result, hasColor: Self.name_)
        assertToken("class", in: result, hasColor: Self.attr)
        assertToken("\"main\"", in: result, hasColor: Self.string_)
        assertToken("href", in: result, hasColor: Self.attr)
    }

    // MARK: - Explicit language (no content-based detection heuristic)

    func testTypeScript() {
        let code = "interface User {\n    name: string;\n    age: number;\n}\nfunction greet<T>(item: T): string {\n    return \"hello\";\n}"
        let result = highlight(code, as: "typescript")

        assertToken("interface", in: result, hasColor: Self.keyword)
        assertToken("User", in: result, hasColor: Self.class_)
        assertToken("string", in: result, hasColor: Self.builtIn)
        assertToken("function", in: result, hasColor: Self.keyword)
        assertToken("\"hello\"", in: result, hasColor: Self.string_)
    }

    func testJava() {
        let code = "// comment\npublic class Main {\n    @Override\n    public void run() {\n        System.out.println(\"hello\");\n        int x = 42;\n    }\n}"
        let result = highlight(code, as: "java")

        assertToken("// comment", in: result, hasColor: Self.comment)
        assertToken("public", in: result, hasColor: Self.keyword)
        assertToken("class", in: result, hasColor: Self.keyword)
        assertToken("Main", in: result, hasColor: Self.class_)
        assertToken("\"hello\"", in: result, hasColor: Self.string_)
        assertToken("42", in: result, hasColor: Self.number_)
    }

    func testRuby() {
        let code = "# comment\ndef greet(name)\n    puts \"Hello #{name}\"\n    x = 42\nend"
        let result = highlight(code, as: "ruby")

        assertToken("# comment", in: result, hasColor: Self.comment)
        assertToken("def", in: result, hasColor: Self.keyword)
        assertToken("greet", in: result, hasColor: Self.function_)
        assertToken("42", in: result, hasColor: Self.number_)
        assertToken("end", in: result, hasColor: Self.keyword)
    }

    func testCSS() {
        let code = ".main {\n    color: #ff0000;\n    font-size: 14px;\n}"
        let result = highlight(code, as: "css")

        assertToken(".main", in: result, hasColor: Self.selClass)
        assertToken("color", in: result, hasColor: Self.attr)
        assertToken("14px", in: result, hasColor: Self.number_)
    }

    func testSQL() {
        let code = "SELECT name, age\nFROM users\nWHERE age > 21\nAND name = 'Alice';"
        let result = highlight(code, as: "sql")

        assertToken("SELECT", in: result, hasColor: Self.keyword)
        assertToken("FROM", in: result, hasColor: Self.keyword)
        assertToken("WHERE", in: result, hasColor: Self.keyword)
        assertToken("'Alice'", in: result, hasColor: Self.string_)
        assertToken("21", in: result, hasColor: Self.number_)
    }

    func testYAML() {
        let code = "# comment\nname: Itsypad\nversion: 1.0\nenabled: true"
        let result = highlight(code, as: "yaml")

        assertToken("# comment", in: result, hasColor: Self.comment)
        assertToken("name", in: result, hasColor: Self.attr)
        assertToken("true", in: result, hasColor: Self.literal)
    }

    func testKotlin() {
        let code = "// comment\nfun greet(name: String): String {\n    val x = 42\n    return \"Hello $name\"\n}\nclass App"
        let result = highlight(code, as: "kotlin")

        assertToken("// comment", in: result, hasColor: Self.comment)
        assertToken("fun", in: result, hasColor: Self.keyword)
        assertToken("greet", in: result, hasColor: Self.function_)
        assertToken("val", in: result, hasColor: Self.keyword)
        assertToken("42", in: result, hasColor: Self.number_)
        assertToken("class", in: result, hasColor: Self.keyword)
    }

    func testMarkdown() {
        let code = "# Heading\n**bold text**\n[link](https://example.com)\n`code span`"
        let result = highlight(code, as: "markdown")

        assertToken("# Heading", in: result, hasColor: Self.keyword)
        assertToken("bold text", in: result, hasColor: Self.strong)
    }

    // MARK: - Plain text stays plain

    func testPlainTextNotHighlighted() {
        let text = "Good ones to test beyond those:\n\n    1. Python — decorators\n    2. Go — goroutines, :=\n    3. Rust — lifetimes 'a\n    4. C/C++ — preprocessor #include"
        let detected = detector.detect(text: text, name: nil, fileURL: nil)
        XCTAssertEqual(detected.lang, "plain", "Plain text was misdetected as \(detected.lang)")
    }
}
