import XCTest
import CloudKit
@testable import ItsypadCore

final class CloudSyncEngineTests: XCTestCase {

    // MARK: - CloudTabRecord

    func testCloudTabRecordHoldsAllFields() {
        let id = UUID()
        let now = Date()
        let record = CloudTabRecord(
            id: id,
            name: "Test",
            content: "hello",
            language: "swift",
            languageLocked: true,
            lastModified: now
        )
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.name, "Test")
        XCTAssertEqual(record.content, "hello")
        XCTAssertEqual(record.language, "swift")
        XCTAssertTrue(record.languageLocked)
        XCTAssertEqual(record.lastModified, now)
    }

    // MARK: - CloudClipboardRecord

    func testCloudClipboardRecordHoldsAllFields() {
        let id = UUID()
        let now = Date()
        let record = CloudClipboardRecord(id: id, text: "copied text", timestamp: now)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.text, "copied text")
        XCTAssertEqual(record.timestamp, now)
    }

    // MARK: - RecordType raw values

    func testRecordTypeRawValues() {
        XCTAssertEqual(CloudSyncEngine.RecordType.scratchTab.rawValue, "ScratchTab")
        XCTAssertEqual(CloudSyncEngine.RecordType.clipboardEntry.rawValue, "ClipboardEntry")
    }
}
