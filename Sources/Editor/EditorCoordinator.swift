import Cocoa
import SwiftUI
import Bonsplit

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
    private var editorFocusObserver: Any?

    private let previewManager = MarkdownPreviewManager()

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

        tabStore.onLanguageDetected = { [weak self] tabID, language in
            MainActor.assumeIsolated {
                guard let self, let bonsplitID = self.tabIDMap[tabID] else { return }
                self.highlighterForTab(bonsplitID)?.language = language

                self.previewManager.exitIfNotMarkdown(for: bonsplitID, language: language)

                self.postMarkdownState(for: bonsplitID)
            }
        }

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

        // Start sync engines if enabled (deferred so init completes first)
        DispatchQueue.main.async {
            CloudSyncEngine.shared.startIfEnabled()
            G2SyncEngine.shared.startIfEnabled()
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
        refreshCSSTheme()

        // Create clipboard tab in the pane it was saved in (or last pane as fallback)
        if SettingsStore.shared.clipboardEnabled {
            let clipboardPane = LayoutSerializer.findClipboardPane(in: tabStore.savedLayout, controller: controller) ?? controller.allPaneIds.last
            if let clipTabID = controller.createTab(title: "Clipboard", icon: "clipboardIcon", isClosable: false, isPinned: true, inPane: clipboardPane) {
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
        let state = EditorStateFactory.create(for: tab)
        wireUpTextChanges(textView: state.textView, tabID: tab.id)
        if let fileURL = tab.fileURL {
            startWatching(url: fileURL, tabID: tab.id)
        }
        return state
    }

    @MainActor
    private func wireUpTextChanges(textView: EditorTextView, tabID: UUID) {
        textView.onTextChange = { [weak self] text in
            guard let self else { return }
            guard let tabIndex = self.tabStore.tabs.firstIndex(where: { $0.id == tabID }) else { return }

            let oldName = self.tabStore.tabs[tabIndex].name
            let oldDirty = self.tabStore.tabs[tabIndex].isDirty

            self.tabStore.updateContent(id: tabID, content: text)

            if let bonsplitID = self.tabIDMap[tabID] {
                let tab = self.tabStore.tabs[tabIndex]
                // Only update Bonsplit tab bar when visible properties changed
                if tab.name != oldName || tab.isDirty != oldDirty {
                    self.controller.updateTab(bonsplitID, title: tab.name, isDirty: tab.isDirty)
                }
                self.highlighterForTab(bonsplitID)?.language = tab.language
                self.previewManager.scheduleUpdate(
                    for: bonsplitID,
                    content: tab.content,
                    fileURL: tab.fileURL,
                    theme: self.cssTheme
                )
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

    // MARK: - Markdown preview

    static let markdownStateChanged = Notification.Name("EditorCoordinatorMarkdownStateChanged")

    @MainActor
    var isCurrentTabMarkdown: Bool {
        guard let focusedPaneId = controller.focusedPaneId,
              let selectedTab = controller.selectedTab(inPane: focusedPaneId),
              selectedTab.id != clipboardTabID else { return false }
        return highlighterForTab(selectedTab.id)?.language == "markdown"
    }

    func isPreviewActive(for bonsplitTabID: TabID) -> Bool {
        previewManager.isActive(for: bonsplitTabID)
    }

    func previewHTML(for bonsplitTabID: TabID) -> String? {
        previewManager.html(for: bonsplitTabID)
    }

    func previewBaseURL(for bonsplitTabID: TabID) -> URL? {
        previewManager.baseURL(for: bonsplitTabID)
    }

    @MainActor
    func togglePreview() {
        guard let focusedPaneId = controller.focusedPaneId,
              let selectedTab = controller.selectedTab(inPane: focusedPaneId),
              selectedTab.id != clipboardTabID else { return }

        guard let tabStoreID = reverseMap[selectedTab.id],
              let tab = tabStore.tabs.first(where: { $0.id == tabStoreID }) else { return }

        previewManager.toggle(
            for: selectedTab.id,
            language: highlighterForTab(selectedTab.id)?.language,
            content: tab.content,
            fileURL: tab.fileURL,
            theme: cssTheme
        )

        postMarkdownState(for: selectedTab.id)
    }

    func postMarkdownState(for bonsplitTabID: TabID) {
        let isMarkdown = bonsplitTabID != clipboardTabID
            && highlighterForTab(bonsplitTabID)?.language == "markdown"
        let isPreviewing = previewManager.isActive(for: bonsplitTabID)
        NotificationCenter.default.post(
            name: Self.markdownStateChanged,
            object: nil,
            userInfo: ["isMarkdown": isMarkdown, "isPreviewing": isPreviewing]
        )
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

        _ = url.startAccessingSecurityScopedResource()
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
    func splitRight() {
        controller.splitPane(orientation: .horizontal)
    }

    @MainActor
    func splitDown() {
        controller.splitPane(orientation: .vertical)
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

            // Markdown toolbar state is handled by BonsplitRootView.onChange(of: isSelected)
            // since this delegate only fires for programmatic selectTab() calls, not user clicks.

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
        previewManager.removeTab(tabId)
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

                // The new text view isn't in the window yet; defer first responder
                let newState = editorStates[bonsplitTabID]
                DispatchQueue.main.async {
                    newState?.textView.window?.makeFirstResponder(newState?.textView)
                }
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

        if tab.isPinned {
            items.append(TabContextMenuItem(title: "Unpin tab", icon: "pin.slash") { [weak self] in
                MainActor.assumeIsolated {
                    self?.controller.updateTab(tab.id, isPinned: false)
                    self?.updatePinnedState(bonsplitTabID: tab.id, isPinned: false)
                }
            })
        } else {
            items.append(TabContextMenuItem(title: "Pin tab", icon: "pin") { [weak self] in
                MainActor.assumeIsolated {
                    self?.controller.updateTab(tab.id, isPinned: true)
                    self?.updatePinnedState(bonsplitTabID: tab.id, isPinned: true)
                }
            })
        }

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
        tabStore.currentLayout = LayoutSerializer.captureLayout(controller: controller, tabIDMap: tabIDMap, clipboardTabID: clipboardTabID)
    }

    @MainActor
    private func updatePinnedState(bonsplitTabID: TabID, isPinned: Bool) {
        guard let tabStoreID = reverseMap[bonsplitTabID],
              let index = tabStore.tabs.firstIndex(where: { $0.id == tabStoreID }) else { return }
        tabStore.tabs[index].isPinned = isPinned
        tabStore.scheduleSave()
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

            EditorStateFactory.applyTheme(textView: state.textView, gutter: state.gutterView, coordinator: state.highlightCoordinator)
        }

        refreshCSSTheme()
        applyBonsplitTheme()

        // Re-render any active markdown previews with the new theme
        let previewTabs: [(id: TabID, content: String, fileURL: URL?)] = controller.allTabIds.compactMap { bonsplitID in
            guard let tabStoreID = reverseMap[bonsplitID],
                  let tab = tabStore.tabs.first(where: { $0.id == tabStoreID }) else { return nil }
            return (id: bonsplitID, content: tab.content, fileURL: tab.fileURL)
        }
        previewManager.renderAll(tabs: previewTabs, theme: cssTheme)
    }

    @MainActor
    private func applyClipboardEnabled(_ enabled: Bool) {
        if enabled {
            ClipboardStore.shared.startMonitoring()
            if clipboardTabID == nil {
                if let clipTabID = controller.createTab(title: "Clipboard", icon: "clipboardIcon", isClosable: false, isPinned: true) {
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

    private(set) var cssTheme: EditorTheme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)

    private func refreshCSSTheme() {
        if let first = editorStates.values.first {
            cssTheme = first.highlightCoordinator.theme
        } else {
            cssTheme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
        }
    }

    private func applyBonsplitTheme() {
        let bg = cssTheme.background
        let isDark = cssTheme.isDark
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

}
