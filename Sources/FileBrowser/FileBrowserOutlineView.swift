import AppKit

private final class ArrowCursorOutlineView: NSOutlineView {
    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .arrow)
    }
}

private final class SubtleRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set { }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.08).setFill()
        bounds.fill()
    }
}

final class FileBrowserOutlineView: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let outlineView = ArrowCursorOutlineView()
    private let scrollView = NSScrollView()
    private let store = FileTreeStore.shared
    private var expandedURLs: Set<URL> = []

    var onFileSelected: ((URL) -> Void)?
    private var currentTheme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)

    override func loadView() {
        view = scrollView

        outlineView.headerView = nil
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 14
        outlineView.autoresizesOutlineColumn = true
        outlineView.floatsGroupRows = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(rowDoubleClicked)
        outlineView.style = .sourceList

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        store.onTreeChanged = { [weak self] in
            self?.reloadData()
        }
    }

    func applyTheme(_ theme: EditorTheme) {
        currentTheme = theme
        outlineView.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        outlineView.reloadData()
    }

    func reloadData() {
        let expanded = expandedURLs
        outlineView.reloadData()
        restoreExpansion(expanded)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return store.rootNode?.children?.count ?? 0
        }
        guard let node = item as? FileNode else { return 0 }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            guard let children = store.rootNode?.children, index < children.count else {
                NSLog("[FileBrowser] ERROR: child(%d) of root but children is nil or out of bounds", index)
                return FileNode(url: URL(fileURLWithPath: "/"), name: "?", isDirectory: false)
            }
            return children[index]
        }
        guard let node = item as? FileNode, let children = node.children, index < children.count else {
            NSLog("[FileBrowser] ERROR: child(%d) of %@ but children is nil or out of bounds", index, (item as? FileNode)?.name ?? "?")
            return FileNode(url: URL(fileURLWithPath: "/"), name: "?", isDirectory: false)
        }
        return children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.isDirectory
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        return SubtleRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }

        let cellID = NSUserInterfaceItemIdentifier("FileCell")
        let cell: NSTableCellView
        if let existing = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = .systemFont(ofSize: 12)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        cell.textField?.stringValue = node.name
        cell.textField?.textColor = currentTheme.foreground
        cell.imageView?.image = icon(for: node)
        cell.imageView?.contentTintColor = currentTheme.foreground.withAlphaComponent(0.7)

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let node = item as? FileNode, node.isDirectory else { return false }
        // Pre-load children before expand so the data source is ready
        if node.children == nil || node.children?.isEmpty == true {
            node.children = store.loadChildren(of: node.url)
            NSLog("[FileBrowser] Pre-loaded %d children for %@", node.children?.count ?? 0, node.name)
        }
        return true
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        expandedURLs.insert(node.url)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        expandedURLs.remove(node.url)
    }

    // MARK: - Click handling

    @objc private func rowDoubleClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }

        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else if Self.isTextFile(node.url) {
            onFileSelected?(node.url)
        } else {
            NSWorkspace.shared.open(node.url)
        }
    }

    private static func isTextFile(_ url: URL) -> Bool {
        guard let uti = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return uti.conforms(to: .text) || uti.conforms(to: .sourceCode) || uti.conforms(to: .script)
            || uti.conforms(to: .json) || uti.conforms(to: .xml) || uti.conforms(to: .yaml)
            || uti.conforms(to: .propertyList)
    }

    // MARK: - Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }

        let revealItem = NSMenuItem(
            title: String(localized: "file_browser.reveal_in_finder", defaultValue: "Reveal in Finder"),
            action: #selector(revealInFinder(_:)),
            keyEquivalent: ""
        )
        revealItem.representedObject = node.url
        revealItem.target = self
        menu.addItem(revealItem)

        let copyItem = NSMenuItem(
            title: String(localized: "file_browser.copy_path", defaultValue: "Copy path"),
            action: #selector(copyPath(_:)),
            keyEquivalent: ""
        )
        copyItem.representedObject = node.url
        copyItem.target = self
        menu.addItem(copyItem)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    // MARK: - Helpers

    private func icon(for node: FileNode) -> NSImage {
        if node.isDirectory {
            return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
                ?? NSWorkspace.shared.icon(forFile: node.url.path)
        }
        let icon = NSWorkspace.shared.icon(forFile: node.url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func restoreExpansion(_ urls: Set<URL>) {
        for i in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: i) as? FileNode else { continue }
            if urls.contains(node.url), !outlineView.isItemExpanded(node) {
                outlineView.expandItem(node)
            }
        }
    }
}
