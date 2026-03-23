import AppKit

final class FileTreeStore {
    static let shared = FileTreeStore()

    private(set) var rootURL: URL?
    private(set) var rootNode: FileNode?
    private var folderWatcher: FileWatcher?
    var onTreeChanged: (() -> Void)?

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Folder management

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "file_browser.open_folder_message", defaultValue: "Choose a folder to browse")
        panel.prompt = String(localized: "file_browser.open_folder_prompt", defaultValue: "Open")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRootFolder(url)
    }

    func setRootFolder(_ url: URL) {
        stopWatching()
        rootURL?.stopAccessingSecurityScopedResource()

        // Save security-scoped bookmark
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmark, forKey: "fileBrowserRootBookmark")
        }

        rootURL = url
        reload()
        startWatching()
    }

    func restoreFolder() {
        guard let data = defaults.data(forKey: "fileBrowserRootBookmark") else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return }

        if isStale {
            if let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: "fileBrowserRootBookmark")
            }
        }

        guard url.startAccessingSecurityScopedResource() else { return }
        rootURL = url
        reload()
        startWatching()
    }

    func closeFolder() {
        stopWatching()
        rootURL?.stopAccessingSecurityScopedResource()
        rootURL = nil
        rootNode = nil
        defaults.removeObject(forKey: "fileBrowserRootBookmark")
        onTreeChanged?()
    }

    // MARK: - Tree loading

    func reload() {
        guard let rootURL else {
            rootNode = nil
            onTreeChanged?()
            return
        }
        rootNode = buildNode(for: rootURL)
        rootNode?.children = loadChildren(of: rootURL)
        onTreeChanged?()
    }

    func loadChildren(of url: URL) -> [FileNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let nodes: [FileNode] = contents.compactMap { childURL in
            let name = childURL.lastPathComponent
            guard FileNode.shouldInclude(name, isHidden: false) else { return nil }

            let isDir = childURL.hasDirectoryPath
            return FileNode(url: childURL, name: name, isDirectory: isDir, children: isDir ? [] : nil)
        }

        return FileNode.sorted(nodes)
    }

    private func buildNode(for url: URL) -> FileNode {
        FileNode(url: url, name: url.lastPathComponent, isDirectory: true, children: nil)
    }

    // MARK: - Watching

    private func startWatching() {
        guard let rootURL else { return }
        folderWatcher = FileWatcher()
        folderWatcher?.watch(url: rootURL) { [weak self] in
            self?.reload()
        }
    }

    private func stopWatching() {
        folderWatcher?.stopAll()
        folderWatcher = nil
    }
}
