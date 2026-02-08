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

    func testDefaultIcloudSync() {
        XCTAssertFalse(store.icloudSync)
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
        store.icloudSync = true
        XCTAssertTrue(defaults.bool(forKey: "icloudSync"))
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

        let preStore = SettingsStore(defaults: preDefaults)
        XCTAssertEqual(preStore.editorFontName, "Menlo")
        XCTAssertEqual(preStore.editorFontSize, 18)
        XCTAssertEqual(preStore.appearanceOverride, "dark")
        XCTAssertFalse(preStore.showLineNumbers)
        XCTAssertEqual(preStore.tabWidth, 2)
        XCTAssertFalse(preStore.wordWrap)

        preDefaults.removePersistentDomain(forName: preSuiteName)
    }
}
