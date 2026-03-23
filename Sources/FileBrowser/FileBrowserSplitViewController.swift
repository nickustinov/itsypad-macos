import AppKit

final class FileBrowserSplitViewController: NSSplitViewController {
    private let sidebarItem: NSSplitViewItem
    private let contentItem: NSSplitViewItem
    private let fileBrowserContainer = FileBrowserContainerView()

    init(contentView: NSView) {
        let sidebarVC = NSViewController()
        sidebarVC.view = fileBrowserContainer

        let contentVC = NSViewController()
        contentVC.view = contentView

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 120
        sidebarItem.maximumThickness = 400
        sidebarItem.preferredThicknessFraction = 0.2

        contentItem = NSSplitViewItem(viewController: contentVC)
        contentItem.minimumThickness = 320

        super.init(nibName: nil, bundle: nil)

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.autosaveName = "FileBrowserSplit"
        splitView.dividerStyle = .thin

        fileBrowserContainer.onClose = { [weak self] in
            self?.toggleSidebar()
        }

        // Restore sidebar state
        let visible = UserDefaults.standard.object(forKey: "fileBrowserSidebarVisible") as? Bool ?? false
        sidebarItem.isCollapsed = !visible

        // Restore folder
        if visible {
            FileTreeStore.shared.restoreFolder()
        }
    }

    // MARK: - Public

    var onFileSelected: ((URL) -> Void)? {
        get { fileBrowserContainer.onFileSelected }
        set { fileBrowserContainer.onFileSelected = newValue }
    }

    func toggleSidebar() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            sidebarItem.animator().isCollapsed.toggle()
        }

        let visible = !sidebarItem.isCollapsed
        UserDefaults.standard.set(visible, forKey: "fileBrowserSidebarVisible")

        // Restore folder on first open if not yet loaded
        if visible, FileTreeStore.shared.rootURL == nil {
            FileTreeStore.shared.restoreFolder()
        }
    }

    func openFolder() {
        FileTreeStore.shared.openFolder()
        if sidebarItem.isCollapsed, FileTreeStore.shared.rootURL != nil {
            toggleSidebar()
        }
    }

    var isSidebarVisible: Bool {
        !sidebarItem.isCollapsed
    }
}
