import XCTest
@testable import ItsypadCore

final class TabStoreTests: XCTestCase {
    private var store: TabStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        store = TabStore(sessionURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        store = nil
        super.tearDown()
    }

    // MARK: - Init

    func testInitStartsWithOneUntitledTab() {
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs.first?.name, "Untitled")
        XCTAssertNotNil(store.selectedTabID)
    }

    // MARK: - addNewTab

    func testAddNewTab() {
        let initialCount = store.tabs.count
        store.addNewTab()
        XCTAssertEqual(store.tabs.count, initialCount + 1)
        XCTAssertEqual(store.selectedTabID, store.tabs.last?.id)
    }

    func testAddNewTabSelectsIt() {
        store.addNewTab()
        let newTab = store.tabs.last!
        XCTAssertEqual(store.selectedTabID, newTab.id)
    }

    // MARK: - closeTab

    func testCloseTabRemovesIt() {
        store.addNewTab()
        let tabToClose = store.tabs.first!
        store.closeTab(id: tabToClose.id)
        XCTAssertFalse(store.tabs.contains(where: { $0.id == tabToClose.id }))
    }

    func testCloseLastTabCreatesNew() {
        let onlyTab = store.tabs.first!
        store.closeTab(id: onlyTab.id)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertNotEqual(store.tabs.first?.id, onlyTab.id)
    }

    func testCloseSelectedTabSelectsNeighbor() {
        store.addNewTab()
        store.addNewTab()
        let middleTab = store.tabs[1]
        store.selectedTabID = middleTab.id
        store.closeTab(id: middleTab.id)
        XCTAssertNotNil(store.selectedTabID)
        XCTAssertNotEqual(store.selectedTabID, middleTab.id)
    }

    func testCloseNonSelectedTabKeepsSelection() {
        store.addNewTab()
        let firstTab = store.tabs[0]
        let secondTab = store.tabs[1]
        store.selectedTabID = secondTab.id
        store.closeTab(id: firstTab.id)
        XCTAssertEqual(store.selectedTabID, secondTab.id)
    }

    // MARK: - updateContent

    func testUpdateContentAutoNames() {
        let tabID = store.tabs.first!.id
        store.updateContent(id: tabID, content: "hello world")
        XCTAssertEqual(store.tabs.first?.name, "hello world")
    }

    func testUpdateContentTruncatesLongName() {
        let tabID = store.tabs.first!.id
        let longLine = String(repeating: "a", count: 50)
        store.updateContent(id: tabID, content: longLine)
        XCTAssertEqual(store.tabs.first?.name.count, 30)
    }

    func testUpdateContentSetsDirty() {
        let tabID = store.tabs.first!.id
        store.updateContent(id: tabID, content: "changed")
        XCTAssertTrue(store.tabs.first!.isDirty)
    }

    func testUpdateContentEmptyLineUsesUntitled() {
        let tabID = store.tabs.first!.id
        store.updateContent(id: tabID, content: "   \nsomething")
        XCTAssertEqual(store.tabs.first?.name, "Untitled")
    }

    func testUpdateContentWithLockedLanguageDoesNotChangeLanguage() {
        let tabID = store.tabs.first!.id
        store.updateLanguage(id: tabID, language: "python")
        XCTAssertTrue(store.tabs.first!.languageLocked)
        store.updateContent(id: tabID, content: "import SwiftUI\nstruct Foo: View {}")
        XCTAssertEqual(store.tabs.first?.language, "python")
    }

    func testUpdateContentWithFileURLDoesNotAutoName() {
        let tabID = store.tabs.first!.id
        store.tabs[0].fileURL = URL(fileURLWithPath: "/tmp/test.swift")
        store.tabs[0].name = "test.swift"
        store.updateContent(id: tabID, content: "new content")
        XCTAssertEqual(store.tabs.first?.name, "test.swift")
    }

    func testUpdateContentSameContentNoOp() {
        let tabID = store.tabs.first!.id
        store.updateContent(id: tabID, content: "hello")
        store.tabs[0].isDirty = false
        store.updateContent(id: tabID, content: "hello")
        XCTAssertFalse(store.tabs.first!.isDirty)
    }

    // MARK: - updateLanguage

    func testUpdateLanguageLocksLanguage() {
        let tabID = store.tabs.first!.id
        store.updateLanguage(id: tabID, language: "rust")
        XCTAssertEqual(store.tabs.first?.language, "rust")
        XCTAssertTrue(store.tabs.first!.languageLocked)
    }

    // MARK: - moveTab

    func testMoveTabForward() {
        store.addNewTab()
        store.addNewTab()
        let first = store.tabs[0]
        store.moveTab(from: 0, to: 2)
        XCTAssertEqual(store.tabs[1].id, first.id)
    }

    func testMoveTabBackward() {
        store.addNewTab()
        store.addNewTab()
        let last = store.tabs[2]
        store.moveTab(from: 2, to: 0)
        XCTAssertEqual(store.tabs[0].id, last.id)
    }

    func testMoveTabSameIndexNoOp() {
        store.addNewTab()
        let tabs = store.tabs
        store.moveTab(from: 0, to: 0)
        XCTAssertEqual(store.tabs.map(\.id), tabs.map(\.id))
    }

    func testMoveTabOutOfBoundsNoOp() {
        let tabs = store.tabs
        store.moveTab(from: 5, to: 0)
        XCTAssertEqual(store.tabs.map(\.id), tabs.map(\.id))
    }

    // MARK: - Session persistence

    func testSessionPersistenceRoundtrip() {
        let tabID = store.tabs.first!.id
        store.updateContent(id: tabID, content: "persisted content")
        store.saveSession()

        let restored = TabStore(sessionURL: tempURL)
        XCTAssertEqual(restored.tabs.first?.content, "persisted content")
        XCTAssertEqual(restored.selectedTabID, tabID)
    }

    // MARK: - TabData Codable

    func testTabDataCodableRoundtrip() throws {
        let tab = TabData(
            name: "Test",
            content: "hello",
            language: "swift",
            fileURL: URL(fileURLWithPath: "/tmp/test.swift"),
            languageLocked: true,
            isDirty: true,
            cursorPosition: 42
        )
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(TabData.self, from: data)
        XCTAssertEqual(tab, decoded)
    }

    func testTabDataDefaultValues() {
        let tab = TabData()
        XCTAssertEqual(tab.name, "Untitled")
        XCTAssertEqual(tab.content, "")
        XCTAssertEqual(tab.language, "plain")
        XCTAssertNil(tab.fileURL)
        XCTAssertFalse(tab.languageLocked)
        XCTAssertFalse(tab.isDirty)
        XCTAssertEqual(tab.cursorPosition, 0)
    }

    // MARK: - reloadFromDisk

    func testReloadFromDiskUpdatesContent() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let tabID = store.tabs.first!.id
        store.tabs[0].fileURL = fileURL
        store.tabs[0].content = "original"
        store.tabs[0].isDirty = true

        try "updated from disk".write(to: fileURL, atomically: true, encoding: .utf8)
        let result = store.reloadFromDisk(id: tabID)

        XCTAssertTrue(result)
        XCTAssertEqual(store.tabs.first?.content, "updated from disk")
        XCTAssertFalse(store.tabs.first!.isDirty)
    }

    func testReloadFromDiskReturnsFalseWithoutFileURL() {
        let tabID = store.tabs.first!.id
        XCTAssertNil(store.tabs.first?.fileURL)
        let result = store.reloadFromDisk(id: tabID)
        XCTAssertFalse(result)
    }

    func testReloadFromDiskReturnsFalseForMissingFile() {
        let tabID = store.tabs.first!.id
        store.tabs[0].fileURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-nonexistent.txt")
        let result = store.reloadFromDisk(id: tabID)
        XCTAssertFalse(result)
    }

    func testReloadFromDiskReturnsFalseForInvalidID() {
        let result = store.reloadFromDisk(id: UUID())
        XCTAssertFalse(result)
    }

    // MARK: - Cloud sync (applyCloudTab / removeCloudTab)

    func testApplyCloudTabInsertsNewTab() {
        let initialCount = store.tabs.count
        let record = CloudTabRecord(
            id: UUID(),
            name: "Cloud note",
            content: "from cloud",
            language: "plain",
            languageLocked: false,
            lastModified: Date()
        )
        store.applyCloudTab(record)

        XCTAssertEqual(store.tabs.count, initialCount + 1)
        XCTAssertTrue(store.tabs.contains(where: { $0.id == record.id }))
        XCTAssertEqual(store.tabs.last?.content, "from cloud")
    }

    func testApplyCloudTabUpdatesExistingTab() {
        let existingID = store.tabs.first!.id
        let record = CloudTabRecord(
            id: existingID,
            name: "Updated",
            content: "updated content",
            language: "swift",
            languageLocked: true,
            lastModified: Date()
        )
        store.applyCloudTab(record)

        XCTAssertEqual(store.tabs.first?.content, "updated content")
        XCTAssertEqual(store.tabs.first?.name, "Updated")
        XCTAssertEqual(store.tabs.first?.language, "swift")
        XCTAssertTrue(store.tabs.first!.languageLocked)
    }

    func testApplyCloudTabSkipsOlderVersion() {
        let existingID = store.tabs.first!.id
        store.updateContent(id: existingID, content: "local content")

        let record = CloudTabRecord(
            id: existingID,
            name: "Old cloud",
            content: "old content",
            language: "plain",
            languageLocked: false,
            lastModified: Date.distantPast
        )
        store.applyCloudTab(record)

        XCTAssertEqual(store.tabs.first?.content, "local content")
    }

    func testRemoveCloudTabRemovesTab() {
        store.addNewTab()
        let tabToRemove = store.tabs.first!.id
        store.removeCloudTab(id: tabToRemove)
        XCTAssertFalse(store.tabs.contains(where: { $0.id == tabToRemove }))
    }

    func testRemoveCloudTabEnsuresAtLeastOneTab() {
        let onlyTab = store.tabs.first!.id
        store.removeCloudTab(id: onlyTab)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertNotEqual(store.tabs.first?.id, onlyTab)
    }

    func testRemoveCloudTabIgnoresUnknownID() {
        let initialCount = store.tabs.count
        store.removeCloudTab(id: UUID())
        XCTAssertEqual(store.tabs.count, initialCount)
    }

    // MARK: - LayoutNode Codable

    func testLayoutNodePaneCodableRoundtrip() throws {
        let node = LayoutNode.pane(PaneNodeData(
            tabIDs: [UUID(), UUID()],
            selectedTabID: UUID()
        ))
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(LayoutNode.self, from: data)
        XCTAssertEqual(node, decoded)
    }

    func testLayoutNodeSplitCodableRoundtrip() throws {
        let node = LayoutNode.split(SplitNodeData(
            orientation: "horizontal",
            dividerPosition: 0.4,
            first: .pane(PaneNodeData(tabIDs: [UUID()], selectedTabID: nil)),
            second: .pane(PaneNodeData(tabIDs: [UUID()], selectedTabID: nil))
        ))
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(LayoutNode.self, from: data)
        XCTAssertEqual(node, decoded)
    }

    func testLayoutNodeNestedSplitCodableRoundtrip() throws {
        let inner = LayoutNode.split(SplitNodeData(
            orientation: "vertical",
            dividerPosition: 0.3,
            first: .pane(PaneNodeData(tabIDs: [UUID()], selectedTabID: nil)),
            second: .pane(PaneNodeData(tabIDs: [UUID()], selectedTabID: nil))
        ))
        let node = LayoutNode.split(SplitNodeData(
            orientation: "horizontal",
            dividerPosition: 0.5,
            first: inner,
            second: .pane(PaneNodeData(tabIDs: [UUID(), UUID()], selectedTabID: UUID()))
        ))
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(LayoutNode.self, from: data)
        XCTAssertEqual(node, decoded)
    }

    // MARK: - Session persistence with layout

    func testSessionPersistenceWithLayout() {
        let tabID = store.tabs.first!.id
        store.currentLayout = .pane(PaneNodeData(tabIDs: [tabID], selectedTabID: tabID))
        store.saveSession()

        let restored = TabStore(sessionURL: tempURL)
        XCTAssertNotNil(restored.savedLayout)
        if case .pane(let data) = restored.savedLayout {
            XCTAssertEqual(data.tabIDs, [tabID])
            XCTAssertEqual(data.selectedTabID, tabID)
        } else {
            XCTFail("Expected pane layout")
        }
    }

    func testSessionPersistenceWithSplitLayout() {
        let tabID = store.tabs.first!.id
        store.addNewTab()
        let secondTabID = store.tabs.last!.id

        store.currentLayout = .split(SplitNodeData(
            orientation: "horizontal",
            dividerPosition: 0.5,
            first: .pane(PaneNodeData(tabIDs: [tabID], selectedTabID: tabID)),
            second: .pane(PaneNodeData(tabIDs: [secondTabID], selectedTabID: secondTabID))
        ))
        store.saveSession()

        let restored = TabStore(sessionURL: tempURL)
        XCTAssertNotNil(restored.savedLayout)
        if case .split(let data) = restored.savedLayout {
            XCTAssertEqual(data.orientation, "horizontal")
            XCTAssertEqual(data.dividerPosition, 0.5)
        } else {
            XCTFail("Expected split layout")
        }
    }

    func testSessionPersistenceWithoutLayoutBackwardCompatible() {
        store.saveSession()

        let restored = TabStore(sessionURL: tempURL)
        XCTAssertNil(restored.savedLayout)
    }

    func testSessionPersistenceLayoutNilByDefault() {
        XCTAssertNil(store.currentLayout)
    }
}
