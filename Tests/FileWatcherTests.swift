import XCTest
@testable import ItsypadCore

final class FileWatcherTests: XCTestCase {
    private var watcher: FileWatcher!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        watcher = FileWatcher()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        watcher.stopAll()
        watcher = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func tempFile(_ name: String = "test.txt") -> URL {
        tempDir.appendingPathComponent(name)
    }

    // MARK: - watch

    func testWatchFiresCallbackOnWrite() {
        let fileURL = tempFile()
        try! "initial".write(to: fileURL, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "callback fires")
        watcher.watch(url: fileURL) {
            expectation.fulfill()
        }

        try! "modified".write(to: fileURL, atomically: true, encoding: .utf8)
        waitForExpectations(timeout: 2)
    }

    func testWatchNonexistentFileIsNoOp() {
        let fileURL = tempFile("nonexistent.txt")
        let unexpected = expectation(description: "callback should not fire")
        unexpected.isInverted = true
        watcher.watch(url: fileURL) {
            unexpected.fulfill()
        }
        waitForExpectations(timeout: 0.5)
    }

    // MARK: - stop

    func testStopPreventsCallback() {
        let fileURL = tempFile()
        try! "initial".write(to: fileURL, atomically: true, encoding: .utf8)

        let unexpected = expectation(description: "callback should not fire")
        unexpected.isInverted = true
        watcher.watch(url: fileURL) {
            unexpected.fulfill()
        }
        watcher.stop(url: fileURL)

        try! "modified".write(to: fileURL, atomically: true, encoding: .utf8)

        waitForExpectations(timeout: 0.5)
    }

    func testStopNonWatchedURLIsNoOp() {
        let fileURL = tempFile("never-watched.txt")
        watcher.stop(url: fileURL)
        // Should not crash
    }

    // MARK: - stopAll

    func testStopAllPreventsAllCallbacks() {
        let file1 = tempFile("a.txt")
        let file2 = tempFile("b.txt")
        try! "a".write(to: file1, atomically: true, encoding: .utf8)
        try! "b".write(to: file2, atomically: true, encoding: .utf8)

        let unexpected1 = expectation(description: "file1 callback should not fire")
        unexpected1.isInverted = true
        let unexpected2 = expectation(description: "file2 callback should not fire")
        unexpected2.isInverted = true
        watcher.watch(url: file1) { unexpected1.fulfill() }
        watcher.watch(url: file2) { unexpected2.fulfill() }
        watcher.stopAll()

        try! "a2".write(to: file1, atomically: true, encoding: .utf8)
        try! "b2".write(to: file2, atomically: true, encoding: .utf8)

        waitForExpectations(timeout: 0.5)
    }

    // MARK: - Debounce

    func testDebounceCoalescesRapidWrites() {
        let fileURL = tempFile()
        try! "initial".write(to: fileURL, atomically: true, encoding: .utf8)

        var callCount = 0
        let expectation = expectation(description: "debounced callback")
        watcher.watch(url: fileURL) {
            callCount += 1
            expectation.fulfill()
        }

        // Rapid writes
        for i in 0..<5 {
            try! "write \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        waitForExpectations(timeout: 2)
        // Debounce should coalesce into 1 callback (may occasionally be 2 due to timing)
        XCTAssertLessThanOrEqual(callCount, 2)
    }

    // MARK: - Re-watch replaces previous

    func testReWatchReplacesPrevious() {
        let fileURL = tempFile()
        try! "initial".write(to: fileURL, atomically: true, encoding: .utf8)

        var firstCallCount = 0
        watcher.watch(url: fileURL) { firstCallCount += 1 }

        // Replace with new watcher
        let expectation = expectation(description: "second callback fires")
        watcher.watch(url: fileURL) {
            expectation.fulfill()
        }

        try! "modified".write(to: fileURL, atomically: true, encoding: .utf8)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(firstCallCount, 0)
    }

    // MARK: - Multiple files

    func testWatchMultipleFilesIndependently() {
        let file1 = tempFile("one.txt")
        let file2 = tempFile("two.txt")
        try! "1".write(to: file1, atomically: true, encoding: .utf8)
        try! "2".write(to: file2, atomically: true, encoding: .utf8)

        let exp1 = expectation(description: "file1 callback")
        let exp2 = expectation(description: "file2 callback")

        watcher.watch(url: file1) { exp1.fulfill() }
        watcher.watch(url: file2) { exp2.fulfill() }

        try! "1-modified".write(to: file1, atomically: true, encoding: .utf8)
        try! "2-modified".write(to: file2, atomically: true, encoding: .utf8)

        waitForExpectations(timeout: 2)
    }
}
