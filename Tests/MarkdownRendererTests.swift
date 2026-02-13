import XCTest
@testable import ItsypadCore

final class MarkdownRendererTests: XCTestCase {
    private static let renderer = MarkdownRenderer()
    private let theme = EditorTheme.dark

    // MARK: - Basic markdown

    func testRenderHeading() {
        let html = Self.renderer.render(markdown: "# Hello", theme: theme)
        XCTAssertTrue(html.contains("<h1>Hello</h1>"), "Expected <h1> tag in output")
    }

    func testRenderParagraph() {
        let html = Self.renderer.render(markdown: "Some text here.", theme: theme)
        XCTAssertTrue(html.contains("<p>Some text here.</p>"), "Expected <p> tag in output")
    }

    func testRenderBold() {
        let html = Self.renderer.render(markdown: "**bold**", theme: theme)
        XCTAssertTrue(html.contains("<strong>bold</strong>"), "Expected <strong> tag in output")
    }

    func testRenderItalic() {
        let html = Self.renderer.render(markdown: "*italic*", theme: theme)
        XCTAssertTrue(html.contains("<em>italic</em>"), "Expected <em> tag in output")
    }

    // MARK: - Code blocks

    func testRenderFencedCodeBlock() {
        let markdown = """
        ```swift
        let x = 42
        ```
        """
        let html = Self.renderer.render(markdown: markdown, theme: theme)
        XCTAssertTrue(html.contains("hljs"), "Expected hljs class in code block output")
        XCTAssertTrue(html.contains("let"), "Expected code content in output")
    }

    func testRenderInlineCode() {
        let html = Self.renderer.render(markdown: "Use `print()` here", theme: theme)
        XCTAssertTrue(html.contains("<code>print()</code>"), "Expected <code> tag for inline code")
    }

    // MARK: - Links

    func testRenderLinks() {
        let html = Self.renderer.render(markdown: "[Example](https://example.com)", theme: theme)
        XCTAssertTrue(html.contains("<a"), "Expected <a> tag in output")
        XCTAssertTrue(html.contains("https://example.com"), "Expected URL in output")
        XCTAssertTrue(html.contains("Example"), "Expected link text in output")
    }

    // MARK: - Empty content

    func testRenderEmptyString() {
        let html = Self.renderer.render(markdown: "", theme: theme)
        XCTAssertTrue(html.contains("<!DOCTYPE html>"), "Expected valid HTML wrapper")
        XCTAssertTrue(html.contains("<body>"), "Expected body tag")
    }

    // MARK: - HTML structure

    func testRenderIncludesThemeColors() {
        let html = Self.renderer.render(markdown: "test", theme: theme)
        // Dark theme background is #25252c
        XCTAssertTrue(html.contains("#25252c"), "Expected dark theme background color")
    }

    func testRenderIncludesSyntaxCSS() {
        let html = Self.renderer.render(markdown: "```swift\nlet x = 1\n```", theme: theme)
        XCTAssertTrue(html.contains(".hljs"), "Expected syntax highlight CSS in output")
    }

    // MARK: - Lists

    func testRenderUnorderedList() {
        let markdown = "- Item one\n- Item two\n- Item three"
        let html = Self.renderer.render(markdown: markdown, theme: theme)
        XCTAssertTrue(html.contains("<ul>"), "Expected <ul> tag")
        XCTAssertTrue(html.contains("<li>"), "Expected <li> tags")
    }

    func testRenderOrderedList() {
        let markdown = "1. First\n2. Second\n3. Third"
        let html = Self.renderer.render(markdown: markdown, theme: theme)
        XCTAssertTrue(html.contains("<ol>"), "Expected <ol> tag")
    }

    // MARK: - Other elements

    func testRenderBlockquote() {
        let html = Self.renderer.render(markdown: "> A quote", theme: theme)
        XCTAssertTrue(html.contains("<blockquote>"), "Expected <blockquote> tag")
    }

    func testRenderHorizontalRule() {
        let html = Self.renderer.render(markdown: "---", theme: theme)
        XCTAssertTrue(html.contains("<hr"), "Expected <hr> tag")
    }

    // MARK: - Frontmatter stripping

    func testStripFrontmatter() {
        let result = Self.renderer.stripFrontmatter("---\ntitle: Test\n---\n# Hello")
        XCTAssertEqual(result, "# Hello")
    }

    func testStripFrontmatterPreservesContent() {
        let result = Self.renderer.stripFrontmatter("# No frontmatter here")
        XCTAssertEqual(result, "# No frontmatter here")
    }

    func testStripFrontmatterMultipleFields() {
        let markdown = "---\ntitle: Test\ndate: 2026-01-01\ntags: [swift]\n---\nContent"
        let result = Self.renderer.stripFrontmatter(markdown)
        XCTAssertEqual(result, "Content")
    }

    func testStripFrontmatterOnlyFrontmatter() {
        let result = Self.renderer.stripFrontmatter("---\ntitle: Test\n---")
        XCTAssertEqual(result, "")
    }

    func testStripFrontmatterNotAtStart() {
        let markdown = "Some text\n---\ntitle: Test\n---\n"
        let result = Self.renderer.stripFrontmatter(markdown)
        XCTAssertEqual(result, markdown, "Should not strip frontmatter that doesn't start at beginning")
    }

    func testRenderFrontmatterDocument() {
        let markdown = "---\ntitle: My Post\ndate: 2026-01-01\n---\n# Hello world"
        let html = Self.renderer.render(markdown: markdown, theme: theme)
        XCTAssertTrue(html.contains("<h1>Hello world</h1>"), "Expected content after frontmatter")
        XCTAssertFalse(html.contains("title: My Post"), "Frontmatter should be stripped from output")
    }
}
