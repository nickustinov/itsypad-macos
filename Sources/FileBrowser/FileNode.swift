import Foundation

final class FileNode: NSObject {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    init(url: URL, name: String, isDirectory: Bool, children: [FileNode]? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
    }

    override var hash: Int { url.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FileNode else { return false }
        return url == other.url
    }

    // MARK: - Filtering and sorting

    private static let denyList: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".DS_Store",
        "__pycache__", ".build", ".swiftpm", "Pods", "DerivedData",
    ]

    static func shouldInclude(_ name: String, isHidden: Bool) -> Bool {
        if isHidden { return false }
        return !denyList.contains(name)
    }

    static func sorted(_ nodes: [FileNode]) -> [FileNode] {
        nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
