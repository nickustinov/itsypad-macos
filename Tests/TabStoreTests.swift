import XCTest
@testable import ItsypadCore

class MockKeyValueStore: KeyValueStoreProtocol {
    var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        storage[key]
    }

    func setData(_ data: Data?, forKey key: String) {
        storage[key] = data
    }

    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }

    @discardableResult func synchronize() -> Bool {
        true
    }
}

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

    // MARK: - iCloud sync

    func testSaveSessionWritesScratchTabsToCloudStore() {
        let cloud = MockKeyValueStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        SettingsStore.shared.icloudSync = true
        let tabStore = TabStore(sessionURL: url, cloudStore: cloud)
        tabStore.updateContent(id: tabStore.tabs.first!.id, content: "scratch note")
        tabStore.saveSession()

        XCTAssertNotNil(cloud.storage["tabs"])
        let decoded = try! JSONDecoder().decode([TabData].self, from: cloud.storage["tabs"]!)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.content, "scratch note")
        SettingsStore.shared.icloudSync = false
    }

    func testSaveSessionExcludesFileBackedTabs() {
        let cloud = MockKeyValueStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        SettingsStore.shared.icloudSync = true
        let tabStore = TabStore(sessionURL: url, cloudStore: cloud)
        tabStore.tabs[0].fileURL = URL(fileURLWithPath: "/tmp/test.swift")
        tabStore.saveSession()

        let decoded = try! JSONDecoder().decode([TabData].self, from: cloud.storage["tabs"]!)
        XCTAssertTrue(decoded.isEmpty)
        SettingsStore.shared.icloudSync = false
    }

    func testSaveSessionSkipsCloudWhenSyncDisabled() {
        let cloud = MockKeyValueStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        SettingsStore.shared.icloudSync = false
        let tabStore = TabStore(sessionURL: url, cloudStore: cloud)
        tabStore.saveSession()

        XCTAssertNil(cloud.storage["tabs"])
    }

    func testStopICloudSyncRemovesCloudData() {
        let cloud = MockKeyValueStore()
        cloud.storage["tabs"] = Data()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let tabStore = TabStore(sessionURL: url, cloudStore: cloud)
        tabStore.stopICloudSync()

        XCTAssertNil(cloud.storage["tabs"])
    }

    func testMergeCloudTabsAppendsNewTab() {
        let cloud = MockKeyValueStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        SettingsStore.shared.icloudSync = true
        let tabStore = TabStore(sessionURL: url, cloudStore: cloud)
        let initialCount = tabStore.tabs.count

        let cloudTab = TabData(name: "Cloud note", content: "from cloud", language: "plain")
        let cloudData = try! JSONEncoder().encode([cloudTab])
        cloud.storage["tabs"] = cloudData

        tabStore.startICloudSync()
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )

        XCTAssertEqual(tabStore.tabs.count, initialCount + 1)
        XCTAssertTrue(tabStore.tabs.contains(where: { $0.id == cloudTab.id }))
        SettingsStore.shared.icloudSync = false
    }

    func testMergeCloudTabsUpdatesExistingTab() {
        let cloud = MockKeyValueStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        SettingsStore.shared.icloudSync = true
        let tabStore = TabStore(sessionURL: url, cloudStore: cloud)
        let existingID = tabStore.tabs.first!.id

        let cloudTab = TabData(id: existingID, name: "Updated", content: "updated content", language: "swift")
        let cloudData = try! JSONEncoder().encode([cloudTab])
        cloud.storage["tabs"] = cloudData

        tabStore.startICloudSync()
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )

        XCTAssertEqual(tabStore.tabs.first?.content, "updated content")
        XCTAssertEqual(tabStore.tabs.first?.name, "Updated")
        XCTAssertEqual(tabStore.tabs.first?.language, "swift")
        SettingsStore.shared.icloudSync = false
    }
}
