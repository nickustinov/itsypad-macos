import Bonsplit
import Cocoa
import SwiftUI

private class EditorPanel: NSPanel {
    override var hidesOnDeactivate: Bool {
        get { false }
        set { }
    }
}

// MARK: - Toolbar identifiers

private extension NSToolbarItem.Identifier {
    static let newTab = NSToolbarItem.Identifier("newTab")
    static let openFile = NSToolbarItem.Identifier("openFile")
    static let saveFile = NSToolbarItem.Identifier("saveFile")
    static let findReplace = NSToolbarItem.Identifier("findReplace")
    static let tabSwitcher = NSToolbarItem.Identifier("tabSwitcher")
    static let markdownPreview = NSToolbarItem.Identifier("markdownPreview")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSToolbarDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var editorWindow: NSPanel?
    private var editorCoordinator: EditorCoordinator?
    private var settingsWindow: NSWindow?
    private var windowWasVisible = false
    private var workspaceObserver: Any?
    private var settingsObserver: Any?
    private var appearanceObservation: NSKeyValueObservation?
    private var recentFilesMenu: NSMenu?
    private var isPinned = false
    private var markdownObserver: Any?
    private var showMarkdownPreview = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupEditorWindow()
        setupMainMenu()
        updateDockVisibility()

        // Register hotkey
        HotkeyManager.shared.register()

