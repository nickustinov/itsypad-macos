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

    private var clipboardContentView: ClipboardContentView!
    private var clipboardTabContainer: HoverView!
    private var tabBarSeparator: NSBox!
    private var isClipboardTabActive = false

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

        // Separator between document tabs and clipboard tab
        tabBarSeparator = NSBox()
        tabBarSeparator.boxType = .separator
        tabBarSeparator.translatesAutoresizingMaskIntoConstraints = false

        // Clipboard tab (pinned, right-aligned)
        clipboardTabContainer = HoverView()
        clipboardTabContainer.translatesAutoresizingMaskIntoConstraints = false
        clipboardTabContainer.wantsLayer = true
        clipboardTabContainer.layer?.cornerRadius = 4

        let clipboardIcon = NSImageView()
        clipboardIcon.translatesAutoresizingMaskIntoConstraints = false
        clipboardIcon.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
        clipboardIcon.contentTintColor = .secondaryLabelColor
        clipboardIcon.imageScaling = .scaleProportionallyUpOrDown

        let clipboardLabel = NSButton(title: "Clipboard", target: self, action: #selector(clipboardTabClicked))
        clipboardLabel.translatesAutoresizingMaskIntoConstraints = false
        clipboardLabel.bezelStyle = .accessoryBarAction
        clipboardLabel.isBordered = false
        clipboardLabel.font = NSFont.systemFont(ofSize: 11)
        clipboardLabel.contentTintColor = .secondaryLabelColor
        clipboardLabel.identifier = NSUserInterfaceItemIdentifier("clipboardTab")

        clipboardTabContainer.addSubview(clipboardIcon)
        clipboardTabContainer.addSubview(clipboardLabel)

        NSLayoutConstraint.activate([
            clipboardIcon.leadingAnchor.constraint(equalTo: clipboardTabContainer.leadingAnchor, constant: 6),
            clipboardIcon.centerYAnchor.constraint(equalTo: clipboardTabContainer.centerYAnchor),
            clipboardIcon.widthAnchor.constraint(equalToConstant: 14),
            clipboardIcon.heightAnchor.constraint(equalToConstant: 14),

            clipboardLabel.leadingAnchor.constraint(equalTo: clipboardIcon.trailingAnchor, constant: 2),
            clipboardLabel.centerYAnchor.constraint(equalTo: clipboardTabContainer.centerYAnchor),
            clipboardLabel.trailingAnchor.constraint(equalTo: clipboardTabContainer.trailingAnchor, constant: -6),

            clipboardTabContainer.heightAnchor.constraint(equalToConstant: 24),
        ])

        tabBarView.addSubview(tabBarScrollView)
        tabBarView.addSubview(tabBarSeparator)
        tabBarView.addSubview(clipboardTabContainer)

        NSLayoutConstraint.activate([
            // Clipboard tab (trailing)
            clipboardTabContainer.trailingAnchor.constraint(equalTo: tabBarView.trailingAnchor, constant: -6),
            clipboardTabContainer.centerYAnchor.constraint(equalTo: tabBarView.centerYAnchor),

            // Separator
            tabBarSeparator.trailingAnchor.constraint(equalTo: clipboardTabContainer.leadingAnchor, constant: -4),
            tabBarSeparator.topAnchor.constraint(equalTo: tabBarView.topAnchor, constant: 4),
            tabBarSeparator.bottomAnchor.constraint(equalTo: tabBarView.bottomAnchor, constant: -4),
            tabBarSeparator.widthAnchor.constraint(equalToConstant: 1),

            // Scroll view (leading → separator)
            tabBarScrollView.leadingAnchor.constraint(equalTo: tabBarView.leadingAnchor),
            tabBarScrollView.trailingAnchor.constraint(equalTo: tabBarSeparator.leadingAnchor, constant: -2),
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
        // Clipboard content view (same position as editor, toggled via isHidden)
        clipboardContentView = ClipboardContentView(frame: .zero)
        clipboardContentView.translatesAutoresizingMaskIntoConstraints = false
        clipboardContentView.isHidden = true

        view.addSubview(editorScrollView)
        view.addSubview(lineNumberGutter)
        view.addSubview(clipboardContentView)
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

            // Clipboard content view (same area as editor)
            clipboardContentView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            clipboardContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clipboardContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            clipboardContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

    private static let tabSeparatorID = NSUserInterfaceItemIdentifier("tabSeparator")

    private func refreshTabs() {
        // Remove old tab buttons
        for view in tabBarStackView.arrangedSubviews {
            tabBarStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (i, tab) in tabStore.tabs.enumerated() {
            if i > 0 {
                let sep = NSBox()
                sep.boxType = .custom
                sep.fillColor = .separatorColor
                sep.borderWidth = 0
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.identifier = Self.tabSeparatorID
                tabBarStackView.addArrangedSubview(sep)
                NSLayoutConstraint.activate([
                    sep.widthAnchor.constraint(equalToConstant: 1),
                    sep.heightAnchor.constraint(equalToConstant: 14),
                ])
            }
            let tabButton = makeTabButton(for: tab)
            tabBarStackView.addArrangedSubview(tabButton)
        }

        updateTabSeparatorVisibility()
        updateClipboardTabAppearance()
        refreshTabSwitcher()
    }

    private func refreshTabTitles() {
        let subviews = tabBarStackView.arrangedSubviews
        for (index, tab) in tabStore.tabs.enumerated() {
            guard index < subviews.count else { break }
            let container = subviews[index]
            guard let button = container.subviews.first(where: { $0 is NSButton && $0.identifier?.rawValue == tab.id.uuidString }) as? NSButton else { continue }
            let isSelected = tab.id == tabStore.selectedTabID && !isClipboardTabActive
            button.title = tab.name
            button.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
            if let dot = container.subviews.first(where: { $0.tag == Self.dirtyIndicatorTag }) {
                dot.isHidden = !tab.isDirty
            }
            if let hoverView = container as? HoverView {
                hoverView.isSelected = isSelected
            }
        }

        updateTabSeparatorVisibility()
        updateClipboardTabAppearance()
        refreshTabSwitcher()
    }

    private func updateTabSeparatorVisibility() {
        let arranged = tabBarStackView.arrangedSubviews
        let selectedID = tabStore.selectedTabID
        let tabs = tabStore.tabs

        for (i, view) in arranged.enumerated() where view.identifier == Self.tabSeparatorID {
            // Find the tab containers before and after this separator
            let before = i > 0 ? arranged[i - 1] : nil
            let after = i + 1 < arranged.count ? arranged[i + 1] : nil

            let beforeSelected = before?.subviews.contains(where: {
                $0.identifier?.rawValue == selectedID?.uuidString
            }) == true && !isClipboardTabActive

            let afterSelected = after?.subviews.contains(where: {
                $0.identifier?.rawValue == selectedID?.uuidString
            }) == true && !isClipboardTabActive

            view.isHidden = beforeSelected || afterSelected
        }
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
        highlightCoordinator.font = SettingsStore.shared.editorFont
        highlightCoordinator.applyWrapIndent(to: editorTextView, font: SettingsStore.shared.editorFont)
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
        highlightCoordinator.updateTheme()
        applyThemeColors()

        // Line numbers
        updateGutterVisibility()
    }

    private func applyThemeColors() {
        let theme = highlightCoordinator.theme
        let bg = theme.background
        let isDark = theme.isDark

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

        // Clipboard content view
        clipboardContentView.themeBackground = bg
        clipboardContentView.isDark = isDark
    }

    // MARK: - Actions

    @objc func newTab() {
        saveCursorPosition()
        if isClipboardTabActive { showEditor() }
        tabStore.addNewTab()
        refreshTabs()
        loadSelectedTab()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    @objc func selectNextTab() {
        saveCursorPosition()
        // Cycle: doc tabs → clipboard → back to first doc tab
        let count = tabStore.tabs.count
        if isClipboardTabActive {
            // Clipboard is last; wrap to first doc tab
            if count > 0 {
                showEditor()
                tabStore.selectedTabID = tabStore.tabs[0].id
                refreshTabs()
                loadSelectedTab()
                editorTextView.window?.makeFirstResponder(editorTextView)
            }
        } else if let idx = tabStore.selectedTabIndex {
            if idx + 1 < count {
                tabStore.selectedTabID = tabStore.tabs[idx + 1].id
                refreshTabs()
                loadSelectedTab()
                editorTextView.window?.makeFirstResponder(editorTextView)
            } else {
                // Past last doc tab → clipboard
                showClipboard()
            }
        }
    }

    @objc func selectPreviousTab() {
        saveCursorPosition()
        let count = tabStore.tabs.count
        if isClipboardTabActive {
            // Go to last doc tab
            if count > 0 {
                showEditor()
                tabStore.selectedTabID = tabStore.tabs[count - 1].id
                refreshTabs()
                loadSelectedTab()
                editorTextView.window?.makeFirstResponder(editorTextView)
            }
        } else if let idx = tabStore.selectedTabIndex {
            if idx > 0 {
                tabStore.selectedTabID = tabStore.tabs[idx - 1].id
                refreshTabs()
                loadSelectedTab()
                editorTextView.window?.makeFirstResponder(editorTextView)
            } else {
                // Before first doc tab → clipboard
                showClipboard()
            }
        }
    }

    @objc func openFile() {
        saveCursorPosition()
        if isClipboardTabActive { showEditor() }
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
        if isClipboardTabActive { showEditor() }
        tabStore.selectedTabID = id
        refreshTabs()
        loadSelectedTab()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString) else { return }
        saveCursorPosition()
        if isClipboardTabActive { showEditor() }
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

    @objc private func clipboardTabClicked() {
        if isClipboardTabActive { return }
        saveCursorPosition()
        showClipboard()
    }

    private func showClipboard() {
        isClipboardTabActive = true
        editorScrollView.isHidden = true
        lineNumberGutter.isHidden = true
        clipboardContentView.isHidden = false
        clipboardContentView.reloadEntries()
        refreshTabTitles()
    }

    private func showEditor() {
        isClipboardTabActive = false
        clipboardContentView.isHidden = true
        editorScrollView.isHidden = false
        lineNumberGutter.isHidden = !SettingsStore.shared.showLineNumbers
        refreshTabTitles()
    }

    private func updateClipboardTabAppearance() {
        clipboardTabContainer.isSelected = isClipboardTabActive
        if let icon = clipboardTabContainer.subviews.first(where: { $0 is NSImageView }) as? NSImageView {
            icon.contentTintColor = isClipboardTabActive ? .labelColor : .secondaryLabelColor
        }
        if let label = clipboardTabContainer.subviews.first(where: { $0.identifier?.rawValue == "clipboardTab" }) as? NSButton {
            label.contentTintColor = isClipboardTabActive ? .labelColor : .secondaryLabelColor
        }
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
