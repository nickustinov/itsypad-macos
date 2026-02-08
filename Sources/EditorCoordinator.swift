import Cocoa
import SwiftUI
import Bonsplit

struct EditorState {
    let textView: EditorTextView
    let scrollView: NSScrollView
    let gutterView: LineNumberGutterView
    let highlightCoordinator: SyntaxHighlightCoordinator
}

@Observable
final class EditorCoordinator: BonsplitDelegate, @unchecked Sendable {
    let controller: BonsplitController
    private let tabStore = TabStore.shared

    private var tabIDMap: [UUID: TabID] = [:]
    private var reverseMap: [TabID: UUID] = [:]
    private var editorStates: [TabID: EditorState] = [:]
    private(set) var clipboardTabID: TabID?
    private var isRemovingClipboardTab = false

    private var previousBonsplitTabID: TabID?
    private var settingsObserver: Any?

    @MainActor
    init() {
        var config = BonsplitConfiguration.default
        config.allowSplits = false
        config.allowTabReordering = true
        config.contentViewLifecycle = .keepAllAlive
        config.allowCloseLastPane = false
        config.newTabPosition = .end
        config.appearance.tabBarHeight = 28

        controller = BonsplitController(configuration: config)

        // Remove Bonsplit's default "Welcome" tab
        for tabId in controller.allTabIds {
            _ = controller.closeTab(tabId)
        }

        controller.delegate = self

        applyBonsplitTheme()
        restoreSession()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySettings()
            }
        }
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Session restore

    @MainActor
    private func restoreSession() {
        // Restore document tabs from TabStore
        for tab in tabStore.tabs {
            if let bonsplitTabID = controller.createTab(
                title: tab.name,
                icon: nil,
                isDirty: tab.isDirty
            ) {
                tabIDMap[tab.id] = bonsplitTabID
                reverseMap[bonsplitTabID] = tab.id
                editorStates[bonsplitTabID] = createEditorState(for: tab)
            }
        }

        // Create clipboard tab last — pinned to the right (if enabled)
        if SettingsStore.shared.clipboardEnabled {
            if let clipTabID = controller.createTab(title: "Clipboard", icon: "doc.on.clipboard", isClosable: false, isPinned: true) {
                clipboardTabID = clipTabID
            }
        }

        // Select the previously selected tab, or first document tab
        if let selectedID = tabStore.selectedTabID,
           let bonsplitID = tabIDMap[selectedID] {
            controller.selectTab(bonsplitID)
            previousBonsplitTabID = bonsplitID
        } else if let firstTab = tabStore.tabs.first,
                  let bonsplitID = tabIDMap[firstTab.id] {
            controller.selectTab(bonsplitID)
            previousBonsplitTabID = bonsplitID
        }
    }

    // MARK: - Editor state factory

    @MainActor
    private func createEditorState(for tab: TabData) -> EditorState {
        let settings = SettingsStore.shared
        let scrollView = createScrollView()
        let textView = createTextView(settings: settings)

        // Word wrap initial state (no-wrap needs explicit setup)
        if !settings.wordWrap {
            textView.isHorizontallyResizable = true
            scrollView.hasHorizontalScroller = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView

        let gutter = createGutter()
        let highlighter = createHighlighter(for: textView, settings: settings)
        setupEditorContent(textView: textView, highlighter: highlighter, tab: tab)
        wireUpTextChanges(textView: textView, tabID: tab.id)

        applyThemeToEditor(textView: textView, gutter: gutter, theme: highlighter.theme)
        highlighter.applyWrapIndent(to: textView, font: settings.editorFont)
        highlighter.scheduleHighlightIfNeeded()

        return EditorState(
            textView: textView,
            scrollView: scrollView,
            gutterView: gutter,
            highlightCoordinator: highlighter
        )
    }

    @MainActor
    private func createScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        return scrollView
    }

    @MainActor
    private func createTextView(settings: SettingsStore) -> EditorTextView {
        let textView = EditorTextView(frame: .zero)
        textView.isEditable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = settings.editorFont
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: settings.showLineNumbers ? 4 : 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor

        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        return textView
    }

    private func createGutter() -> LineNumberGutterView {
        let gutter = LineNumberGutterView()
        gutter.translatesAutoresizingMaskIntoConstraints = false
        gutter.wantsLayer = true
        gutter.layer?.masksToBounds = true
        return gutter
    }

    @MainActor
    private func createHighlighter(for textView: EditorTextView, settings: SettingsStore) -> SyntaxHighlightCoordinator {
        let highlighter = SyntaxHighlightCoordinator()
        highlighter.textView = textView
        highlighter.font = settings.editorFont
        textView.delegate = highlighter
        return highlighter
    }

    @MainActor
    private func setupEditorContent(textView: EditorTextView, highlighter: SyntaxHighlightCoordinator, tab: TabData) {
        textView.string = tab.content
        highlighter.language = tab.language

        let pos = min(tab.cursorPosition, (textView.string as NSString).length)
        textView.setSelectedRange(NSRange(location: pos, length: 0))
        textView.scrollRangeToVisible(NSRange(location: pos, length: 0))
    }

    @MainActor
    private func wireUpTextChanges(textView: EditorTextView, tabID: UUID) {
        textView.onTextChange = { [weak self] text in
            guard let self else { return }
            self.tabStore.updateContent(id: tabID, content: text)
            if let bonsplitID = self.tabIDMap[tabID],
               let updatedTab = self.tabStore.tabs.first(where: { $0.id == tabID }) {
                self.controller.updateTab(bonsplitID, title: updatedTab.name, isDirty: updatedTab.isDirty)
                self.highlighterForTab(bonsplitID)?.language = updatedTab.language
            }
        }
    }

    // MARK: - Lookup helpers

    func editorState(for bonsplitTabID: TabID) -> EditorState? {
        editorStates[bonsplitTabID]
    }

    private func highlighterForTab(_ bonsplitID: TabID) -> SyntaxHighlightCoordinator? {
        editorStates[bonsplitID]?.highlightCoordinator
    }

    @MainActor
    func activeTextView() -> EditorTextView? {
        guard let focusedPaneId = controller.focusedPaneId,
              let selectedTab = controller.selectedTab(inPane: focusedPaneId),
              selectedTab.id != clipboardTabID,
              let state = editorStates[selectedTab.id] else { return nil }
        return state.textView
    }

    // MARK: - Public actions (menu/toolbar)

    @MainActor
    func newTab() {
        saveCursorForSelectedTab()
        tabStore.addNewTab()
        guard let newTab = tabStore.tabs.last else { return }
        if let bonsplitTabID = controller.createTab(
            title: newTab.name,
            icon: nil,
            isDirty: newTab.isDirty
        ) {
            tabIDMap[newTab.id] = bonsplitTabID
            reverseMap[bonsplitTabID] = newTab.id
            editorStates[bonsplitTabID] = createEditorState(for: newTab)
            controller.selectTab(bonsplitTabID)
        }
    }

    @MainActor
    func openFile() {
        saveCursorForSelectedTab()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            openFile(url: url)
        }
    }

    @MainActor
    func openFile(url: URL) {
        // Check if already open
        if let existing = tabStore.tabs.first(where: { $0.fileURL == url }) {
            if let bonsplitID = tabIDMap[existing.id] {
                controller.selectTab(bonsplitID)
            }
            return
        }

        tabStore.openFile(url: url)
        guard let newTab = tabStore.tabs.last else { return }
        if let bonsplitTabID = controller.createTab(
            title: newTab.name,
            icon: nil,
            isDirty: newTab.isDirty
        ) {
            tabIDMap[newTab.id] = bonsplitTabID
            reverseMap[bonsplitTabID] = newTab.id
            editorStates[bonsplitTabID] = createEditorState(for: newTab)
            controller.selectTab(bonsplitTabID)
        }
    }

    @MainActor
    func saveFile() {
        guard let selectedTabStoreID = selectedTabStoreID() else { return }
        tabStore.saveFile(id: selectedTabStoreID)
        if let bonsplitID = tabIDMap[selectedTabStoreID],
           let tab = tabStore.tabs.first(where: { $0.id == selectedTabStoreID }) {
            controller.updateTab(bonsplitID, title: tab.name, isDirty: tab.isDirty)
        }
    }

    @MainActor
    func saveFileAs() {
        guard let selectedTabStoreID = selectedTabStoreID() else { return }
        tabStore.saveFileAs(id: selectedTabStoreID)
        if let bonsplitID = tabIDMap[selectedTabStoreID],
           let tab = tabStore.tabs.first(where: { $0.id == selectedTabStoreID }) {
            controller.updateTab(bonsplitID, title: tab.name, isDirty: tab.isDirty)
        }
    }

    @MainActor
    func closeCurrentTab() {
        guard let focusedPaneId = controller.focusedPaneId,
              let selectedTab = controller.selectedTab(inPane: focusedPaneId) else { return }

        // Don't close clipboard tab
        if selectedTab.id == clipboardTabID { return }

        guard let tabStoreID = reverseMap[selectedTab.id],
              let tab = tabStore.tabs.first(where: { $0.id == tabStoreID }) else { return }

        if !confirmCloseTab(tab) { return }

        saveCursorForSelectedTab()
        _ = controller.closeTab(selectedTab.id)
    }

    @MainActor
    func selectNextTab() {
        controller.selectNextTab()
    }

    @MainActor
    func selectPreviousTab() {
        controller.selectPreviousTab()
    }

    @MainActor
    func selectClipboardTab() {
        guard let clipID = clipboardTabID else { return }
        controller.selectTab(clipID)
    }

    // MARK: - BonsplitDelegate

    func splitTabBar(
        _ controller: BonsplitController,
        shouldCloseTab tab: Bonsplit.Tab,
        inPane pane: PaneID
    ) -> Bool {
        // Never close clipboard tab (unless programmatically removing it)
        if tab.id == clipboardTabID { return isRemovingClipboardTab }

        guard let tabStoreID = reverseMap[tab.id],
              let tabData = tabStore.tabs.first(where: { $0.id == tabStoreID }) else {
            return true
        }
        return confirmCloseTab(tabData)
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didSelectTab tab: Bonsplit.Tab,
        inPane pane: PaneID
    ) {
        MainActor.assumeIsolated {
            // Save cursor for previously selected tab and resign its first responder
            if let prevID = previousBonsplitTabID,
               let prevState = editorStates[prevID] {
                if let tabStoreID = reverseMap[prevID] {
                    tabStore.updateCursorPosition(id: tabStoreID, position: prevState.textView.selectedRange().location)
                }
                prevState.textView.window?.makeFirstResponder(nil)
            }

            previousBonsplitTabID = tab.id

            // Update TabStore selection
            if let tabStoreID = reverseMap[tab.id] {
                tabStore.selectedTabID = tabStoreID
            }

            // First responder is handled by EditorContentView.updateNSView
            // when isSelected changes, ensuring correct SwiftUI timing
        }
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didCloseTab tabId: TabID,
        fromPane pane: PaneID
    ) {
        guard let tabStoreID = reverseMap[tabId] else { return }
        editorStates.removeValue(forKey: tabId)
        tabIDMap.removeValue(forKey: tabStoreID)
        reverseMap.removeValue(forKey: tabId)
        tabStore.closeTab(id: tabStoreID)
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didMoveTab tab: Bonsplit.Tab,
        fromPane source: PaneID,
        toPane destination: PaneID
    ) {
        // Bonsplit handles the visual reorder; just persist if needed
        tabStore.scheduleSave()
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didDoubleClickTabBarInPane pane: PaneID
    ) {
        MainActor.assumeIsolated {
            newTab()
        }
    }

    func splitTabBar(
        _ controller: BonsplitController,
        contextMenuItemsForTab tab: Bonsplit.Tab,
        inPane pane: PaneID
    ) -> [TabContextMenuItem] {
        guard let tabStoreID = reverseMap[tab.id],
              let tabData = tabStore.tabs.first(where: { $0.id == tabStoreID }) else { return [] }

        var items: [TabContextMenuItem] = []

        items.append(TabContextMenuItem(title: "Save as...", icon: "square.and.arrow.down") {
            MainActor.assumeIsolated {
                self.tabStore.saveFileAs(id: tabStoreID)
                if let bonsplitID = self.tabIDMap[tabStoreID],
                   let updated = self.tabStore.tabs.first(where: { $0.id == tabStoreID }) {
                    self.controller.updateTab(bonsplitID, title: updated.name, isDirty: updated.isDirty)
                }
            }
        })

        let hasFile = tabData.fileURL != nil

        items.append(TabContextMenuItem(title: "Copy path", icon: "doc.on.doc", isEnabled: hasFile) {
            if let url = tabData.fileURL {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.path, forType: .string)
            }
        })

        items.append(TabContextMenuItem(title: "Reveal in Finder", icon: "folder", isEnabled: hasFile) {
            if let url = tabData.fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        })

        return items
    }

    // MARK: - Private helpers

    @MainActor
    private func selectedTabStoreID() -> UUID? {
        guard let focusedPaneId = controller.focusedPaneId,
              let selectedTab = controller.selectedTab(inPane: focusedPaneId),
              let tabStoreID = reverseMap[selectedTab.id] else { return nil }
        return tabStoreID
    }

    @MainActor
    private func saveCursorForSelectedTab() {
        guard let focusedPaneId = controller.focusedPaneId,
              let selectedTab = controller.selectedTab(inPane: focusedPaneId),
              let tabStoreID = reverseMap[selectedTab.id],
              let state = editorStates[selectedTab.id] else { return }
        tabStore.updateCursorPosition(id: tabStoreID, position: state.textView.selectedRange().location)
    }

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

    // MARK: - Settings

    @MainActor
    private func applySettings() {
        let settings = SettingsStore.shared
        let font = settings.editorFont
        let showGutter = settings.showLineNumbers

        applyBonsplitTheme()
        applyClipboardEnabled(settings.clipboardEnabled)

        for (_, state) in editorStates {
            state.textView.font = font
            state.textView.wrapsLines = settings.wordWrap
            applyGutterVisibility(state: state, showGutter: showGutter)
            state.textView.textContainerInset = NSSize(width: showGutter ? 4 : 12, height: 12)
            state.highlightCoordinator.font = font
            state.highlightCoordinator.updateTheme()

            let theme = state.highlightCoordinator.theme
            applyThemeToEditor(textView: state.textView, gutter: state.gutterView, theme: theme)
        }
    }

    @MainActor
    private func applyClipboardEnabled(_ enabled: Bool) {
        if enabled {
            ClipboardStore.shared.startMonitoring()
            if clipboardTabID == nil {
                if let clipTabID = controller.createTab(title: "Clipboard", icon: "doc.on.clipboard", isClosable: false, isPinned: true) {
                    clipboardTabID = clipTabID
                }
            }
        } else {
            ClipboardStore.shared.stopMonitoring()
            if let clipTabID = clipboardTabID {
                isRemovingClipboardTab = true
                _ = controller.closeTab(clipTabID)
                isRemovingClipboardTab = false
                clipboardTabID = nil
            }
        }
    }

    private func applyBonsplitTheme() {
        let theme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
        let blendTarget: NSColor = theme.isDark ? .white : .black

        // Active tab = editor background
        BonsplitTheme.shared.activeTabBackground = theme.background

        // Tab bar background = slightly lighter/darker than editor
        BonsplitTheme.shared.barBackground = theme.background.blended(withFraction: 0.06, of: blendTarget) ?? theme.background

        // Separator blends into the bar
        BonsplitTheme.shared.separator = theme.background.blended(withFraction: 0.12, of: blendTarget) ?? theme.background
    }

    private func applyGutterVisibility(state: EditorState, showGutter: Bool) {
        let lineCount = state.textView.string.components(separatedBy: "\n").count
        state.gutterView.updateVisibility(showGutter, lineCount: lineCount)
    }

    private func applyThemeToEditor(textView: EditorTextView, gutter: LineNumberGutterView, theme: EditorTheme) {
        let settings = SettingsStore.shared

        textView.backgroundColor = theme.background
        textView.drawsBackground = true
        textView.insertionPointColor = theme.isDark ? .white : .black

        gutter.bgColor = theme.background
        gutter.lineColor = theme.isDark
            ? NSColor.white.withAlphaComponent(0.3)
            : NSColor.black.withAlphaComponent(0.3)
        gutter.lineFont = NSFont.monospacedSystemFont(
            ofSize: settings.editorFont.pointSize * 0.85,
            weight: .regular
        )
        gutter.needsDisplay = true
    }
}
