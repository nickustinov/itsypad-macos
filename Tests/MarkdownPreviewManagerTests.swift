import XCTest
import Bonsplit
@testable import ItsypadCore

final class MarkdownPreviewManagerTests: XCTestCase {
    private var manager: MarkdownPreviewManager!
    private var theme: EditorTheme!

    override func setUp() {
        super.setUp()
        manager = MarkdownPreviewManager()
        theme = EditorTheme.current(for: "system")
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testInitiallyNoPreviewsActive() {
        let tabID = TabID()
        XCTAssertFalse(manager.isActive(for: tabID))
        XCTAssertNil(manager.html(for: tabID))
        XCTAssertNil(manager.baseURL(for: tabID))
    }

    // MARK: - toggle

    func testToggleOnForMarkdownActivatesPreview() {
        let tabID = TabID()
        let result = manager.toggle(
            for: tabID,
            language: "markdown",
            content: "# Hello",
            fileURL: nil,
            theme: theme
        )
        XCTAssertTrue(result)
        XCTAssertTrue(manager.isActive(for: tabID))
        XCTAssertNotNil(manager.html(for: tabID))
    }

    func testToggleOffDeactivatesPreview() {
        let tabID = TabID()
        manager.toggle(for: tabID, language: "markdown", content: "# Hello", fileURL: nil, theme: theme)
        let result = manager.toggle(for: tabID, language: "markdown", content: "# Hello", fileURL: nil, theme: theme)
        XCTAssertFalse(result)
        XCTAssertFalse(manager.isActive(for: tabID))
        XCTAssertNil(manager.html(for: tabID))
        XCTAssertNil(manager.baseURL(for: tabID))
    }

    func testToggleOnForNonMarkdownDoesNotActivate() {
        let tabID = TabID()
        let result = manager.toggle(
            for: tabID,
            language: "swift",
            content: "let x = 1",
            fileURL: nil,
            theme: theme
        )
        XCTAssertFalse(result)
        XCTAssertFalse(manager.isActive(for: tabID))
    }

    func testToggleOnSetsBaseURLFromFileURL() {
        let tabID = TabID()
        let fileURL = URL(fileURLWithPath: "/tmp/docs/readme.md")
        manager.toggle(for: tabID, language: "markdown", content: "# Test", fileURL: fileURL, theme: theme)
        XCTAssertEqual(manager.baseURL(for: tabID), URL(fileURLWithPath: "/tmp/docs/readme.md").deletingLastPathComponent())
    }

    func testToggleOnWithNilFileURLSetsNilBaseURL() {
        let tabID = TabID()
        manager.toggle(for: tabID, language: "markdown", content: "# Test", fileURL: nil, theme: theme)
        XCTAssertNil(manager.baseURL(for: tabID))
    }

    // MARK: - removeTab

    func testRemoveTabCleansUpPreviewState() {
        let tabID = TabID()
        manager.toggle(for: tabID, language: "markdown", content: "# Hello", fileURL: nil, theme: theme)
        XCTAssertTrue(manager.isActive(for: tabID))

        manager.removeTab(tabID)
        XCTAssertFalse(manager.isActive(for: tabID))
        XCTAssertNil(manager.html(for: tabID))
        XCTAssertNil(manager.baseURL(for: tabID))
    }

    func testRemoveTabForNonPreviewingTabIsNoOp() {
        let tabID = TabID()
        manager.removeTab(tabID)
        XCTAssertFalse(manager.isActive(for: tabID))
    }

    // MARK: - exitIfNotMarkdown

    func testExitIfNotMarkdownRemovesPreview() {
        let tabID = TabID()
        manager.toggle(for: tabID, language: "markdown", content: "# Hello", fileURL: nil, theme: theme)
        let removed = manager.exitIfNotMarkdown(for: tabID, language: "swift")
        XCTAssertTrue(removed)
        XCTAssertFalse(manager.isActive(for: tabID))
        XCTAssertNil(manager.html(for: tabID))
    }

    func testExitIfNotMarkdownKeepsMarkdownPreview() {
        let tabID = TabID()
        manager.toggle(for: tabID, language: "markdown", content: "# Hello", fileURL: nil, theme: theme)
        let removed = manager.exitIfNotMarkdown(for: tabID, language: "markdown")
        XCTAssertFalse(removed)
        XCTAssertTrue(manager.isActive(for: tabID))
    }

    func testExitIfNotMarkdownNoOpForNonPreviewingTab() {
        let tabID = TabID()
        let removed = manager.exitIfNotMarkdown(for: tabID, language: "swift")
        XCTAssertFalse(removed)
    }

    // MARK: - renderAll

    func testRenderAllUpdatesOnlyActivePreviews() {
        let tab1 = TabID()
        let tab2 = TabID()
        manager.toggle(for: tab1, language: "markdown", content: "# Original", fileURL: nil, theme: theme)
        // tab2 is not previewing

        let oldHTML = manager.html(for: tab1)
        manager.renderAll(tabs: [
            (id: tab1, content: "# Updated", fileURL: nil),
            (id: tab2, content: "# Also updated", fileURL: nil),
        ], theme: theme)

        XCTAssertNotEqual(manager.html(for: tab1), oldHTML)
        XCTAssertNil(manager.html(for: tab2))
    }
}
