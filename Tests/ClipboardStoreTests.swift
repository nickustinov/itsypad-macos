import XCTest
@testable import ItsypadCore

final class ClipboardStoreTests: XCTestCase {
    private var store: ClipboardStore!
    private var tempURL: URL!
    private var tempImagesDir: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        tempImagesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        store = ClipboardStore(storageURL: tempURL, imagesDirectory: tempImagesDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempImagesDir)
        store = nil
        super.tearDown()
    }

    // MARK: - search

    func testSearchEmptyQueryReturnsAll() {
        store.entries = [
            ClipboardEntry(kind: .text, text: "hello"),
            ClipboardEntry(kind: .text, text: "world"),
        ]
        let results = store.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchMatchingFilters() {
        store.entries = [
            ClipboardEntry(kind: .text, text: "hello world"),
            ClipboardEntry(kind: .text, text: "goodbye"),
        ]
        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "hello world")
    }

    func testSearchNoMatch() {
        store.entries = [
            ClipboardEntry(kind: .text, text: "hello"),
        ]
        let results = store.search(query: "xyz")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchCaseInsensitive() {
        store.entries = [
            ClipboardEntry(kind: .text, text: "Hello World"),
        ]
        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchImageByKeyword() {
        store.entries = [
            ClipboardEntry(kind: .image, imageFileName: "test.png"),
            ClipboardEntry(kind: .text, text: "hello"),
        ]
        let results = store.search(query: "image")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .image)
    }

    // MARK: - deleteEntry

    func testDeleteEntry() {
        let entry = ClipboardEntry(kind: .text, text: "to delete")
        store.entries = [entry, ClipboardEntry(kind: .text, text: "keep")]
        store.deleteEntry(id: entry.id)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "keep")
    }

    func testDeleteNonexistentIDNoOp() {
        let entry = ClipboardEntry(kind: .text, text: "keep")
        store.entries = [entry]
        store.deleteEntry(id: UUID())
        XCTAssertEqual(store.entries.count, 1)
    }

    func testDeleteImageEntryRemovesFile() throws {
        let fileName = "test-delete.png"
        let fileURL = tempImagesDir.appendingPathComponent(fileName)
        try Data([0x89, 0x50]).write(to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let entry = ClipboardEntry(kind: .image, imageFileName: fileName)
        store.entries = [entry]
        store.deleteEntry(id: entry.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - clearAll

    func testClearAllRemovesAllEntries() {
        store.entries = [
            ClipboardEntry(kind: .text, text: "one"),
            ClipboardEntry(kind: .text, text: "two"),
        ]
        store.clearAll()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testClearAllRemovesImageFiles() throws {
        let fileName = "test-clear.png"
        let fileURL = tempImagesDir.appendingPathComponent(fileName)
        try Data([0x89, 0x50]).write(to: fileURL)

        store.entries = [ClipboardEntry(kind: .image, imageFileName: fileName)]
        store.clearAll()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testClearAllOnEmptyIsNoOp() {
        store.clearAll()
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - Persistence

    func testPersistenceRoundtrip() {
        store.entries = [
            ClipboardEntry(kind: .text, text: "persisted"),
        ]
        store.saveEntries()

        let restored = ClipboardStore(storageURL: tempURL, imagesDirectory: tempImagesDir)
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(restored.entries.first?.text, "persisted")
    }

    func testMissingFileStartsEmpty() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let freshStore = ClipboardStore(storageURL: missingURL, imagesDirectory: tempImagesDir)
        XCTAssertTrue(freshStore.entries.isEmpty)
    }

    // MARK: - ClipboardEntry Codable

    func testClipboardEntryCodableRoundtrip() throws {
        let entry = ClipboardEntry(kind: .text, text: "test content")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }

    func testClipboardContentKindCodableRoundtrip() throws {
        for kind in [ClipboardContentKind.text, .image] {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(ClipboardContentKind.self, from: data)
            XCTAssertEqual(kind, decoded)
        }
    }

    func testImageEntryCodableRoundtrip() throws {
        let entry = ClipboardEntry(kind: .image, imageFileName: "abc123.png")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.imageFileName, "abc123.png")
        XCTAssertNil(decoded.text)
    }

    // MARK: - iCloud sync

    func testSaveClipboardToCloudEncodesTextOnly() {
        let cloud = MockKeyValueStore()
        store.entries = [
            ClipboardEntry(kind: .text, text: "hello"),
            ClipboardEntry(kind: .image, imageFileName: "img.png"),
            ClipboardEntry(kind: .text, text: "world"),
        ]
        store.saveClipboardToCloud(cloud)

        let data = cloud.storage["clipboard"]!
        let decoded = try! JSONDecoder().decode([ClipboardCloudEntry].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].text, "hello")
        XCTAssertEqual(decoded[1].text, "world")
    }

    func testSaveClipboardToCloudCapsAt200() {
        let cloud = MockKeyValueStore()
        store.entries = (0..<300).map { i in
            ClipboardEntry(kind: .text, text: "entry \(i)")
        }
        store.saveClipboardToCloud(cloud)

        let data = cloud.storage["clipboard"]!
        let decoded = try! JSONDecoder().decode([ClipboardCloudEntry].self, from: data)
        XCTAssertEqual(decoded.count, 200)
    }

    func testMergeCloudClipboardInsertsNewEntries() {
        let cloud = MockKeyValueStore()
        SettingsStore.shared.icloudSync = true

        store.entries = [
            ClipboardEntry(kind: .text, text: "local"),
        ]

        let cloudEntry = ClipboardCloudEntry(id: UUID(), text: "from cloud", timestamp: Date())
        let cloudData = try! JSONEncoder().encode([cloudEntry])
        cloud.storage["clipboard"] = cloudData

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(store.entries.contains(where: { $0.text == "from cloud" }))
        SettingsStore.shared.icloudSync = false
    }

    func testMergeCloudClipboardSkipsDuplicateUUIDs() {
        let cloud = MockKeyValueStore()
        SettingsStore.shared.icloudSync = true

        let sharedID = UUID()
        store.entries = [
            ClipboardEntry(id: sharedID, kind: .text, text: "local version"),
        ]

        let cloudEntry = ClipboardCloudEntry(id: sharedID, text: "cloud version", timestamp: Date())
        let cloudData = try! JSONEncoder().encode([cloudEntry])
        cloud.storage["clipboard"] = cloudData

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "local version")
        SettingsStore.shared.icloudSync = false
    }

    func testMergeCloudClipboardMaintainsChronologicalOrder() {
        let cloud = MockKeyValueStore()
        SettingsStore.shared.icloudSync = true

        let now = Date()
        store.entries = [
            ClipboardEntry(kind: .text, text: "newest", timestamp: now),
            ClipboardEntry(kind: .text, text: "oldest", timestamp: now.addingTimeInterval(-100)),
        ]

        let cloudEntry = ClipboardCloudEntry(id: UUID(), text: "middle", timestamp: now.addingTimeInterval(-50))
        let cloudData = try! JSONEncoder().encode([cloudEntry])
        cloud.storage["clipboard"] = cloudData

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries[0].text, "newest")
        XCTAssertEqual(store.entries[1].text, "middle")
        XCTAssertEqual(store.entries[2].text, "oldest")
        SettingsStore.shared.icloudSync = false
    }

    func testClearCloudDataRemovesKey() {
        let cloud = MockKeyValueStore()
        cloud.storage["clipboard"] = Data()
        cloud.storage["deletedClipboardIDs"] = Data()
        store.clearCloudData(from: cloud)
        XCTAssertNil(cloud.storage["clipboard"])
        XCTAssertNil(cloud.storage["deletedClipboardIDs"])
    }

    // MARK: - Tombstones

    func testMergeSkipsTombstonedCloudEntries() {
        let cloud = MockKeyValueStore()
        SettingsStore.shared.icloudSync = true

        let tombstonedID = UUID()
        let normalID = UUID()

        // Write tombstone to cloud
        let tombstoneData = try! JSONEncoder().encode([tombstonedID.uuidString])
        cloud.storage["deletedClipboardIDs"] = tombstoneData

        // Write cloud entries including the tombstoned one
        let cloudEntries = [
            ClipboardCloudEntry(id: tombstonedID, text: "deleted", timestamp: Date()),
            ClipboardCloudEntry(id: normalID, text: "kept", timestamp: Date()),
        ]
        cloud.storage["clipboard"] = try! JSONEncoder().encode(cloudEntries)

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, normalID)
        XCTAssertEqual(store.entries.first?.text, "kept")
        SettingsStore.shared.icloudSync = false
    }

    func testMergeRemovesTombstonedLocalEntries() {
        let cloud = MockKeyValueStore()
        SettingsStore.shared.icloudSync = true

        let id = UUID()
        store.entries = [ClipboardEntry(id: id, kind: .text, text: "will be removed")]

        // Write tombstone to cloud for the local entry
        let tombstoneData = try! JSONEncoder().encode([id.uuidString])
        cloud.storage["deletedClipboardIDs"] = tombstoneData

        store.mergeCloudClipboard(from: cloud)

        XCTAssertTrue(store.entries.isEmpty)
        SettingsStore.shared.icloudSync = false
    }

    func testMergeRemovesTombstonedLocalEntriesWithNoCloudData() {
        let cloud = MockKeyValueStore()
        SettingsStore.shared.icloudSync = true

        let id = UUID()
        store.entries = [ClipboardEntry(id: id, kind: .text, text: "will be removed")]

        // Write tombstone but no clipboard data
        let tombstoneData = try! JSONEncoder().encode([id.uuidString])
        cloud.storage["deletedClipboardIDs"] = tombstoneData

        store.mergeCloudClipboard(from: cloud)

        XCTAssertTrue(store.entries.isEmpty)
        SettingsStore.shared.icloudSync = false
    }

    func testMergeTombstonesCleansUpImageFiles() throws {
        let cloud = MockKeyValueStore()
        SettingsStore.shared.icloudSync = true

        let fileName = "tombstone-test.png"
        let fileURL = tempImagesDir.appendingPathComponent(fileName)
        try Data([0x89, 0x50]).write(to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let id = UUID()
        store.entries = [ClipboardEntry(id: id, kind: .image, imageFileName: fileName)]

        let tombstoneData = try! JSONEncoder().encode([id.uuidString])
        cloud.storage["deletedClipboardIDs"] = tombstoneData

        store.mergeCloudClipboard(from: cloud)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        SettingsStore.shared.icloudSync = false
    }

    func testMergeWithTombstonesPreservesNonTombstonedEntries() {
        let cloud = MockKeyValueStore()
        SettingsStore.shared.icloudSync = true

        let tombstonedID = UUID()
        let keptID = UUID()
        store.entries = [
            ClipboardEntry(id: tombstonedID, kind: .text, text: "remove me"),
            ClipboardEntry(id: keptID, kind: .text, text: "keep me"),
        ]

        let tombstoneData = try! JSONEncoder().encode([tombstonedID.uuidString])
        cloud.storage["deletedClipboardIDs"] = tombstoneData

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, keptID)
        SettingsStore.shared.icloudSync = false
    }
}
