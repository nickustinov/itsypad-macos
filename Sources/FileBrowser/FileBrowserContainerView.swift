import AppKit

final class FileBrowserContainerView: NSView {
    private let headerView = NSView()
    private let folderLabel = NSTextField(labelWithString: "")
    private let outlineViewController = FileBrowserOutlineView()
    private let emptyStateButton = NSButton()
    private let emptyStateHint = NSTextField(labelWithString: "")

    var onFileSelected: ((URL) -> Void)? {
        get { outlineViewController.onFileSelected }
        set { outlineViewController.onFileSelected = newValue }
    }

    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        registerForDraggedTypes([.fileURL])

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .settingsChanged, object: nil)
        applyTheme()

        // Header
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        addSubview(headerView)

        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        folderLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        headerView.addSubview(folderLabel)

        let openButton = NSButton(image: NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)!, target: self, action: #selector(openFolderAction))
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.isBordered = false
        openButton.toolTip = String(localized: "file_browser.open_folder_tooltip", defaultValue: "Open folder")
        headerView.addSubview(openButton)

        let closeFolderButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)!, target: self, action: #selector(closeFolderAction))
        closeFolderButton.translatesAutoresizingMaskIntoConstraints = false
        closeFolderButton.isBordered = false
        closeFolderButton.contentTintColor = .secondaryLabelColor
        closeFolderButton.toolTip = String(localized: "file_browser.close_folder_tooltip", defaultValue: "Close folder")
        closeFolderButton.tag = 1
        headerView.addSubview(closeFolderButton)

        // Outline view
        let outlineContainer = outlineViewController.view
        outlineContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outlineContainer)

        // Empty state – "Open folder" button
        emptyStateButton.translatesAutoresizingMaskIntoConstraints = false
        emptyStateButton.title = String(localized: "file_browser.open_folder_button", defaultValue: "Open folder...")
        emptyStateButton.bezelStyle = .rounded
        emptyStateButton.target = self
        emptyStateButton.action = #selector(openFolderAction)
        emptyStateButton.isHidden = true
        addSubview(emptyStateButton)

        emptyStateHint.translatesAutoresizingMaskIntoConstraints = false
        emptyStateHint.stringValue = "⇧⌘O or drag a folder"
        emptyStateHint.font = .systemFont(ofSize: 11)
        emptyStateHint.textColor = .tertiaryLabelColor
        emptyStateHint.alignment = .center
        emptyStateHint.isHidden = true
        addSubview(emptyStateHint)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 36),

            folderLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            folderLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            folderLabel.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -4),

            closeFolderButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -4),
            closeFolderButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeFolderButton.widthAnchor.constraint(equalToConstant: 20),
            closeFolderButton.heightAnchor.constraint(equalToConstant: 20),

            openButton.trailingAnchor.constraint(equalTo: closeFolderButton.leadingAnchor, constant: -2),
            openButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 20),
            openButton.heightAnchor.constraint(equalToConstant: 20),

            outlineContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            outlineContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outlineContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outlineContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyStateButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStateButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            emptyStateHint.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStateHint.topAnchor.constraint(equalTo: emptyStateButton.bottomAnchor, constant: 6),
        ])

        updateState()

        FileTreeStore.shared.onTreeChanged = { [weak self] in
            self?.outlineViewController.reloadData()
            self?.updateState()
        }
    }

    private func updateState() {
        let hasFolder = FileTreeStore.shared.rootURL != nil
        emptyStateButton.isHidden = hasFolder
        emptyStateHint.isHidden = hasFolder
        headerView.isHidden = !hasFolder
        folderLabel.stringValue = FileTreeStore.shared.rootURL?.lastPathComponent ?? ""
    }

    @objc private func applyTheme() {
        let theme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
        layer?.backgroundColor = theme.background.cgColor
        outlineViewController.applyTheme(theme)
    }

    @objc private func openFolderAction() {
        FileTreeStore.shared.openFolder()
    }

    @objc private func closeFolderAction() {
        FileTreeStore.shared.closeFolder()
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard folderURLFrom(sender) != nil else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let url = folderURLFrom(sender) else { return false }
        FileTreeStore.shared.setRootFolder(url)
        return true
    }

    private func folderURLFrom(_ sender: any NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return nil }
        var isDir: ObjCBool = false
        guard let url = urls.first,
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return url
    }
}
