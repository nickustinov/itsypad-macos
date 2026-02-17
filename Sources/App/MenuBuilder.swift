import Cocoa

class MenuBuilder {
    private weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
    }

    func buildAppMenuItem() -> NSMenuItem {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: String(localized: "menu.app.about", defaultValue: "About Itsypad"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let settingsMenuItem = NSMenuItem(title: String(localized: "menu.app.settings", defaultValue: "Settings..."), action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settingsMenuItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsMenuItem.target = target
        menu.addItem(settingsMenuItem)

        #if !APPSTORE
        let updateItem = NSMenuItem(title: String(localized: "menu.app.check_for_updates", defaultValue: "Check for updates..."), action: #selector(AppDelegate.checkForUpdates), keyEquivalent: "")
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        updateItem.target = target
        menu.addItem(updateItem)
        #endif

        menu.addItem(.separator())

        let hideItem = NSMenuItem(title: String(localized: "menu.app.hide", defaultValue: "Hide Itsypad"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        menu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: String(localized: "menu.app.hide_others", defaultValue: "Hide others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.image = NSImage(systemSymbolName: "eye.slash.circle", accessibilityDescription: nil)
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: String(localized: "menu.app.show_all", defaultValue: "Show all"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        menu.addItem(showAllItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "menu.app.quit", defaultValue: "Quit Itsypad"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    func buildFileMenuItem(recentFilesMenu: NSMenu) -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "menu.file", defaultValue: "File"))

        let newTabTitle = String(localized: "menu.file.new_tab", defaultValue: "New tab")
        let newTabItem = NSMenuItem(title: newTabTitle, action: #selector(AppDelegate.newTabAction), keyEquivalent: "t")
        newTabItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(newTabItem)

        let altNewTab = NSMenuItem(title: newTabTitle, action: #selector(AppDelegate.newTabAction), keyEquivalent: "n")
        altNewTab.isHidden = true
        altNewTab.allowsKeyEquivalentWhenHidden = true
        menu.addItem(altNewTab)

        let openItem = NSMenuItem(title: String(localized: "menu.file.open", defaultValue: "Open..."), action: #selector(AppDelegate.openFileAction), keyEquivalent: "o")
        openItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(openItem)

        let recentItem = NSMenuItem(title: String(localized: "menu.file.open_recent", defaultValue: "Open recent"), action: nil, keyEquivalent: "")
        recentItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        recentItem.submenu = recentFilesMenu
        menu.addItem(recentItem)

        let saveItem = NSMenuItem(title: String(localized: "menu.file.save", defaultValue: "Save"), action: #selector(AppDelegate.saveFileAction), keyEquivalent: "s")
        saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        menu.addItem(saveItem)

        let saveAsItem = NSMenuItem(title: String(localized: "menu.file.save_as", defaultValue: "Save as..."), action: #selector(AppDelegate.saveFileAsAction), keyEquivalent: "S")
        saveAsItem.image = NSImage(systemSymbolName: "square.and.arrow.down.on.square", accessibilityDescription: nil)
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAsItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: String(localized: "menu.file.close_tab", defaultValue: "Close tab"), action: #selector(AppDelegate.closeTabAction), keyEquivalent: "w")
        closeItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        menu.addItem(closeItem)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    func buildEditMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "menu.edit", defaultValue: "Edit"))

        let undoItem = NSMenuItem(title: String(localized: "menu.edit.undo", defaultValue: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        menu.addItem(undoItem)

        let redoItem = NSMenuItem(title: String(localized: "menu.edit.redo", defaultValue: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil)
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redoItem)

        menu.addItem(.separator())

        let cutItem = NSMenuItem(title: String(localized: "menu.edit.cut", defaultValue: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        menu.addItem(cutItem)

        let copyItem = NSMenuItem(title: String(localized: "menu.edit.copy", defaultValue: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: String(localized: "menu.edit.paste", defaultValue: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(pasteItem)

        let selectAllItem = NSMenuItem(title: String(localized: "menu.edit.select_all", defaultValue: "Select all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.image = NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: nil)
        menu.addItem(selectAllItem)

        menu.addItem(.separator())

        let findMenu = NSMenu(title: String(localized: "menu.edit.find", defaultValue: "Find"))

        let findItem = NSMenuItem(title: String(localized: "menu.edit.find_ellipsis", defaultValue: "Find..."), action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "f")
        findItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        findItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        findItem.target = target
        findMenu.addItem(findItem)

        let replaceItem = NSMenuItem(title: String(localized: "menu.edit.find_and_replace", defaultValue: "Find and replace..."), action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "f")
        replaceItem.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: nil)
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        replaceItem.tag = Int(NSTextFinder.Action.showReplaceInterface.rawValue)
        replaceItem.target = target
        findMenu.addItem(replaceItem)

        let findNextItem = NSMenuItem(title: String(localized: "menu.edit.find_next", defaultValue: "Find next"), action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "g")
        findNextItem.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        findNextItem.tag = Int(NSTextFinder.Action.nextMatch.rawValue)
        findNextItem.target = target
        findMenu.addItem(findNextItem)

        let findPrevItem = NSMenuItem(title: String(localized: "menu.edit.find_previous", defaultValue: "Find previous"), action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "G")
        findPrevItem.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)
        findPrevItem.keyEquivalentModifierMask = [.command, .shift]
        findPrevItem.tag = Int(NSTextFinder.Action.previousMatch.rawValue)
        findPrevItem.target = target
        findMenu.addItem(findPrevItem)

        let useSelItem = NSMenuItem(title: String(localized: "menu.edit.use_selection_for_find", defaultValue: "Use selection for find"), action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "e")
        useSelItem.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: nil)
        useSelItem.tag = Int(NSTextFinder.Action.setSearchString.rawValue)
        useSelItem.target = target
        findMenu.addItem(useSelItem)

        let findMenuItem = NSMenuItem(title: String(localized: "menu.edit.find", defaultValue: "Find"), action: nil, keyEquivalent: "")
        findMenuItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        findMenuItem.submenu = findMenu
        menu.addItem(findMenuItem)

        menu.addItem(.separator())

        let toggleChecklistItem = NSMenuItem(title: String(localized: "menu.edit.toggle_checklist", defaultValue: "Toggle checklist"), action: #selector(AppDelegate.toggleChecklistAction), keyEquivalent: "l")
        toggleChecklistItem.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)
        toggleChecklistItem.keyEquivalentModifierMask = [.command, .shift]
        toggleChecklistItem.target = target
        menu.addItem(toggleChecklistItem)

        let moveUpItem = NSMenuItem(title: String(localized: "menu.edit.move_line_up", defaultValue: "Move line up"), action: #selector(AppDelegate.moveLineUpAction), keyEquivalent: "")
        moveUpItem.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
        moveUpItem.keyEquivalent = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        moveUpItem.keyEquivalentModifierMask = [.command, .option]
        moveUpItem.target = target
        menu.addItem(moveUpItem)

        let moveDownItem = NSMenuItem(title: String(localized: "menu.edit.move_line_down", defaultValue: "Move line down"), action: #selector(AppDelegate.moveLineDownAction), keyEquivalent: "")
        moveDownItem.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)
        moveDownItem.keyEquivalent = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        moveDownItem.keyEquivalentModifierMask = [.command, .option]
        moveDownItem.target = target
        menu.addItem(moveDownItem)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    func buildViewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "menu.view", defaultValue: "View"))

        let zoomInItem = NSMenuItem(title: String(localized: "menu.view.increase_font_size", defaultValue: "Increase font size"), action: #selector(AppDelegate.increaseFontSize), keyEquivalent: "+")
        zoomInItem.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: nil)
        zoomInItem.target = target
        menu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: String(localized: "menu.view.decrease_font_size", defaultValue: "Decrease font size"), action: #selector(AppDelegate.decreaseFontSize), keyEquivalent: "-")
        zoomOutItem.image = NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: nil)
        zoomOutItem.target = target
        menu.addItem(zoomOutItem)

        let resetZoomItem = NSMenuItem(title: String(localized: "menu.view.reset_font_size", defaultValue: "Reset font size"), action: #selector(AppDelegate.resetFontSize), keyEquivalent: "0")
        resetZoomItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        resetZoomItem.target = target
        menu.addItem(resetZoomItem)

        menu.addItem(.separator())

        let wordWrapItem = NSMenuItem(title: String(localized: "menu.view.word_wrap", defaultValue: "Word wrap"), action: #selector(AppDelegate.toggleWordWrap), keyEquivalent: "")
        wordWrapItem.image = NSImage(systemSymbolName: "arrow.turn.down.left", accessibilityDescription: nil)
        wordWrapItem.target = target
        menu.addItem(wordWrapItem)

        let lineNumbersItem = NSMenuItem(title: String(localized: "menu.view.show_line_numbers", defaultValue: "Show line numbers"), action: #selector(AppDelegate.toggleLineNumbers), keyEquivalent: "")
        lineNumbersItem.image = NSImage(systemSymbolName: "list.number", accessibilityDescription: nil)
        lineNumbersItem.target = target
        menu.addItem(lineNumbersItem)

        let pinItem = NSMenuItem(title: String(localized: "menu.view.always_on_top", defaultValue: "Always on top"), action: #selector(AppDelegate.togglePin), keyEquivalent: "T")
        pinItem.image = NSImage(systemSymbolName: "pin", accessibilityDescription: nil)
        pinItem.keyEquivalentModifierMask = [.command, .shift]
        pinItem.target = target
        menu.addItem(pinItem)

        let previewItem = NSMenuItem(title: String(localized: "menu.view.toggle_preview", defaultValue: "Toggle preview"), action: #selector(AppDelegate.togglePreviewAction), keyEquivalent: "p")
        previewItem.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
        previewItem.keyEquivalentModifierMask = [.command, .shift]
        previewItem.target = target
        menu.addItem(previewItem)

        menu.addItem(.separator())

        let nextTabItem = NSMenuItem(title: String(localized: "menu.view.next_tab", defaultValue: "Next tab"), action: #selector(AppDelegate.nextTabAction), keyEquivalent: "\t")
        nextTabItem.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        nextTabItem.keyEquivalentModifierMask = [.control]
        nextTabItem.target = target
        menu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: String(localized: "menu.view.previous_tab", defaultValue: "Previous tab"), action: #selector(AppDelegate.previousTabAction), keyEquivalent: "\t")
        prevTabItem.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        prevTabItem.keyEquivalentModifierMask = [.control, .shift]
        prevTabItem.target = target
        menu.addItem(prevTabItem)

        menu.addItem(.separator())

        let splitRightItem = NSMenuItem(title: String(localized: "menu.view.split_right", defaultValue: "Split right"), action: #selector(AppDelegate.splitRight), keyEquivalent: "D")
        splitRightItem.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
        splitRightItem.keyEquivalentModifierMask = [.command, .shift]
        splitRightItem.target = target
        menu.addItem(splitRightItem)

        let splitDownItem = NSMenuItem(title: String(localized: "menu.view.split_down", defaultValue: "Split down"), action: #selector(AppDelegate.splitDown), keyEquivalent: "d")
        splitDownItem.image = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil)
        splitDownItem.keyEquivalentModifierMask = [.command, .control, .shift]
        splitDownItem.target = target
        menu.addItem(splitDownItem)

        menu.addItem(.separator())

        for i in 1...9 {
            let tabItem = NSMenuItem(title: String(localized: "menu.view.tab_n", defaultValue: "Tab \(i)"), action: #selector(AppDelegate.selectTabByNumber(_:)), keyEquivalent: "\(i)")
            tabItem.image = NSImage(systemSymbolName: "\(i).square", accessibilityDescription: nil)
            tabItem.tag = i
            tabItem.target = target
            menu.addItem(tabItem)
        }

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    func buildHelpMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "menu.help", defaultValue: "Help"))

        let websiteItem = NSMenuItem(title: String(localized: "menu.help.website", defaultValue: "Itsypad website"), action: #selector(AppDelegate.openHelpURL(_:)), keyEquivalent: "")
        websiteItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        websiteItem.representedObject = githubURL
        websiteItem.target = target
        menu.addItem(websiteItem)

        #if !APPSTORE
        let releasesItem = NSMenuItem(title: String(localized: "menu.help.release_notes", defaultValue: "Release notes"), action: #selector(AppDelegate.openHelpURL(_:)), keyEquivalent: "")
        releasesItem.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil)
        releasesItem.representedObject = githubURL + "/releases"
        releasesItem.target = target
        menu.addItem(releasesItem)
        #endif

        let issuesItem = NSMenuItem(title: String(localized: "menu.help.report_issue", defaultValue: "Report an issue"), action: #selector(AppDelegate.openHelpURL(_:)), keyEquivalent: "")
        issuesItem.image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: nil)
        issuesItem.representedObject = githubURL + "/issues"
        issuesItem.target = target
        menu.addItem(issuesItem)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
