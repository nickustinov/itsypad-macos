import Cocoa
import SwiftUI

// MARK: - Toolbar identifiers

private extension NSToolbarItem.Identifier {
    static let newTab = NSToolbarItem.Identifier("newTab")
    static let openFile = NSToolbarItem.Identifier("openFile")
    static let saveFile = NSToolbarItem.Identifier("saveFile")
    static let tabSwitcher = NSToolbarItem.Identifier("tabSwitcher")
}

// MARK: - Hover-aware tab container

private class HoverView: NSView {
    var isSelected = false { didSet { updateBackground() } }
    private var isHovered = false { didSet { updateBackground() } }
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    private func updateBackground() {
        let alpha: CGFloat
        if isSelected { alpha = 0.15 }
        else if isHovered { alpha = 0.08 }
        else { alpha = 0 }
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
    }
}

// MARK: - Editor view controller

class EditorViewController: NSViewController, NSToolbarDelegate {
    private let tabStore = TabStore.shared
    private let highlightCoordinator = SyntaxHighlightCoordinator()

    private var tabBarView: NSView!
    private var tabBarScrollView: NSScrollView!
    private var tabBarStackView: NSStackView!
    private var editorScrollView: NSScrollView!
    private var editorTextView: EditorTextView!
    private var tabSwitcherPopUp: NSPopUpButton?
    private var lineNumberGutter: LineNumberGutterView!
    private var gutterWidthConstraint: NSLayoutConstraint!

