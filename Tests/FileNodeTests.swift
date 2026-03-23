import XCTest
@testable import ItsypadCore

final class FileNodeTests: XCTestCase {

    // MARK: - Filtering

    func testHiddenFilesExcluded() {
        XCTAssertFalse(FileNode.shouldInclude(".hidden", isHidden: true))
    }

    func testDSStoreExcluded() {
        XCTAssertFalse(FileNode.shouldInclude(".DS_Store", isHidden: false))
    }

    func testGitExcluded() {
        XCTAssertFalse(FileNode.shouldInclude(".git", isHidden: false))
    }

    func testNodeModulesExcluded() {
        XCTAssertFalse(FileNode.shouldInclude("node_modules", isHidden: false))
    }

    func testNormalFileIncluded() {
        XCTAssertTrue(FileNode.shouldInclude("readme.md", isHidden: false))
    }

    func testNormalFolderIncluded() {
        XCTAssertTrue(FileNode.shouldInclude("src", isHidden: false))
    }

    // MARK: - Sorting

    func testDirectoriesBeforeFiles() {
        let nodes = [
            FileNode(url: URL(fileURLWithPath: "/b.txt"), name: "b.txt", isDirectory: false, children: nil),
            FileNode(url: URL(fileURLWithPath: "/a"), name: "a", isDirectory: true, children: []),
        ]
        let sorted = FileNode.sorted(nodes)
        XCTAssertTrue(sorted[0].isDirectory)
        XCTAssertFalse(sorted[1].isDirectory)
    }

    func testAlphabeticalWithinSameType() {
        let nodes = [
            FileNode(url: URL(fileURLWithPath: "/c.txt"), name: "c.txt", isDirectory: false, children: nil),
            FileNode(url: URL(fileURLWithPath: "/a.txt"), name: "a.txt", isDirectory: false, children: nil),
            FileNode(url: URL(fileURLWithPath: "/b.txt"), name: "b.txt", isDirectory: false, children: nil),
        ]
        let sorted = FileNode.sorted(nodes)
        XCTAssertEqual(sorted.map(\.name), ["a.txt", "b.txt", "c.txt"])
    }

    func testCaseInsensitiveSorting() {
        let nodes = [
            FileNode(url: URL(fileURLWithPath: "/Zebra"), name: "Zebra", isDirectory: true, children: []),
            FileNode(url: URL(fileURLWithPath: "/apple"), name: "apple", isDirectory: true, children: []),
        ]
        let sorted = FileNode.sorted(nodes)
        XCTAssertEqual(sorted.map(\.name), ["apple", "Zebra"])
    }
}
