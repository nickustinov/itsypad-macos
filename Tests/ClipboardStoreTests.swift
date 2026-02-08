import XCTest
@testable import ItsypadCore

final class ClipboardStoreTests: XCTestCase {
    private var store: ClipboardStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        store = ClipboardStore(storageURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        store = nil
        super.tearDown()
    }

    // MARK: - search

    func testSearchEmptyQueryReturnsAll() {
        store.entries = [
            ClipboardEntry(content: "hello"),
            ClipboardEntry(content: "world"),
        ]
        let results = store.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchMatchingFilters() {
        store.entries = [
            ClipboardEntry(content: "hello world"),
            ClipboardEntry(content: "goodbye"),
        ]
        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, "hello world")
    }

    func testSearchNoMatch() {
        store.entries = [
            ClipboardEntry(content: "hello"),
        ]
        let results = store.search(query: "xyz")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchCaseInsensitive() {
        store.entries = [
            ClipboardEntry(content: "Hello World"),
        ]
        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - deleteEntry

    func testDeleteEntry() {
        let entry = ClipboardEntry(content: "to delete")
        store.entries = [entry, ClipboardEntry(content: "keep")]
        store.deleteEntry(id: entry.id)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.content, "keep")
    }

    func testDeleteNonexistentIDNoOp() {
        let entry = ClipboardEntry(content: "keep")
        store.entries = [entry]
        store.deleteEntry(id: UUID())
        XCTAssertEqual(store.entries.count, 1)
    }

    // MARK: - Persistence

    func testPersistenceRoundtrip() {
        store.entries = [
            ClipboardEntry(content: "persisted"),
        ]
        store.saveEntries()

        let restored = ClipboardStore(storageURL: tempURL)
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(restored.entries.first?.content, "persisted")
    }

    func testMissingFileStartsEmpty() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let freshStore = ClipboardStore(storageURL: missingURL)
        XCTAssertTrue(freshStore.entries.isEmpty)
    }

    // MARK: - ClipboardEntry Codable

    func testClipboardEntryCodableRoundtrip() throws {
        let entry = ClipboardEntry(content: "test content")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }
}
