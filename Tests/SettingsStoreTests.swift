import XCTest
@testable import ItsypadCore

final class SettingsStoreTests: XCTestCase {
    private var store: SettingsStore!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.nickustinov.itsypad.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Default values

    func testDefaultShortcut() {
        XCTAssertEqual(store.shortcut, "⌥⌥⌥ L")
    }

    func testDefaultEditorFontName() {
        XCTAssertEqual(store.editorFontName, "System Mono")
    }

    func testDefaultEditorFontSize() {
        XCTAssertEqual(store.editorFontSize, 14)
    }

    func testDefaultAppearanceOverride() {
        XCTAssertEqual(store.appearanceOverride, "system")
    }

    func testDefaultShowInDock() {
        XCTAssertTrue(store.showInDock)
    }

    func testDefaultShowLineNumbers() {
        XCTAssertTrue(store.showLineNumbers)
    }

    func testDefaultHighlightCurrentLine() {
        XCTAssertFalse(store.highlightCurrentLine)
    }

    func testDefaultIndentUsingSpaces() {
        XCTAssertTrue(store.indentUsingSpaces)
    }

    func testDefaultTabWidth() {
        XCTAssertEqual(store.tabWidth, 4)
    }

    func testDefaultWordWrap() {
        XCTAssertTrue(store.wordWrap)
    }

    func testDefaultShortcutKeys() {
        XCTAssertNotNil(store.shortcutKeys)
        XCTAssertEqual(store.shortcutKeys?.isTripleTap, true)
        XCTAssertEqual(store.shortcutKeys?.tapModifier, "left-option")
    }

    func testDefaultClipboardShortcut() {
        XCTAssertEqual(store.clipboardShortcut, "")
    }

    func testDefaultClipboardShortcutKeys() {
        XCTAssertNil(store.clipboardShortcutKeys)
    }

    func testDefaultClickableLinks() {
        XCTAssertTrue(store.clickableLinks)
    }

    func testDefaultLineSpacing() {
        XCTAssertEqual(store.lineSpacing, 1.0)
    }

    func testDefaultLetterSpacing() {
        XCTAssertEqual(store.letterSpacing, 0.0)
    }

    func testDefaultIcloudSync() {
        XCTAssertTrue(store.icloudSync)
    }

    func testDefaultClipboardViewMode() {
        XCTAssertEqual(store.clipboardViewMode, "grid")
    }

    func testDefaultClipboardPreviewLines() {
        XCTAssertEqual(store.clipboardPreviewLines, 5)
    }

    func testDefaultClipboardFontSize() {
        XCTAssertEqual(store.clipboardFontSize, 11)
    }

    func testDefaultClipboardAutoDelete() {
        XCTAssertEqual(store.clipboardAutoDelete, "never")
    }

    // MARK: - Setting persistence

    func testShortcutPersistsToDefaults() {
        store.shortcut = "⌘K"
        XCTAssertEqual(defaults.string(forKey: "shortcut"), "⌘K")
    }

    func testEditorFontNamePersistsToDefaults() {
        store.editorFontName = "Menlo"
        XCTAssertEqual(defaults.string(forKey: "editorFontName"), "Menlo")
    }

    func testEditorFontSizePersistsToDefaults() {
        store.editorFontSize = 16
        XCTAssertEqual(defaults.double(forKey: "editorFontSize"), 16)
    }

    func testIcloudSyncPersistsToDefaults() {
        store.setICloudSync(true)
        XCTAssertTrue(defaults.bool(forKey: "icloudSync"))
    }

    func testClipboardViewModePersistsToDefaults() {
        store.clipboardViewMode = "panels"
        XCTAssertEqual(defaults.string(forKey: "clipboardViewMode"), "panels")
    }

    func testClipboardPreviewLinesPersistsToDefaults() {
        store.clipboardPreviewLines = 10
        XCTAssertEqual(defaults.integer(forKey: "clipboardPreviewLines"), 10)
    }

    func testClipboardFontSizePersistsToDefaults() {
        store.clipboardFontSize = 14
        XCTAssertEqual(defaults.double(forKey: "clipboardFontSize"), 14)
    }

    func testClipboardAutoDeletePersistsToDefaults() {
        store.clipboardAutoDelete = "7d"
        XCTAssertEqual(defaults.string(forKey: "clipboardAutoDelete"), "7d")
    }

    func testClickableLinksPersistsToDefaults() {
        store.clickableLinks = false
        XCTAssertFalse(defaults.bool(forKey: "clickableLinks"))
    }

    func testLineSpacingPersistsToDefaults() {
        store.lineSpacing = 1.5
        XCTAssertEqual(defaults.double(forKey: "lineSpacing"), 1.5)
    }

    func testLetterSpacingPersistsToDefaults() {
        store.letterSpacing = 2.0
        XCTAssertEqual(defaults.double(forKey: "letterSpacing"), 2.0)
    }

    // MARK: - editorFont computed property

    func testEditorFontSystemMono() {
        store.editorFontSize = 14
        let font = store.editorFont
        XCTAssertTrue(font.isFixedPitch)
        XCTAssertEqual(font.pointSize, 14)
    }

    func testEditorFontFallback() {
        store.editorFontName = "NonexistentFont12345"
        let font = store.editorFont
        XCTAssertTrue(font.isFixedPitch, "Should fall back to monospaced system font")
    }

    // MARK: - Load from pre-populated defaults

    func testLoadFromPrePopulatedDefaults() {
        let preSuiteName = "com.nickustinov.itsypad.test.\(UUID().uuidString)"
        let preDefaults = UserDefaults(suiteName: preSuiteName)!
        preDefaults.set("Menlo", forKey: "editorFontName")
        preDefaults.set(18.0, forKey: "editorFontSize")
        preDefaults.set("dark", forKey: "appearanceOverride")
        preDefaults.set(false, forKey: "showLineNumbers")
        preDefaults.set(2, forKey: "tabWidth")
        preDefaults.set(false, forKey: "wordWrap")
        preDefaults.set(false, forKey: "clickableLinks")
        preDefaults.set(1.4, forKey: "lineSpacing")
        preDefaults.set(1.5, forKey: "letterSpacing")
        preDefaults.set("panels", forKey: "clipboardViewMode")
        preDefaults.set(12, forKey: "clipboardPreviewLines")
        preDefaults.set(16.0, forKey: "clipboardFontSize")
        preDefaults.set("14d", forKey: "clipboardAutoDelete")

        let preStore = SettingsStore(defaults: preDefaults)
        XCTAssertEqual(preStore.editorFontName, "Menlo")
        XCTAssertEqual(preStore.editorFontSize, 18)
        XCTAssertEqual(preStore.appearanceOverride, "dark")
        XCTAssertFalse(preStore.showLineNumbers)
        XCTAssertEqual(preStore.tabWidth, 2)
        XCTAssertFalse(preStore.wordWrap)
        XCTAssertFalse(preStore.clickableLinks)
        XCTAssertEqual(preStore.lineSpacing, 1.4)
        XCTAssertEqual(preStore.letterSpacing, 1.5)
        XCTAssertEqual(preStore.clipboardViewMode, "panels")
        XCTAssertEqual(preStore.clipboardPreviewLines, 12)
        XCTAssertEqual(preStore.clipboardFontSize, 16)
        XCTAssertEqual(preStore.clipboardAutoDelete, "14d")

        preDefaults.removePersistentDomain(forName: preSuiteName)
    }
}
