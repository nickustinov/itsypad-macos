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
}
