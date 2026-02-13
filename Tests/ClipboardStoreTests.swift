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

    // MARK: - Cloud sync (applyCloudClipboardEntry / removeCloudClipboardEntry)

    func testApplyCloudClipboardEntryInsertsNewEntry() {
        store.entries = [
            ClipboardEntry(kind: .text, text: "local"),
        ]

        let record = CloudClipboardRecord(id: UUID(), text: "from cloud", timestamp: Date())
        store.applyCloudClipboardEntry(record)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(store.entries.contains(where: { $0.text == "from cloud" }))
    }

    func testApplyCloudClipboardEntrySkipsDuplicateUUID() {
        let sharedID = UUID()
        store.entries = [
            ClipboardEntry(id: sharedID, kind: .text, text: "local version"),
        ]

        let record = CloudClipboardRecord(id: sharedID, text: "cloud version", timestamp: Date())
        store.applyCloudClipboardEntry(record)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "local version")
    }

    func testApplyCloudClipboardEntrySkipsDuplicateText() {
        store.entries = [
            ClipboardEntry(kind: .text, text: "same text"),
        ]

        let record = CloudClipboardRecord(id: UUID(), text: "same text", timestamp: Date())
        store.applyCloudClipboardEntry(record)

        XCTAssertEqual(store.entries.count, 1)
    }

    func testApplyCloudClipboardEntryMaintainsChronologicalOrder() {
        let now = Date()
        store.entries = [
            ClipboardEntry(kind: .text, text: "newest", timestamp: now),
            ClipboardEntry(kind: .text, text: "oldest", timestamp: now.addingTimeInterval(-100)),
        ]

        let record = CloudClipboardRecord(id: UUID(), text: "middle", timestamp: now.addingTimeInterval(-50))
        store.applyCloudClipboardEntry(record)

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries[0].text, "newest")
        XCTAssertEqual(store.entries[1].text, "middle")
        XCTAssertEqual(store.entries[2].text, "oldest")
    }

    func testRemoveCloudClipboardEntryRemovesEntry() {
        let entry = ClipboardEntry(kind: .text, text: "will be removed")
        store.entries = [entry]

        store.removeCloudClipboardEntry(id: entry.id)

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRemoveCloudClipboardEntryIgnoresUnknownID() {
        store.entries = [ClipboardEntry(kind: .text, text: "keep")]

        store.removeCloudClipboardEntry(id: UUID())

        XCTAssertEqual(store.entries.count, 1)
    }

    func testRemoveCloudClipboardEntryCleansUpImageFile() throws {
        let fileName = "cloud-delete-test.png"
        let fileURL = tempImagesDir.appendingPathComponent(fileName)
        try Data([0x89, 0x50]).write(to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let entry = ClipboardEntry(kind: .image, imageFileName: fileName)
        store.entries = [entry]

        store.removeCloudClipboardEntry(id: entry.id)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - pruneExpiredEntries

    func testPruneRemovesExpiredEntries() {
        let now = Date()
        store.entries = [
            ClipboardEntry(kind: .text, text: "recent", timestamp: now),
            ClipboardEntry(kind: .text, text: "old", timestamp: now.addingTimeInterval(-7200)),
        ]
        store.pruneExpiredEntries(setting: "1h")
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "recent")
    }

    func testPruneKeepsEntriesWithinThreshold() {
        let now = Date()
        store.entries = [
            ClipboardEntry(kind: .text, text: "recent1", timestamp: now.addingTimeInterval(-3600)),
            ClipboardEntry(kind: .text, text: "recent2", timestamp: now.addingTimeInterval(-43200)),
        ]
        store.pruneExpiredEntries(setting: "1d")
        XCTAssertEqual(store.entries.count, 2)
    }

    func testPruneNeverRemovesNothing() {
        let now = Date()
        store.entries = [
            ClipboardEntry(kind: .text, text: "ancient", timestamp: now.addingTimeInterval(-999999)),
        ]
        store.pruneExpiredEntries(setting: "never")
        XCTAssertEqual(store.entries.count, 1)
    }

    func testPruneCleansUpImageFiles() throws {
        let fileName = "prune-test.png"
        let fileURL = tempImagesDir.appendingPathComponent(fileName)
        try Data([0x89, 0x50]).write(to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.entries = [
            ClipboardEntry(kind: .image, imageFileName: fileName, timestamp: Date().addingTimeInterval(-7200)),
        ]
        store.pruneExpiredEntries(setting: "1h")

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
