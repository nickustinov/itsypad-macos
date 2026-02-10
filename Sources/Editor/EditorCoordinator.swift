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
    private let fileWatcher = FileWatcher()

    private var tabIDMap: [UUID: TabID] = [:]
    private var reverseMap: [TabID: UUID] = [:]
    private var editorStates: [TabID: EditorState] = [:]
    private(set) var clipboardTabID: TabID?
    private var isRemovingClipboardTab = false
    private var isClosingConfirmedTab = false

    private var previousBonsplitTabID: TabID?
    private var isRestoringLayout = false
    private var settingsObserver: Any?
    private var fileDropObserver: Any?
    private var cloudMergeObserver: Any?
    private var windowActivateObserver: Any?
    private var editorFocusObserver: Any?

    @MainActor
    init() {
        var config = BonsplitConfiguration.default
        config.allowSplits = true
        config.allowTabReordering = false
        config.allowCrossPaneTabMove = false
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

        fileDropObserver = NotificationCenter.default.addObserver(
            forName: EditorTextView.fileDropNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let urls = notification.userInfo?["urls"] as? [URL] else { return }
                for url in urls {
                    self?.openFile(url: url)
                }
            }
        }

        cloudMergeObserver = NotificationCenter.default.addObserver(
            forName: TabStore.cloudTabsMerged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let result = notification.userInfo?["result"] as? TabStore.CloudMergeResult else { return }
                self?.handleCloudMerge(result)
            }
        }

        windowActivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tabStore.checkICloud()
            }
        }

        editorFocusObserver = NotificationCenter.default.addObserver(
            forName: EditorTextView.didReceiveClickNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let textView = notification.object as? EditorTextView else { return }
                self?.handleEditorFocused(textView)
            }
        }
    }

    deinit {
        fileWatcher.stopAll()
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = fileDropObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = cloudMergeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = windowActivateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = editorFocusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Session restore

    @MainActor
    private func restoreSession() {
        let savedSelectedID = tabStore.selectedTabID

        isRestoringLayout = tabStore.savedLayout != nil
        let restorer = SessionRestorer(
            controller: controller,
            tabStore: tabStore,
            createEditorState: { [self] tab in self.createEditorState(for: tab) }
        )
        let result = restorer.restore()
        isRestoringLayout = false

        tabIDMap = result.tabIDMap
        reverseMap = result.reverseMap
        editorStates = result.editorStates

        // Create clipboard tab in the pane it was saved in (or last pane as fallback)
        if SettingsStore.shared.clipboardEnabled {
            let clipboardPane = findClipboardPane(in: tabStore.savedLayout) ?? controller.allPaneIds.last
            if let clipTabID = controller.createTab(title: "Clipboard", icon: "clipboardIcon", isClosable: false, inPane: clipboardPane) {
                clipboardTabID = clipTabID
            }
        }

        // Restore the original selection
        tabStore.selectedTabID = savedSelectedID
        if let selectedID = savedSelectedID,
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

        applyThemeToEditor(textView: textView, gutter: gutter, coordinator: highlighter)
        highlighter.applyWrapIndent(to: textView, font: settings.editorFont)
        highlighter.scheduleHighlightIfNeeded()

        if let fileURL = tab.fileURL {
            startWatching(url: fileURL, tabID: tab.id)
        }

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

    // MARK: - Clipboard pane restore

    @MainActor
    private func findClipboardPane(in layout: LayoutNode?) -> PaneID? {
        guard let layout else { return nil }
        let paneIndex = clipboardPaneIndex(in: layout, currentIndex: 0)?.index
        guard let idx = paneIndex else { return nil }
        let panes = controller.allPaneIds
        return idx < panes.count ? panes[idx] : nil
    }

    private func clipboardPaneIndex(in node: LayoutNode, currentIndex: Int) -> (index: Int, nextIndex: Int)? {
        switch node {
        case .pane(let data):
            if data.hasClipboard {
                return (index: currentIndex, nextIndex: currentIndex + 1)
            }
            return nil
        case .split(let data):
            if let found = clipboardPaneIndex(in: data.first, currentIndex: currentIndex) {
                return found
            }
            let firstCount = paneCount(in: data.first)
            return clipboardPaneIndex(in: data.second, currentIndex: currentIndex + firstCount)
        }
    }

    private func paneCount(in node: LayoutNode) -> Int {
        switch node {
        case .pane: return 1
        case .split(let data): return paneCount(in: data.first) + paneCount(in: data.second)
        }
    }

    // MARK: - Editor focus → pane focus

    @MainActor
    private func handleEditorFocused(_ textView: EditorTextView) {
        // Find which Bonsplit tab owns this text view
        guard let bonsplitTabID = editorStates.first(where: { $0.value.textView === textView })?.key else { return }

        // Find which pane contains that tab
        for paneID in controller.allPaneIds {
            let paneTabs = controller.tabs(inPane: paneID)
            if paneTabs.contains(where: { $0.id == bonsplitTabID }) {
                if controller.focusedPaneId != paneID {
                    controller.focusPane(paneID)
                }
                return
            }
        }
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
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
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
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
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
        let hadFile = tabStore.tabs.first(where: { $0.id == selectedTabStoreID })?.fileURL != nil
        tabStore.saveFileAs(id: selectedTabStoreID)
        if let bonsplitID = tabIDMap[selectedTabStoreID],
           let tab = tabStore.tabs.first(where: { $0.id == selectedTabStoreID }) {
            controller.updateTab(bonsplitID, title: tab.name, isDirty: tab.isDirty)
            if !hadFile, let fileURL = tab.fileURL {
                startWatching(url: fileURL, tabID: selectedTabStoreID)
            }
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
        isClosingConfirmedTab = true
        _ = controller.closeTab(selectedTab.id)
        isClosingConfirmedTab = false
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
    func selectTab(atIndex index: Int) {
        guard let focusedPaneId = controller.focusedPaneId else { return }
        let tabs = controller.tabs(inPane: focusedPaneId).filter { $0.id != clipboardTabID }
        guard index >= 0, index < tabs.count else { return }
        controller.selectTab(tabs[index].id)
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

        if isClosingConfirmedTab { return true }

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

            if tab.id == clipboardTabID {
                NotificationCenter.default.post(name: ClipboardStore.clipboardTabSelectedNotification, object: nil)
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
        if let fileURL = tabStore.tabs.first(where: { $0.id == tabStoreID })?.fileURL {
            fileWatcher.stop(url: fileURL)
        }
        editorStates.removeValue(forKey: tabId)
        tabIDMap.removeValue(forKey: tabStoreID)
        reverseMap.removeValue(forKey: tabId)
        tabStore.closeTab(id: tabStoreID)
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didSplitPane originalPane: PaneID,
        newPane: PaneID,
        orientation: SplitOrientation
    ) {
        MainActor.assumeIsolated {
            guard !isRestoringLayout else { return }

            // New panes must never be empty — create an untitled tab
            tabStore.addNewTab()
            guard let newTab = tabStore.tabs.last else { return }
            if let bonsplitTabID = controller.createTab(
                title: newTab.name,
                icon: nil,
                isDirty: newTab.isDirty,
                inPane: newPane
            ) {
                tabIDMap[newTab.id] = bonsplitTabID
                reverseMap[bonsplitTabID] = newTab.id
                editorStates[bonsplitTabID] = createEditorState(for: newTab)
                controller.selectTab(bonsplitTabID)
            }
        }
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

    // MARK: - Tab list for menu

    @MainActor
    func tabListForMenu() -> [(tabID: TabID, title: String, isSelected: Bool)] {
        guard let focusedPaneId = controller.focusedPaneId else { return [] }
        let selectedTab = controller.selectedTab(inPane: focusedPaneId)

        return controller.allTabIds.compactMap { tabID in
            guard let tab = controller.tab(tabID) else { return nil }
            let title = tabID == clipboardTabID ? "Clipboard" : tab.title
            return (tabID: tabID, title: title, isSelected: tabID == selectedTab?.id)
        }
    }

    @MainActor
    func saveActiveTabCursor() {
        saveCursorForSelectedTab()
        tabStore.currentLayout = captureLayout()
    }

    // MARK: - Layout capture

    @MainActor
    func captureLayout() -> LayoutNode? {
        let tree = controller.treeSnapshot()
        let bonsplitToStore = buildExternalIDToStoreIDMap()
        let clipExternalID = clipboardTabID.flatMap { tabID -> String? in
            guard let data = try? JSONEncoder().encode(tabID),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
            return dict["id"]
        }
        return convertNode(tree, mapping: bonsplitToStore, clipboardExternalID: clipExternalID)
    }

    private func buildExternalIDToStoreIDMap() -> [String: UUID] {
        var map: [String: UUID] = [:]
        for (tabStoreID, bonsplitTabID) in tabIDMap {
            // TabID is Codable with a single `id: UUID` field.
            // Encode to extract the UUID string that matches ExternalTab.id.
            if let data = try? JSONEncoder().encode(bonsplitTabID),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let uuidString = dict["id"] {
                map[uuidString] = tabStoreID
            }
        }
        return map
    }

    private func convertNode(_ node: ExternalTreeNode, mapping: [String: UUID], clipboardExternalID: String?) -> LayoutNode? {
        switch node {
        case .pane(let paneNode):
            let tabIDs = paneNode.tabs.compactMap { mapping[$0.id] }
            let hasClipboard = clipboardExternalID.map { clipID in
                paneNode.tabs.contains { $0.id == clipID }
            } ?? false
            guard !tabIDs.isEmpty || hasClipboard else { return nil }
            let selectedID: UUID? = paneNode.selectedTabId.flatMap { mapping[$0] }
            return .pane(PaneNodeData(tabIDs: tabIDs, selectedTabID: selectedID, hasClipboard: hasClipboard))

        case .split(let splitNode):
            guard let first = convertNode(splitNode.first, mapping: mapping, clipboardExternalID: clipboardExternalID),
                  let second = convertNode(splitNode.second, mapping: mapping, clipboardExternalID: clipboardExternalID) else {
                // If one side has no tabs (e.g. only clipboard), return the other
                let first = convertNode(splitNode.first, mapping: mapping, clipboardExternalID: clipboardExternalID)
                let second = convertNode(splitNode.second, mapping: mapping, clipboardExternalID: clipboardExternalID)
                return first ?? second
            }
            return .split(SplitNodeData(
                orientation: splitNode.orientation,
                dividerPosition: splitNode.dividerPosition,
                first: first,
                second: second
            ))
        }
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

    // MARK: - File watching

    @MainActor
    private func startWatching(url: URL, tabID: UUID) {
        fileWatcher.watch(url: url) { [weak self] in
            self?.handleFileChanged(tabID: tabID)
        }
    }

    @MainActor
    private func handleFileChanged(tabID: UUID) {
        guard let index = tabStore.tabs.firstIndex(where: { $0.id == tabID }),
              let fileURL = tabStore.tabs[index].fileURL,
              let bonsplitID = tabIDMap[tabID],
              let state = editorStates[bonsplitID] else { return }

        guard let newContent = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        // Skip if content matches (e.g. user just saved from itsypad)
        if tabStore.tabs[index].content == newContent { return }

        if tabStore.tabs[index].isDirty {
            let alert = NSAlert()
            alert.messageText = "\"\(tabStore.tabs[index].name)\" has been modified externally."
            alert.informativeText = "Do you want to reload it from disk or keep your changes?"
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Keep my changes")
            alert.alertStyle = .informational

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
        }

        let cursorPos = state.textView.selectedRange().location
        _ = tabStore.reloadFromDisk(id: tabID)
        let tab = tabStore.tabs[index]

        state.textView.string = tab.content
        let clampedPos = min(cursorPos, (tab.content as NSString).length)
        state.textView.setSelectedRange(NSRange(location: clampedPos, length: 0))
        state.highlightCoordinator.scheduleHighlightIfNeeded()
        controller.updateTab(bonsplitID, title: tab.name, isDirty: tab.isDirty)

        // Re-watch since delete/rename events invalidate the source
        startWatching(url: fileURL, tabID: tabID)
    }

    // MARK: - iCloud sync

    @MainActor
    private func handleCloudMerge(_ result: TabStore.CloudMergeResult) {
        // Create Bonsplit tabs for new cloud tabs
        for tabID in result.newTabIDs {
            guard let tab = tabStore.tabs.first(where: { $0.id == tabID }),
                  tabIDMap[tabID] == nil else { continue }
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

        // Update editor content for existing tabs
        for tabID in result.updatedTabIDs {
            guard let tab = tabStore.tabs.first(where: { $0.id == tabID }),
                  let bonsplitID = tabIDMap[tabID],
                  let state = editorStates[bonsplitID] else { continue }

            let cursorPos = state.textView.selectedRange().location
            state.textView.string = tab.content
            let clampedPos = min(cursorPos, (tab.content as NSString).length)
            state.textView.setSelectedRange(NSRange(location: clampedPos, length: 0))
            state.highlightCoordinator.language = tab.language
            state.highlightCoordinator.scheduleHighlightIfNeeded()
            state.gutterView.needsDisplay = true
            controller.updateTab(bonsplitID, title: tab.name, isDirty: tab.isDirty)
        }

        // Close tabs removed from cloud
        for tabID in result.removedTabIDs {
            guard let bonsplitID = tabIDMap[tabID] else { continue }
            editorStates.removeValue(forKey: bonsplitID)
            tabIDMap.removeValue(forKey: tabID)
            reverseMap.removeValue(forKey: bonsplitID)
            _ = controller.closeTab(bonsplitID)
        }
    }

    // MARK: - Settings

    @MainActor
    private func applySettings() {
        let settings = SettingsStore.shared
        let font = settings.editorFont
        let showGutter = settings.showLineNumbers

        applyClipboardEnabled(settings.clipboardEnabled)

        for (_, state) in editorStates {
            state.textView.font = font
            state.textView.wrapsLines = settings.wordWrap
            applyGutterVisibility(state: state, showGutter: showGutter)
            state.textView.textContainerInset = NSSize(width: showGutter ? 4 : 12, height: 12)
            state.highlightCoordinator.font = font
            state.highlightCoordinator.updateTheme()

            applyThemeToEditor(textView: state.textView, gutter: state.gutterView, coordinator: state.highlightCoordinator)
        }

        applyBonsplitTheme()
    }

    @MainActor
    private func applyClipboardEnabled(_ enabled: Bool) {
        if enabled {
            ClipboardStore.shared.startMonitoring()
            if clipboardTabID == nil {
                if let clipTabID = controller.createTab(title: "Clipboard", icon: "clipboardIcon", isClosable: false) {
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
        let bg: NSColor
        let isDark: Bool
        if let first = editorStates.values.first {
            bg = first.highlightCoordinator.themeBackgroundColor
            isDark = first.highlightCoordinator.themeIsDark
        } else {
            let theme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
            bg = theme.background
            isDark = theme.isDark
        }
        let blendTarget: NSColor = isDark ? .white : .black

        // Active tab = editor background
        BonsplitTheme.shared.activeTabBackground = bg

        // Tab bar background = slightly lighter/darker than editor
        BonsplitTheme.shared.barBackground = bg.blended(withFraction: 0.06, of: blendTarget) ?? bg

        // Separator blends into the bar
        BonsplitTheme.shared.separator = bg.blended(withFraction: 0.12, of: blendTarget) ?? bg
    }

    private func applyGutterVisibility(state: EditorState, showGutter: Bool) {
        let lineCount = state.textView.string.components(separatedBy: "\n").count
        state.gutterView.updateVisibility(showGutter, lineCount: lineCount)
    }

    private func applyThemeToEditor(textView: EditorTextView, gutter: LineNumberGutterView, coordinator: SyntaxHighlightCoordinator) {
        let settings = SettingsStore.shared
        let bg = coordinator.themeBackgroundColor
        let isDark = coordinator.themeIsDark

        textView.backgroundColor = bg
        textView.drawsBackground = true
        textView.insertionPointColor = isDark ? .white : .black

        gutter.bgColor = bg
        gutter.lineColor = isDark
            ? NSColor.white.withAlphaComponent(0.3)
            : NSColor.black.withAlphaComponent(0.3)
        gutter.lineFont = NSFont.monospacedSystemFont(
            ofSize: settings.editorFont.pointSize * 0.85,
            weight: .regular
        )
        gutter.needsDisplay = true
    }
}
