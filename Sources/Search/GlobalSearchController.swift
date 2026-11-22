import Cocoa

/// Borderless panel that can take key focus so the search field is typeable.
private final class GlobalSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Presents the Spotlight-style global search overlay as a child of the editor window.
@MainActor
final class GlobalSearchController {
    /// Supplies the tabs to search.
    var tabsProvider: () -> [GlobalSearch.Source] = { [] }
    /// Reveals a chosen match in the editor (tab id + range in that tab's content).
    var onReveal: ((UUID, NSRange) -> Void)?
    var onOpenFile: ((URL) -> Void)?

    private let contentView = GlobalSearchView()
    private var panel: GlobalSearchPanel?
    private weak var parentWindow: NSWindow?
    private var resignObserver: Any?
    private var isShown = false
    private var lastResignDismissAt: Date?

    private static let panelWidth: CGFloat = 600
    private static let panelHeight: CGFloat = 420
    private static let topInset: CGFloat = 100
    /// Clicking the toolbar icon while open resigns the panel's key state (closing it) just
    /// before the toolbar action fires; this window treats that follow-up as "stay closed".
    private static let reopenSuppressionWindow: TimeInterval = 0.3

    var isVisible: Bool { isShown }

    /// Opens the overlay, or closes it if already open (⇧⌘F / toolbar icon toggle).
    func toggle(over parent: NSWindow) {
        if isShown {
            dismiss()
            return
        }
        // A click that just closed the overlay (via resign) shouldn't immediately reopen it.
        if let last = lastResignDismissAt, Date().timeIntervalSince(last) < Self.reopenSuppressionWindow {
            return
        }
        present(over: parent)
    }

    func present(over parent: NSWindow) {
        parentWindow = parent

        let panel = self.panel ?? makePanel()
        self.panel = panel
        applyTheme(to: panel)
        isShown = true

        position(panel, over: parent)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        contentView.prepareForDisplay()

        // Dismiss when the overlay loses key focus (e.g. clicking back into the editor).
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(viaResign: true) }
            }
        }
    }

    func toggleFolderSearch(over parent: NSWindow, root: URL) {
        if isShown {
            dismiss()
            return
        }
        contentView.folderRoot = root
        present(over: parent)
    }

    func dismiss(viaResign: Bool = false) {
        guard isShown, let panel else { return }
        isShown = false
        if viaResign { lastResignDismissAt = Date() }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        parentWindow?.makeKey()
    }

    // MARK: - Panel construction

    private func makePanel() -> GlobalSearchPanel {
        let panel = GlobalSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.onActivate = { [weak self] tabID, range in
            self?.dismiss()
            self?.onReveal?(tabID, range)
        }
        contentView.onClose = { [weak self] in self?.dismiss() }
        contentView.onOpenFile = { [weak self] url in
            self?.dismiss()
            self?.onOpenFile?(url)
        }
        contentView.tabsProvider = { [weak self] in self?.tabsProvider() ?? [] }

        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        panel.contentView = container
        return panel
    }

    private func position(_ panel: NSPanel, over parent: NSWindow) {
        let parentFrame = parent.frame
        let x = parentFrame.midX - Self.panelWidth / 2
        let y = parentFrame.maxY - Self.topInset - Self.panelHeight
        panel.setFrame(NSRect(x: x, y: y, width: Self.panelWidth, height: Self.panelHeight), display: true)
    }

    private func applyTheme(to panel: NSPanel) {
        let theme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
        contentView.isDark = theme.isDark
        contentView.themeBackground = theme.background
        panel.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)

        let border: NSColor = theme.isDark ? .white : .black
        (panel.contentView)?.layer?.borderColor = (theme.background.blended(withFraction: 0.18, of: border) ?? .gridColor).cgColor
    }
}
