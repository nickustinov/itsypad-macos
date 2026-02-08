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

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem!
    private var editorWindow: NSPanel?
    private var editorViewController: EditorViewController?
    private var settingsWindow: NSWindow?
    private var windowWasVisible = false
    private var workspaceObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock icon / Cmd-Tab visibility
        NSApp.setActivationPolicy(SettingsStore.shared.showInDock ? .regular : .accessory)

        setupStatusItem()
        setupEditorWindow()
        setupMainMenu()

        // Register hotkey
        HotkeyManager.shared.register()

        // Start clipboard monitoring
        ClipboardStore.shared.startMonitoring()

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
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreWindowIfNeeded()
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

    private func restoreWindowIfNeeded() {
        guard windowWasVisible, let window = editorWindow else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardStore.shared.stopMonitoring()
        TabStore.shared.saveSession()
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
        if editorViewController == nil {
            editorViewController = EditorViewController()
        }

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
        panel.contentViewController = editorViewController
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.setFrameAutosaveName("EditorWindow")

        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.delegate = editorViewController
        toolbar.displayMode = .iconOnly
        panel.toolbar = toolbar

        editorWindow = panel
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

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Itsypad", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        appMenu.addItem(settingsMenuItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Itsypad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New tab", action: #selector(newTabAction), keyEquivalent: "t"))
        fileMenu.addItem(NSMenuItem(title: "Open...", action: #selector(openFileAction), keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem(title: "Save", action: #selector(saveFileAction), keyEquivalent: "s"))

        let saveAsItem = NSMenuItem(title: "Save as...", action: #selector(saveFileAsAction), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAsItem)

        fileMenu.addItem(.separator())

        let closeTabItem = NSMenuItem(title: "Close tab", action: #selector(closeTabAction), keyEquivalent: "w")
        fileMenu.addItem(closeTabItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select all", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")

        let zoomInItem = NSMenuItem(title: "Increase font size", action: #selector(increaseFontSize), keyEquivalent: "+")
        zoomInItem.target = self
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Decrease font size", action: #selector(decreaseFontSize), keyEquivalent: "-")
        zoomOutItem.target = self
        viewMenu.addItem(zoomOutItem)

        let resetZoomItem = NSMenuItem(title: "Reset font size", action: #selector(resetFontSize), keyEquivalent: "0")
        resetZoomItem.target = self
        viewMenu.addItem(resetZoomItem)

        viewMenu.addItem(.separator())

        let lineNumbersItem = NSMenuItem(title: "Show line numbers", action: #selector(toggleLineNumbers), keyEquivalent: "l")
        lineNumbersItem.keyEquivalentModifierMask = [.command, .shift]
        lineNumbersItem.target = self
        viewMenu.addItem(lineNumbersItem)

        viewMenu.addItem(.separator())

        let nextTabItem = NSMenuItem(title: "Next tab", action: #selector(nextTabAction), keyEquivalent: "\t")
        nextTabItem.keyEquivalentModifierMask = [.control]
        nextTabItem.target = self
        viewMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Previous tab", action: #selector(previousTabAction), keyEquivalent: "\t")
        prevTabItem.keyEquivalentModifierMask = [.control, .shift]
        prevTabItem.target = self
        viewMenu.addItem(prevTabItem)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
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
        editorViewController?.newTab()
    }

    @objc private func openFileAction() {
        editorViewController?.openFile()
    }

    @objc private func saveFileAction() {
        editorViewController?.saveFile()
    }

    @objc private func saveFileAsAction() {
        editorViewController?.saveFileAs()
    }

    @objc private func closeTabAction() {
        editorViewController?.closeCurrentTab()
    }

    @objc private func nextTabAction() {
        editorViewController?.selectNextTab()
    }

    @objc private func previousTabAction() {
        editorViewController?.selectPreviousTab()
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLineNumbers) {
            menuItem.state = SettingsStore.shared.showLineNumbers ? .on : .off
        }
        return true
    }
}
