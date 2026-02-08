import Bonsplit
import Cocoa
import SwiftUI

private class EditorPanel: NSPanel {
    override var hidesOnDeactivate: Bool {
        get { false }
        set { }
    }
    override var canHide: Bool {
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
    private var recentFilesMenu: NSMenu?

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

        // Track window visibility and re-show after other apps quit
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeVisible),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidOrderOut),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
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
            }
        }
    }

    @objc private func windowDidBecomeVisible(_ note: Notification) {
        if (note.object as? NSWindow) === editorWindow {
            windowWasVisible = true
        }
    }

    @objc private func windowDidOrderOut(_ note: Notification) {
        // Only clear the flag if WE intentionally hid it (via toggleWindow)
        // Don't clear on resign-key — that happens when another app activates
    }

    @objc private func editorWindowWillClose(_ note: Notification) {
        windowWasVisible = false
        DispatchQueue.main.async { [weak self] in
            self?.updateDockVisibility()
        }
    }

    private func restoreWindowIfNeeded() {
        guard windowWasVisible, let window = editorWindow else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardStore.shared.stopMonitoring()
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
                showItem.title = "Show Itsypad  \(symbol)\(symbol)\(symbol)\(side)"
            }
        }
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Itsypad", action: #selector(quitApp), keyEquivalent: "q")
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
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.tabbingMode = .disallowed
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenAuxiliary]
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
        let alwaysShow = SettingsStore.shared.showInDock
        let windowVisible = editorWindow?.isVisible ?? false
        NSApp.setActivationPolicy((alwaysShow || windowVisible) ? .regular : .accessory)
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newTab, .openFile, .saveFile, .flexibleSpace, .tabSwitcher, .findReplace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newTab, .openFile, .saveFile, .flexibleSpace, .space, .tabSwitcher, .findReplace]
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

    @objc private func openSettings() {
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
        let mainMenu = NSMenu()
        mainMenu.addItem(buildAppMenuItem())
        mainMenu.addItem(buildFileMenuItem())
        mainMenu.addItem(buildEditMenuItem())
        mainMenu.addItem(buildViewMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func buildAppMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Itsypad", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Itsypad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private func buildFileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(NSMenuItem(title: "New tab", action: #selector(newTabAction), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "New tab", action: #selector(newTabAction), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Open...", action: #selector(openFileAction), keyEquivalent: "o"))

        let recentMenu = NSMenu(title: "Open recent")
        recentMenu.delegate = self
        recentFilesMenu = recentMenu
        let recentItem = NSMenuItem(title: "Open recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem(title: "Save", action: #selector(saveFileAction), keyEquivalent: "s"))

        let saveAsItem = NSMenuItem(title: "Save as...", action: #selector(saveFileAsAction), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Close tab", action: #selector(closeTabAction), keyEquivalent: "w"))

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private func buildEditMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "Select all", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        menu.addItem(.separator())

        let findMenu = NSMenu(title: "Find")

        let findItem = NSMenuItem(title: "Find...", action: #selector(findAction(_:)), keyEquivalent: "f")
        findItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        findItem.target = self
        findMenu.addItem(findItem)

        let replaceItem = NSMenuItem(title: "Find and replace...", action: #selector(findAction(_:)), keyEquivalent: "f")
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        replaceItem.tag = Int(NSTextFinder.Action.showReplaceInterface.rawValue)
        replaceItem.target = self
        findMenu.addItem(replaceItem)

        let findNextItem = NSMenuItem(title: "Find next", action: #selector(findAction(_:)), keyEquivalent: "g")
        findNextItem.tag = Int(NSTextFinder.Action.nextMatch.rawValue)
        findNextItem.target = self
        findMenu.addItem(findNextItem)

        let findPrevItem = NSMenuItem(title: "Find previous", action: #selector(findAction(_:)), keyEquivalent: "G")
        findPrevItem.keyEquivalentModifierMask = [.command, .shift]
        findPrevItem.tag = Int(NSTextFinder.Action.previousMatch.rawValue)
        findPrevItem.target = self
        findMenu.addItem(findPrevItem)

        let useSelItem = NSMenuItem(title: "Use selection for find", action: #selector(findAction(_:)), keyEquivalent: "e")
        useSelItem.tag = Int(NSTextFinder.Action.setSearchString.rawValue)
        useSelItem.target = self
        findMenu.addItem(useSelItem)

        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findMenuItem.submenu = findMenu
        menu.addItem(findMenuItem)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private func buildViewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")

        let zoomInItem = NSMenuItem(title: "Increase font size", action: #selector(increaseFontSize), keyEquivalent: "+")
        zoomInItem.target = self
        menu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Decrease font size", action: #selector(decreaseFontSize), keyEquivalent: "-")
        zoomOutItem.target = self
        menu.addItem(zoomOutItem)

        let resetZoomItem = NSMenuItem(title: "Reset font size", action: #selector(resetFontSize), keyEquivalent: "0")
        resetZoomItem.target = self
        menu.addItem(resetZoomItem)

        menu.addItem(.separator())

        let wordWrapItem = NSMenuItem(title: "Word wrap", action: #selector(toggleWordWrap), keyEquivalent: "")
        wordWrapItem.target = self
        menu.addItem(wordWrapItem)

        let lineNumbersItem = NSMenuItem(title: "Show line numbers", action: #selector(toggleLineNumbers), keyEquivalent: "l")
        lineNumbersItem.keyEquivalentModifierMask = [.command, .shift]
        lineNumbersItem.target = self
        menu.addItem(lineNumbersItem)

        menu.addItem(.separator())

        let nextTabItem = NSMenuItem(title: "Next tab", action: #selector(nextTabAction), keyEquivalent: "\t")
        nextTabItem.keyEquivalentModifierMask = [.control]
        nextTabItem.target = self
        menu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Previous tab", action: #selector(previousTabAction), keyEquivalent: "\t")
        prevTabItem.keyEquivalentModifierMask = [.control, .shift]
        prevTabItem.target = self
        menu.addItem(prevTabItem)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Menu actions

    @objc private func showItsypad() {
        toggleWindow()
    }

    @objc private func quitApp() {
        TabStore.shared.saveSession()
        NSApp.terminate(nil)
    }

    @objc private func newTabAction() {
        editorCoordinator?.newTab()
    }

    @objc private func openFileAction() {
        editorCoordinator?.openFile()
    }

    @objc private func saveFileAction() {
        editorCoordinator?.saveFile()
    }

    @objc private func saveFileAsAction() {
        editorCoordinator?.saveFileAs()
    }

    @objc private func findAction(_ sender: NSMenuItem) {
        editorCoordinator?.activeTextView()?.performFindPanelAction(sender)
    }

    @objc private func closeTabAction() {
        editorCoordinator?.closeCurrentTab()
    }

    @objc private func nextTabAction() {
        editorCoordinator?.selectNextTab()
    }

    @objc private func previousTabAction() {
        editorCoordinator?.selectPreviousTab()
    }

    @objc private func increaseFontSize() {
        SettingsStore.shared.editorFontSize = min(36, SettingsStore.shared.editorFontSize + 1)
    }

    @objc private func decreaseFontSize() {
        SettingsStore.shared.editorFontSize = max(8, SettingsStore.shared.editorFontSize - 1)
    }

    @objc private func resetFontSize() {
        SettingsStore.shared.editorFontSize = 14
    }

    @objc private func toggleLineNumbers() {
        SettingsStore.shared.showLineNumbers.toggle()
    }

    @objc private func toggleWordWrap() {
        SettingsStore.shared.wordWrap.toggle()
    }

    private func buildTabSwitcherMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    private func updateTabSwitcherMenu(_ menu: NSMenu) {
        menu.removeAllItems()
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
        let item = NSMenuItem()
        item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        editorCoordinator?.activeTextView()?.performFindPanelAction(item)
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLineNumbers) {
            menuItem.state = SettingsStore.shared.showLineNumbers ? .on : .off
        }
        if menuItem.action == #selector(toggleWordWrap) {
            menuItem.state = SettingsStore.shared.wordWrap ? .on : .off
        }
        return true
    }
}
