import Cocoa

private let cardCellID = NSUserInterfaceItemIdentifier("ClipboardCard")
private let tileMinWidth: CGFloat = 200
private let tileSpacing: CGFloat = 8
private let sectionInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

// MARK: - Clipboard content view

class ClipboardContentView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout,
    NSSearchFieldDelegate, ClipboardCollectionViewKeyDelegate {
    private let searchField = NSSearchField()
    private let clearAllButton = NSButton()
    private let scrollView = NSScrollView()
    private let collectionView = ClipboardCollectionView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var filteredEntries: [ClipboardEntry] = []
    private var clipboardObserver: Any?
    private var tabSelectedObserver: Any?
    private var settingsObserver: Any?
    private var lastLayoutWidth: CGFloat = 0
    private var currentSearchQuery: String = ""
    private var previewOverlay: ClipboardPreviewOverlay?
    private var selectedIndex: Int?
    private var shortcutMonitor: Any?
    private var windowKeyObserver: Any?

    var themeBackground: NSColor = .windowBackgroundColor {
        didSet { applyTheme() }
    }
    var isDark: Bool = false {
        didSet { applyTheme() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        // Search field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = String(localized: "clipboard.search_placeholder", defaultValue: "Search clipboard...")
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.delegate = self

        // Clear all button
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false
        clearAllButton.title = String(localized: "clipboard.clear_all", defaultValue: "Clear all")
        clearAllButton.bezelStyle = .accessoryBarAction
        clearAllButton.font = NSFont.systemFont(ofSize: 11)
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAllClicked)

        // Flow layout
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = tileSpacing
        layout.minimumLineSpacing = tileSpacing
        layout.sectionInset = sectionInsets

        // Collection view
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ClipboardCardItem.self, forItemWithIdentifier: cardCellID)
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.keyDelegate = self

        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        // Empty label
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = NSFont.systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        addSubview(searchField)
        addSubview(clearAllButton)
        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: clearAllButton.leadingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            clearAllButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            clearAllButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
        ])

        clipboardObserver = NotificationCenter.default.addObserver(
            forName: ClipboardStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadEntries()
        }

        tabSelectedObserver = NotificationCenter.default.addObserver(
            forName: ClipboardStore.clipboardTabSelectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.focusSearchField()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.lastLayoutWidth = 0
            self.collectionView.collectionViewLayout?.invalidateLayout()
            self.collectionView.reloadData()
        }

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isClipboardTabVisible else { return event }
            return self.handleShortcutKeyEvent(event) ? nil : event
        }

        windowKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let window = notification.object as? NSWindow,
                  window === self.window,
                  self.isClipboardTabVisible else { return }
            window.makeFirstResponder(self.searchField)
        }

        reloadEntries()
    }

    deinit {
        if let observer = clipboardObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = tabSelectedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = windowKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func focusSearchField() {
        // Defer to next run-loop pass so SwiftUI layout is settled
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.searchField)
        }
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(visibleRect, cursor: .arrow)
    }

    override func layout() {
        super.layout()
        let width = scrollView.bounds.width
        if width != lastLayoutWidth {
            lastLayoutWidth = width
            collectionView.collectionViewLayout?.invalidateLayout()
        }
    }

    @objc private func searchChanged() {
        reloadEntries()
    }

    @objc private func clearAllClicked() {
        guard !ClipboardStore.shared.entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "clipboard.clear_alert.title", defaultValue: "Clear clipboard history?")
        alert.informativeText = String(localized: "clipboard.clear_alert.message", defaultValue: "This will delete all \(ClipboardStore.shared.entries.count) entries. This cannot be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "clipboard.clear_alert.confirm", defaultValue: "Clear all"))
        alert.addButton(withTitle: String(localized: "clipboard.clear_alert.cancel", defaultValue: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ClipboardStore.shared.clearAll()
    }

    func reloadEntries() {
        let query = searchField.stringValue
        currentSearchQuery = query
        filteredEntries = ClipboardStore.shared.search(query: query)
        selectedIndex = nil

        let isEmpty = filteredEntries.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyLabel.stringValue = query.isEmpty ? String(localized: "clipboard.empty", defaultValue: "Clipboard history is empty") : String(localized: "clipboard.no_matches", defaultValue: "No matches")

        collectionView.reloadData()
    }

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredEntries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: cardCellID, for: indexPath)
        if let cardItem = item as? ClipboardCardItem {
            cardItem.cardView?.themeBackground = themeBackground
            cardItem.cardView?.isDark = isDark
            cardItem.cardView?.onDelete = { [weak self] id in
                ClipboardStore.shared.deleteEntry(id: id)
                self?.reloadEntries()
            }
            cardItem.cardView?.onZoom = { [weak self] entry in
                self?.showPreview(for: entry)
            }
            cardItem.cardView?.onActivate = { [weak self] entry in
                self?.activateEntry(entry, at: indexPath.item)
            }
            cardItem.cardView?.isCardSelected = (selectedIndex == indexPath.item)
            let shortcutIndex: Int? = indexPath.item < 9 ? indexPath.item : nil
            cardItem.cardView?.configure(with: filteredEntries[indexPath.item], searchQuery: currentSearchQuery, shortcutIndex: shortcutIndex)
        }
        return item
    }

    // MARK: - NSCollectionViewDelegateFlowLayout

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let availableWidth = collectionView.bounds.width - sectionInsets.left - sectionInsets.right

        let previewLines = SettingsStore.shared.clipboardPreviewLines
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(SettingsStore.shared.clipboardFontSize), weight: .regular)
        let lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        let dynamicHeight = CGFloat(previewLines) * lineHeight + 28

        if SettingsStore.shared.clipboardViewMode == "panels" {
            return NSSize(width: availableWidth, height: dynamicHeight)
        }

        let columns = max(1, floor((availableWidth + tileSpacing) / (tileMinWidth + tileSpacing)))
        let tileWidth = floor((availableWidth - tileSpacing * (columns - 1)) / columns)
        return NSSize(width: tileWidth, height: dynamicHeight)
    }

    // MARK: - NSSearchFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            guard !filteredEntries.isEmpty else { return false }
            selectItem(at: 0)
            window?.makeFirstResponder(collectionView)
            return true
        }
        return false
    }

    // MARK: - Keyboard navigation

    func collectionViewKeyDown(with event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: // up arrow
            return handleUpArrow()
        case 125: // down arrow
            return handleDownArrow()
        case 123: // left arrow
            return handleLeftArrow()
        case 124: // right arrow
            return handleRightArrow()
        case 36: // return/enter
            return handleReturn()
        case 49: // space
            return handleSpace()
        case 53: // escape
            return handleEscape()
        default:
            return false
        }
    }

    private func handleUpArrow() -> Bool {
        guard let index = selectedIndex else { return false }
        let columns = currentColumnCount()
        let newIndex = index - columns
        if newIndex < 0 {
            deselectAndFocusSearch()
        } else {
            selectItem(at: newIndex)
        }
        return true
    }

    private func handleDownArrow() -> Bool {
        guard let index = selectedIndex else { return false }
        let columns = currentColumnCount()
        let newIndex = index + columns
        if newIndex < filteredEntries.count {
            selectItem(at: newIndex)
        }
        return true
    }

    private func handleLeftArrow() -> Bool {
        guard let index = selectedIndex, index > 0 else { return false }
        if SettingsStore.shared.clipboardViewMode == "panels" { return true }
        selectItem(at: index - 1)
        return true
    }

    private func handleRightArrow() -> Bool {
        guard let index = selectedIndex else { return false }
        if SettingsStore.shared.clipboardViewMode == "panels" { return true }
        let newIndex = index + 1
        if newIndex < filteredEntries.count {
            selectItem(at: newIndex)
        }
        return true
    }

    private func handleReturn() -> Bool {
        guard let index = selectedIndex, index < filteredEntries.count else { return false }
        activateEntry(filteredEntries[index], at: index)
        return true
    }

    private func handleSpace() -> Bool {
        guard let index = selectedIndex, index < filteredEntries.count else { return false }
        if previewOverlay != nil {
            dismissPreview()
        } else {
            showPreview(for: filteredEntries[index])
        }
        return true
    }

    private func handleEscape() -> Bool {
        if previewOverlay != nil {
            dismissPreview()
            return true
        }
        if selectedIndex != nil {
            deselectAndFocusSearch()
            return true
        }
        return false
    }

    private func selectItem(at index: Int) {
        let previousIndex = selectedIndex
        selectedIndex = index

        if let prev = previousIndex, let item = collectionView.item(at: prev) as? ClipboardCardItem {
            item.cardView?.isCardSelected = false
        }
        if let item = collectionView.item(at: index) as? ClipboardCardItem {
            item.cardView?.isCardSelected = true
        }

        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectionIndexPaths = [indexPath]
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
    }

    private func deselectAndFocusSearch() {
        if let prev = selectedIndex, let item = collectionView.item(at: prev) as? ClipboardCardItem {
            item.cardView?.isCardSelected = false
        }
        selectedIndex = nil
        collectionView.selectionIndexPaths = []
        focusSearchField()
    }

    private func currentColumnCount() -> Int {
        if SettingsStore.shared.clipboardViewMode == "panels" { return 1 }
        let availableWidth = collectionView.bounds.width - sectionInsets.left - sectionInsets.right
        return max(1, Int(floor((availableWidth + tileSpacing) / (tileMinWidth + tileSpacing))))
    }

    // MARK: - Preview

    private func showPreview(for entry: ClipboardEntry) {
        dismissPreview()
        let overlay = ClipboardPreviewOverlay(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.configure(with: entry, themeBackground: themeBackground, isDark: isDark)
        overlay.onDismiss = { [weak self] in
            self?.dismissPreview()
        }
        overlay.onNavigate = { [weak self] keyCode in
            self?.handlePreviewNavigation(keyCode: keyCode)
        }
        addSubview(overlay)
        previewOverlay = overlay
        overlay.animateIn()
    }

    private func handlePreviewNavigation(keyCode: UInt16) {
        switch keyCode {
        case 49: // space — toggle preview
            dismissPreview()
        case 126: // up
            _ = handleUpArrow()
            updatePreviewContent()
        case 125: // down
            _ = handleDownArrow()
            updatePreviewContent()
        case 123: // left
            _ = handleLeftArrow()
            updatePreviewContent()
        case 124: // right
            _ = handleRightArrow()
            updatePreviewContent()
        default:
            break
        }
    }

    private func updatePreviewContent() {
        guard let overlay = previewOverlay,
              let index = selectedIndex, index < filteredEntries.count else { return }
        overlay.configure(with: filteredEntries[index], themeBackground: themeBackground, isDark: isDark)
    }

    private func dismissPreview() {
        guard let overlay = previewOverlay else { return }
        previewOverlay = nil
        overlay.animateOut {
            overlay.removeFromSuperview()
        }
    }

    // MARK: - Clipboard shortcuts (⌘1–9 / ⌥1–9)

    private var isClipboardTabVisible: Bool {
        guard let window, window.isKeyWindow else { return false }
        return !isHiddenOrHasHiddenAncestor && visibleRect.height > 0
    }

    private func handleShortcutKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let number = clipboardNumberFromKeyCode(event.keyCode) else { return false }
        let index = number - 1
        guard index < filteredEntries.count else { return false }

        if flags == .command {
            copyItem(at: index)
            return true
        } else if flags == .option {
            pasteItem(at: index)
            return true
        }
        return false
    }

    private func activateEntry(_ entry: ClipboardEntry, at index: Int) {
        if SettingsStore.shared.clipboardClickAction == "paste" {
            pasteItem(at: index)
        } else {
            copyItem(at: index)
        }
    }

    private func copyItem(at index: Int) {
        let entry = filteredEntries[index]
        ClipboardStore.shared.copyToClipboard(entry)
        if let item = collectionView.item(at: index) as? ClipboardCardItem {
            item.cardView?.flashCopied()
        }
    }

    private func pasteItem(at index: Int) {
        let entry = filteredEntries[index]
        ClipboardStore.shared.copyToClipboard(entry)
        if let item = collectionView.item(at: index) as? ClipboardCardItem {
            item.cardView?.flashCopied()
        }
        guard AccessibilityHelper.isTrusted() else {
            AccessibilityHelper.requestPermission()
            return
        }
        hideWindowAndPaste()
    }

    private func hideWindowAndPaste() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.toggleWindow()
        }
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AccessibilityHelper.simulatePaste()
        }
    }

    // MARK: - Theme

    private func applyTheme() {
        layer?.backgroundColor = themeBackground.cgColor
        searchField.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        reloadEntries()
    }
}