    private var tabStoreObserver: Any?
    private var settingsObserver: Any?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 600))
        self.view = container

        setupTabBar()
        setupEditor()
        layoutViews()
        refreshTabs()
        loadSelectedTab()

        // Observe TabStore changes
        tabStoreObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TabStoreDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshTabs()
            self?.loadSelectedTab()
        }

        // Observe settings changes
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyThemeColors()
    }

    deinit {
        if let observer = tabStoreObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newTab, .openFile, .saveFile, .flexibleSpace, .tabSwitcher]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newTab, .openFile, .saveFile, .tabSwitcher, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .newTab:
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")
            item.label = "New tab"
            item.toolTip = "New tab"
            item.target = self
            item.action = #selector(newTab)
        case .openFile:
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open")
            item.label = "Open"
            item.toolTip = "Open file"
            item.target = self
            item.action = #selector(openFile)
        case .saveFile:
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            item.label = "Save"
            item.toolTip = "Save file"
            item.target = self
            item.action = #selector(saveFile)
        case .tabSwitcher:
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 24), pullsDown: false)
            popUp.controlSize = .small
            popUp.font = NSFont.systemFont(ofSize: 12)
            popUp.target = self
            popUp.action = #selector(tabSwitcherChanged)
            tabSwitcherPopUp = popUp
            refreshTabSwitcher()
            item.view = popUp
            item.label = "Tabs"
        default:
            return nil
        }

        return item
    }

    // MARK: - Setup

    private func setupTabBar() {
        tabBarView = NSView()
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        tabBarView.wantsLayer = true
        tabBarView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor

        tabBarScrollView = NSScrollView()
        tabBarScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabBarScrollView.drawsBackground = false
        tabBarScrollView.hasHorizontalScroller = false
        tabBarScrollView.hasVerticalScroller = false
        tabBarScrollView.horizontalScrollElasticity = .allowed

        tabBarStackView = NSStackView()
        tabBarStackView.orientation = .horizontal
        tabBarStackView.spacing = 2
        tabBarStackView.translatesAutoresizingMaskIntoConstraints = false
        tabBarStackView.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

        let clipView = NSClipView()
        clipView.documentView = tabBarStackView
        clipView.drawsBackground = false
        tabBarScrollView.contentView = clipView

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(tabBarDoubleClicked(_:)))
        doubleClick.numberOfClicksRequired = 2
        tabBarView.addGestureRecognizer(doubleClick)

        tabBarView.addSubview(tabBarScrollView)
        NSLayoutConstraint.activate([
            tabBarScrollView.leadingAnchor.constraint(equalTo: tabBarView.leadingAnchor),
            tabBarScrollView.trailingAnchor.constraint(equalTo: tabBarView.trailingAnchor),
            tabBarScrollView.topAnchor.constraint(equalTo: tabBarView.topAnchor),
            tabBarScrollView.bottomAnchor.constraint(equalTo: tabBarView.bottomAnchor),
        ])
    }

    private func setupEditor() {
        editorScrollView = NSScrollView()
        editorScrollView.translatesAutoresizingMaskIntoConstraints = false
        editorScrollView.drawsBackground = false
        editorScrollView.autohidesScrollers = true
        editorScrollView.hasVerticalScroller = true
        editorScrollView.contentView.postsBoundsChangedNotifications = true

        editorTextView = EditorTextView(frame: .zero)
        editorTextView.isEditable = true
        editorTextView.isRichText = false
        editorTextView.usesFindBar = true
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.font = SettingsStore.shared.editorFont
        editorTextView.drawsBackground = true
        editorTextView.textContainerInset = NSSize(width: 12, height: 12)
        editorTextView.minSize = NSSize(width: 0, height: 0)
        editorTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editorTextView.isSelectable = true
        editorTextView.allowsUndo = true
        editorTextView.textColor = .labelColor
        editorTextView.insertionPointColor = .controlAccentColor

        editorTextView.isAutomaticTextCompletionEnabled = false
        editorTextView.isAutomaticQuoteSubstitutionEnabled = false
        editorTextView.isAutomaticDashSubstitutionEnabled = false
        editorTextView.isAutomaticDataDetectionEnabled = false
        editorTextView.isAutomaticLinkDetectionEnabled = false
        editorTextView.isGrammarCheckingEnabled = false
        editorTextView.isContinuousSpellCheckingEnabled = false
        editorTextView.smartInsertDeleteEnabled = false

        editorTextView.textContainer?.widthTracksTextView = true
        editorTextView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        editorScrollView.documentView = editorTextView

        // Line number gutter
        lineNumberGutter = LineNumberGutterView()
        lineNumberGutter.translatesAutoresizingMaskIntoConstraints = false
        lineNumberGutter.wantsLayer = true
        lineNumberGutter.layer?.masksToBounds = true
        lineNumberGutter.attach(to: editorScrollView, textView: editorTextView)

        // Syntax highlighting coordinator
        highlightCoordinator.textView = editorTextView
        editorTextView.delegate = highlightCoordinator

        editorTextView.onTextChange = { [weak self] text in
            guard let self, let id = self.tabStore.selectedTabID else { return }
            self.tabStore.updateContent(id: id, content: text)
            if let tab = self.tabStore.selectedTab {
                self.highlightCoordinator.language = tab.language
            }
            self.refreshTabTitles()
        }
    }

    private func layoutViews() {
        view.addSubview(editorScrollView)
        view.addSubview(lineNumberGutter)
        view.addSubview(tabBarView) // On top

        let tabBarHeight: CGFloat = 28
        let showGutter = SettingsStore.shared.showLineNumbers
        gutterWidthConstraint = lineNumberGutter.widthAnchor.constraint(equalToConstant: showGutter ? gutterWidth() : 0)

        NSLayoutConstraint.activate([
            // Tab bar
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: tabBarHeight),

            // Gutter
            lineNumberGutter.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            lineNumberGutter.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lineNumberGutter.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gutterWidthConstraint,

            // Editor
            editorScrollView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            editorScrollView.leadingAnchor.constraint(equalTo: lineNumberGutter.trailingAnchor),
            editorScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        lineNumberGutter.isHidden = !showGutter
    }

    private func gutterWidth() -> CGFloat {
        let lineCount = editorTextView.string.components(separatedBy: "\n").count
        let digits = max(3, "\(lineCount)".count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: lineNumberGutter.lineFont]).width
        return CGFloat(digits) * digitWidth + 16
    }

    private func updateGutterVisibility() {
        let show = SettingsStore.shared.showLineNumbers
        lineNumberGutter.isHidden = !show
        gutterWidthConstraint.constant = show ? gutterWidth() : 0
        editorTextView.textContainerInset = NSSize(width: show ? 4 : 12, height: 12)
    }

    // MARK: - Tab management

    private func refreshTabs() {
        // Remove old tab buttons
        for view in tabBarStackView.arrangedSubviews {
            tabBarStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for tab in tabStore.tabs {
            let tabButton = makeTabButton(for: tab)
            tabBarStackView.addArrangedSubview(tabButton)
        }

        refreshTabSwitcher()
    }

    private func refreshTabTitles() {
        let subviews = tabBarStackView.arrangedSubviews
        for (index, tab) in tabStore.tabs.enumerated() {
            guard index < subviews.count else { break }
            let container = subviews[index]
            guard let button = container.subviews.first(where: { $0 is NSButton && $0.identifier?.rawValue == tab.id.uuidString }) as? NSButton else { continue }
            let isSelected = tab.id == tabStore.selectedTabID
            button.title = tab.name
            button.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
            if let dot = container.subviews.first(where: { $0.tag == Self.dirtyIndicatorTag }) {
                dot.isHidden = !tab.isDirty
            }
            if let hoverView = container as? HoverView {
                hoverView.isSelected = isSelected
            }
        }

        refreshTabSwitcher()
    }

    private static let dirtyIndicatorTag = 9999

    private func makeTabButton(for tab: TabData) -> NSView {
        let isSelected = tab.id == tabStore.selectedTabID
        let container = HoverView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.isSelected = isSelected

        let button = NSButton(title: tab.name, target: self, action: #selector(tabClicked(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 11)
        button.tag = tab.id.hashValue
        button.identifier = NSUserInterfaceItemIdentifier(tab.id.uuidString)
        button.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor

        let dirtyDot = NSTextField(labelWithString: "●")
        dirtyDot.translatesAutoresizingMaskIntoConstraints = false
        dirtyDot.font = NSFont.systemFont(ofSize: 6)
        dirtyDot.textColor = .tertiaryLabelColor
        dirtyDot.tag = Self.dirtyIndicatorTag
        dirtyDot.isHidden = !tab.isDirty

        let closeButton = NSButton(title: "×", target: self, action: #selector(closeTabClicked(_:)))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        closeButton.identifier = NSUserInterfaceItemIdentifier(tab.id.uuidString)
        closeButton.contentTintColor = .secondaryLabelColor

        container.addSubview(button)
        container.addSubview(dirtyDot)
        container.addSubview(closeButton)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            dirtyDot.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 2),
            dirtyDot.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: dirtyDot.trailingAnchor, constant: 2),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),

            container.heightAnchor.constraint(equalToConstant: 24),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])

        return container
    }

    private func loadSelectedTab() {
        guard let tab = tabStore.selectedTab else { return }

        if editorTextView.string != tab.content {
            editorTextView.string = tab.content
        }

        highlightCoordinator.language = tab.language
        highlightCoordinator.setTheme(to: SettingsStore.shared.highlightTheme)
        highlightCoordinator.font = SettingsStore.shared.editorFont
        highlightCoordinator.scheduleHighlightIfNeeded()
        applyThemeColors()

        // Restore cursor position
        let pos = min(tab.cursorPosition, (editorTextView.string as NSString).length)
        editorTextView.setSelectedRange(NSRange(location: pos, length: 0))

        // Update tab bar highlight
        refreshTabTitles()
    }

    private func refreshTabSwitcher() {
        guard let popUp = tabSwitcherPopUp else { return }
        popUp.removeAllItems()
        for tab in tabStore.tabs {
            let title = tab.isDirty ? "● \(tab.name)" : tab.name
            popUp.addItem(withTitle: title)
            popUp.lastItem?.representedObject = tab.id
        }
        if let selectedID = tabStore.selectedTabID,
           let index = tabStore.tabs.firstIndex(where: { $0.id == selectedID }) {
            popUp.selectItem(at: index)
        }
    }

    private func applySettings() {
        let settings = SettingsStore.shared

        // Font
        editorTextView.font = settings.editorFont
        highlightCoordinator.font = settings.editorFont

        // Theme
        highlightCoordinator.setTheme(to: settings.highlightTheme)
        highlightCoordinator.rehighlight()
        applyThemeColors()

        // Line numbers
        updateGutterVisibility()
    }

    private func applyThemeColors() {
        guard let bg = highlightCoordinator.themeBackgroundColor else { return }

        // Compute luminance first — used for all theme-dependent styling
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        (bg.usingColorSpace(.sRGB) ?? bg).getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        let isDark = luminance < 0.5

        // Editor background
        editorTextView.backgroundColor = bg
        editorTextView.drawsBackground = true
        editorScrollView.drawsBackground = false

        // Tab bar — slightly lighter/darker than editor background
        let blendTarget: NSColor = isDark ? .white : .black
        let adjusted = bg.blended(withFraction: 0.06, of: blendTarget) ?? bg
        tabBarView.layer?.backgroundColor = adjusted.cgColor

        // Window appearance
        view.window?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // Caret color — contrast with background
        editorTextView.insertionPointColor = isDark ? .white : .black

        // Line number gutter
        lineNumberGutter.bgColor = bg
        lineNumberGutter.lineColor = isDark ? NSColor.white.withAlphaComponent(0.3) : NSColor.black.withAlphaComponent(0.3)
        lineNumberGutter.lineFont = NSFont.monospacedSystemFont(ofSize: SettingsStore.shared.editorFont.pointSize * 0.85, weight: .regular)
        lineNumberGutter.needsDisplay = true
    }

    // MARK: - Actions

    @objc func newTab() {
        saveCursorPosition()
        tabStore.addNewTab()
        refreshTabs()
        loadSelectedTab()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    @objc func selectNextTab() {
        guard tabStore.tabs.count > 1, let idx = tabStore.selectedTabIndex else { return }
        saveCursorPosition()
        let next = (idx + 1) % tabStore.tabs.count
        tabStore.selectedTabID = tabStore.tabs[next].id
        refreshTabs()
        loadSelectedTab()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    @objc func selectPreviousTab() {
        guard tabStore.tabs.count > 1, let idx = tabStore.selectedTabIndex else { return }
        saveCursorPosition()
        let prev = (idx - 1 + tabStore.tabs.count) % tabStore.tabs.count
        tabStore.selectedTabID = tabStore.tabs[prev].id
        refreshTabs()
        loadSelectedTab()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    @objc func openFile() {
        saveCursorPosition()
        tabStore.openFile()
        refreshTabs()
        loadSelectedTab()
    }

    @objc func saveFile() {
        guard let id = tabStore.selectedTabID else { return }
        tabStore.saveFile(id: id)
        refreshTabTitles()
    }

    @objc func saveFileAs() {
        guard let id = tabStore.selectedTabID else { return }
        tabStore.saveFileAs(id: id)
        refreshTabTitles()
    }

    @objc func closeCurrentTab() {
        guard let id = tabStore.selectedTabID,
              let tab = tabStore.selectedTab else { return }
        if !confirmCloseTab(tab) { return }
        saveCursorPosition()
        tabStore.closeTab(id: id)
        refreshTabs()
        loadSelectedTab()
    }

    @objc private func tabSwitcherChanged() {
        guard let id = tabSwitcherPopUp?.selectedItem?.representedObject as? UUID else { return }
        saveCursorPosition()
        tabStore.selectedTabID = id
        refreshTabs()
        loadSelectedTab()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString) else { return }
        saveCursorPosition()
        tabStore.selectedTabID = id
        refreshTabs()
        loadSelectedTab()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    @objc private func closeTabClicked(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString),
              let tab = tabStore.tabs.first(where: { $0.id == id }) else { return }
        if !confirmCloseTab(tab) { return }
        saveCursorPosition()
        tabStore.closeTab(id: id)
        refreshTabs()
        loadSelectedTab()
    }

    @objc private func tabBarDoubleClicked(_ gesture: NSClickGestureRecognizer) {
        let location = gesture.location(in: tabBarStackView)
        for subview in tabBarStackView.arrangedSubviews {
            if subview.frame.contains(location) { return }
        }
        newTab()
    }

    /// Returns true if safe to close, false if cancelled.
    func confirmCloseTab(_ tab: TabData) -> Bool {
        guard tab.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to \"\(tab.name)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            tabStore.saveFile(id: tab.id)
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func saveCursorPosition() {
        guard let id = tabStore.selectedTabID else { return }
        tabStore.updateCursorPosition(id: id, position: editorTextView.selectedRange().location)
    }
}