        // Start clipboard monitoring if enabled
        if SettingsStore.shared.clipboardEnabled {
            ClipboardStore.shared.startMonitoring()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editorWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: editorWindow
        )
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreWindowIfNeeded()
            }
        }
        // Apply theme to window when settings change
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyWindowAppearance()
                self?.updateDockVisibility()
                self?.updateMenuBarVisibility()
            }
        }

        // Re-apply theme when macOS appearance changes (affects "system" mode)
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard SettingsStore.shared.appearanceOverride == "system" else { return }
                NotificationCenter.default.post(name: .settingsChanged, object: nil)
            }
        }

        markdownObserver = NotificationCenter.default.addObserver(
            forName: EditorCoordinator.markdownStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                let isMarkdown = notification.userInfo?["isMarkdown"] as? Bool ?? false
                let isPreviewing = notification.userInfo?["isPreviewing"] as? Bool ?? false
                self?.updateMarkdownToolbarItem(isMarkdown: isMarkdown, isPreviewing: isPreviewing)
            }
        }

        // Notifications during EditorCoordinator.init fire before the observer above is registered,
        // so check the initial state now.
        if let isMarkdown = editorCoordinator?.isCurrentTabMarkdown {
            updateMarkdownToolbarItem(isMarkdown: isMarkdown, isPreviewing: false)
        }
    }

    @objc private func editorWindowWillClose(_ note: Notification) {
        windowWasVisible = false
        DispatchQueue.main.async { [weak self] in
            self?.updateDockVisibility()
        }
    }

    private func restoreWindowIfNeeded() {
        // Only needed in accessory mode (no dock icon) where macOS won't
        // automatically bring our window forward after the frontmost app quits.
        guard !SettingsStore.shared.showInDock else { return }
        guard windowWasVisible, let window = editorWindow else { return }
        guard window.isVisible, !window.isMiniaturized else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let window = editorWindow else { return false }
        windowWasVisible = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateDockVisibility()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardStore.shared.stopMonitoring()
        editorCoordinator?.saveActiveTabCursor()
        TabStore.shared.saveSession()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        showWindowAndOpen(url: url)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            showWindowAndOpen(url: url)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    private func showWindowAndOpen(url: URL) {
        guard let window = editorWindow else { return }
        windowWasVisible = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateDockVisibility()
        editorCoordinator?.openFile(url: url)
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = makeMenuBarIcon()
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }
    }

    private func makeMenuBarIcon() -> NSImage {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif
        guard let image = bundle.image(forResource: "menuBar") else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Itsypad", action: #selector(showItsypad), keyEquivalent: "")
        showItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        showItem.target = self
        if let keys = SettingsStore.shared.shortcutKeys {
            if keys.isTripleTap, let mod = keys.tapModifier {
                let symbol: String
                if mod.contains("option") { symbol = "⌥" }
                else if mod.contains("control") { symbol = "⌃" }
                else if mod.contains("shift") { symbol = "⇧" }
                else if mod.contains("command") { symbol = "⌘" }
                else { symbol = "" }
                let side = mod.hasPrefix("left-") ? " L" : mod.hasPrefix("right-") ? " R" : ""
                let hint = "  \(symbol)\(symbol)\(symbol)\(side)"
                let attributed = NSMutableAttributedString(string: "Show Itsypad")
                attributed.append(NSAttributedString(string: hint, attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
                showItem.attributedTitle = attributed
            } else if let char = Self.characterForKeyCode(keys.keyCode) {
                showItem.keyEquivalent = char
                showItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: UInt(keys.modifiers))
            }
        }
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Itsypad", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Editor window

    private func setupEditorWindow() {
        let coordinator = EditorCoordinator()
        editorCoordinator = coordinator

        let rootView = BonsplitRootView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: rootView)

        let panel = EditorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.tabbingMode = .disallowed
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenPrimary]
        panel.minSize = NSSize(width: 320, height: 400)
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.setFrameAutosaveName("EditorWindow")

        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        panel.toolbar = toolbar

        editorWindow = panel

        applyWindowAppearance()

        // Show window on launch
        windowWasVisible = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyWindowAppearance() {
        let theme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
        editorWindow?.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)

        // Set window background to theme color so Bonsplit's tab bar picks it up
        let blendTarget: NSColor = theme.isDark ? .white : .black
        let tabBarBg = theme.background.blended(withFraction: 0.06, of: blendTarget) ?? theme.background
        editorWindow?.backgroundColor = tabBarBg
    }

    func toggleWindow() {
        guard let window = editorWindow else { return }

        if window.isKeyWindow {
            windowWasVisible = false
            window.orderOut(nil)
        } else {
            windowWasVisible = true
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        updateDockVisibility()
    }

    func toggleClipboard() {
        guard let window = editorWindow else { return }

        if window.isKeyWindow {
            windowWasVisible = false
            window.orderOut(nil)
        } else {
            windowWasVisible = true
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            editorCoordinator?.selectClipboardTab()
        }
        updateDockVisibility()
    }

    private func updateDockVisibility() {
        NSApp.setActivationPolicy(SettingsStore.shared.showInDock ? .regular : .accessory)
    }

    private func updateMenuBarVisibility() {
        statusItem.isVisible = SettingsStore.shared.showInMenuBar
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var items: [NSToolbarItem.Identifier] = [.newTab, .openFile, .saveFile, .flexibleSpace, .tabSwitcher, .space]
        if showMarkdownPreview {
            items.append(.markdownPreview)
        }
        items.append(.findReplace)
        return items
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newTab, .openFile, .saveFile, .flexibleSpace, .tabSwitcher, .space, .markdownPreview, .findReplace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .tabSwitcher:
            let menuItem = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            menuItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Tabs")
            menuItem.label = "Tabs"
            menuItem.toolTip = "Switch tab"
            menuItem.showsIndicator = true
            menuItem.menu = buildTabSwitcherMenu()
            return menuItem
        default:
            break
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .newTab:
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")
            item.label = "New tab"
            item.toolTip = "New tab"
            item.target = self
            item.action = #selector(newTabAction)
        case .openFile:
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open")
            item.label = "Open"
            item.toolTip = "Open file"
            item.target = self
            item.action = #selector(openFileAction)
        case .saveFile:
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            item.label = "Save"
            item.toolTip = "Save file"
            item.target = self
            item.action = #selector(saveFileAction)
        case .markdownPreview:
            let isPreviewing = currentSelectedTabID().flatMap { editorCoordinator?.isPreviewActive(for: $0) } ?? false
            item.image = NSImage(systemSymbolName: isPreviewing ? "rectangle.split.2x1.fill" : "rectangle.split.2x1", accessibilityDescription: "Preview")
            item.label = "Preview"
            item.toolTip = "Toggle markdown preview (⇧⌘P)"
            item.target = self
            item.action = #selector(togglePreviewAction)
        case .findReplace:
            item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")
            item.label = "Find"
            item.toolTip = "Find and replace (⌘F)"
            item.target = self
            item.action = #selector(toggleFindAction)
        default:
            return nil
        }

        return item
    }

    // MARK: - Settings

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Itsypad settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    // MARK: - Main menu

    private func setupMainMenu() {
        let builder = MenuBuilder(target: self)

        let recentMenu = NSMenu(title: "Open recent")
        recentMenu.delegate = self
        recentFilesMenu = recentMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(builder.buildAppMenuItem())
        mainMenu.addItem(builder.buildFileMenuItem(recentFilesMenu: recentMenu))
        mainMenu.addItem(builder.buildEditMenuItem())
        mainMenu.addItem(builder.buildViewMenuItem())
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu actions

    @objc private func showItsypad() {
        toggleWindow()
    }

    @objc func checkForUpdates() {
        UpdateChecker.check()
    }

    @objc private func quitApp() {
        TabStore.shared.saveSession()
        NSApp.terminate(nil)
    }

    @objc func newTabAction() {
        editorCoordinator?.newTab()
    }

    @objc func openFileAction() {
        editorCoordinator?.openFile()
    }

    @objc func saveFileAction() {
        editorCoordinator?.saveFile()
    }

    @objc func saveFileAsAction() {
        editorCoordinator?.saveFileAs()
    }

    @objc func findAction(_ sender: NSMenuItem) {
        editorCoordinator?.activeTextView()?.performFindPanelAction(sender)
    }

    @objc func toggleChecklistAction() {
        editorCoordinator?.activeTextView()?.toggleChecklist()
    }

    @objc func moveLineUpAction() {
        editorCoordinator?.activeTextView()?.moveLine(.up)
    }

    @objc func moveLineDownAction() {
        editorCoordinator?.activeTextView()?.moveLine(.down)
    }

    @objc func closeTabAction() {
        editorCoordinator?.closeCurrentTab()
    }

    @objc func nextTabAction() {
        editorCoordinator?.selectNextTab()
    }

    @objc func previousTabAction() {
        editorCoordinator?.selectPreviousTab()
    }

    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        editorCoordinator?.selectTab(atIndex: sender.tag - 1)
    }

    @objc func splitRight() {
        editorCoordinator?.splitRight()
    }

    @objc func splitDown() {
        editorCoordinator?.splitDown()
    }

    @objc func increaseFontSize() {
        SettingsStore.shared.editorFontSize = min(36, SettingsStore.shared.editorFontSize + 1)
    }

    @objc func decreaseFontSize() {
        SettingsStore.shared.editorFontSize = max(8, SettingsStore.shared.editorFontSize - 1)
    }

    @objc func resetFontSize() {
        SettingsStore.shared.editorFontSize = 14
    }

    @objc func toggleLineNumbers() {
        SettingsStore.shared.showLineNumbers.toggle()
    }

    @objc func toggleWordWrap() {
        SettingsStore.shared.wordWrap.toggle()
    }

    @objc func togglePin() {
        isPinned.toggle()
        editorWindow?.level = isPinned ? .floating : .normal
    }

    @objc func togglePreviewAction() {
        editorCoordinator?.togglePreview()
    }

    private func currentSelectedTabID() -> TabID? {
        guard let focusedPaneId = editorCoordinator?.controller.focusedPaneId else { return nil }
        return editorCoordinator?.controller.selectedTab(inPane: focusedPaneId)?.id
    }

    private func updateMarkdownToolbarItem(isMarkdown: Bool, isPreviewing: Bool) {
        guard let window = editorWindow else { return }

        if isMarkdown != showMarkdownPreview {
            showMarkdownPreview = isMarkdown
            let toolbar = NSToolbar(identifier: "EditorToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        } else if isMarkdown, let item = window.toolbar?.items.first(where: { $0.itemIdentifier == .markdownPreview }) {
            item.image = NSImage(
                systemSymbolName: isPreviewing ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                accessibilityDescription: "Preview"
            )
        }
    }

    private func buildTabSwitcherMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    private func updateTabSwitcherMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        // NSMenuToolbarItem hides the first item; add a dummy so all tabs show
        let dummy = NSMenuItem(title: "Tabs", action: nil, keyEquivalent: "")
        dummy.isHidden = true
        menu.addItem(dummy)
        guard let coordinator = editorCoordinator else { return }
        for entry in coordinator.tabListForMenu() {
            let item = NSMenuItem(title: entry.title, action: #selector(switchToTab(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.tabID
            item.state = entry.isSelected ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func switchToTab(_ sender: NSMenuItem) {
        guard let tabID = sender.representedObject as? TabID else { return }
        editorCoordinator?.controller.selectTab(tabID)
    }

    @objc private func toggleFindAction() {
        guard let textView = editorCoordinator?.activeTextView() else { return }
        let isVisible = textView.enclosingScrollView?.isFindBarVisible ?? false
        let item = NSMenuItem()
        item.tag = Int((isVisible ? NSTextFinder.Action.hideFindInterface : NSTextFinder.Action.showFindInterface).rawValue)
        textView.performFindPanelAction(item)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Tab switcher menu — rebuild dynamically each time it opens
        if let toolbarItem = editorWindow?.toolbar?.items.first(where: { $0.itemIdentifier == .tabSwitcher }) as? NSMenuToolbarItem,
           menu === toolbarItem.menu {
            updateTabSwitcherMenu(menu)
            return
        }

        guard menu === recentFilesMenu else { return }
        menu.removeAllItems()

        let recentURLs = NSDocumentController.shared.recentDocumentURLs
        if recentURLs.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent files", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for url in recentURLs {
            let item = NSMenuItem(title: url.path, action: #selector(openRecentFile(_:)), keyEquivalent: "")
            item.target = self
            item.toolTip = url.path
            item.representedObject = url
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear menu", action: #selector(clearRecentFiles), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        showWindowAndOpen(url: url)
    }

    @objc private func clearRecentFiles() {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    private static func characterForKeyCode(_ keyCode: UInt16) -> String? {
        let map: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
            38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "n", 46: "m", 47: ".",
        ]
        return map[keyCode]
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLineNumbers) {
            menuItem.state = SettingsStore.shared.showLineNumbers ? .on : .off
        }
        if menuItem.action == #selector(toggleWordWrap) {
            menuItem.state = SettingsStore.shared.wordWrap ? .on : .off
        }
        if menuItem.action == #selector(togglePin) {
            menuItem.state = isPinned ? .on : .off
        }
        if menuItem.action == #selector(togglePreviewAction) {
            let isMarkdown = editorCoordinator?.isCurrentTabMarkdown ?? false
            if isMarkdown, let tabID = currentSelectedTabID() {
                menuItem.state = editorCoordinator?.isPreviewActive(for: tabID) ?? false ? .on : .off
            } else {
                menuItem.state = .off
            }
            return isMarkdown
        }
        return true
    }

}
