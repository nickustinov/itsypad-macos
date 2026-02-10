import Cocoa

class MenuBuilder {
    private weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
    }

    func buildAppMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Itsypad", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settingsMenuItem.target = target
        menu.addItem(settingsMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Hide Itsypad", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthersItem)
        menu.addItem(NSMenuItem(title: "Show all", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Itsypad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    func buildFileMenuItem(recentFilesMenu: NSMenu) -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(NSMenuItem(title: "New tab", action: #selector(AppDelegate.newTabAction), keyEquivalent: "t"))
        let altNewTab = NSMenuItem(title: "New tab", action: #selector(AppDelegate.newTabAction), keyEquivalent: "n")
        altNewTab.isHidden = true
        altNewTab.allowsKeyEquivalentWhenHidden = true
        menu.addItem(altNewTab)
        menu.addItem(NSMenuItem(title: "Open...", action: #selector(AppDelegate.openFileAction), keyEquivalent: "o"))

        let recentItem = NSMenuItem(title: "Open recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentFilesMenu
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem(title: "Save", action: #selector(AppDelegate.saveFileAction), keyEquivalent: "s"))

        let saveAsItem = NSMenuItem(title: "Save as...", action: #selector(AppDelegate.saveFileAsAction), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Close tab", action: #selector(AppDelegate.closeTabAction), keyEquivalent: "w"))

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    func buildEditMenuItem() -> NSMenuItem {
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

        let findItem = NSMenuItem(title: "Find...", action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "f")
        findItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        findItem.target = target
        findMenu.addItem(findItem)

        let replaceItem = NSMenuItem(title: "Find and replace...", action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "f")
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        replaceItem.tag = Int(NSTextFinder.Action.showReplaceInterface.rawValue)
        replaceItem.target = target
        findMenu.addItem(replaceItem)

        let findNextItem = NSMenuItem(title: "Find next", action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "g")
        findNextItem.tag = Int(NSTextFinder.Action.nextMatch.rawValue)
        findNextItem.target = target
        findMenu.addItem(findNextItem)

        let findPrevItem = NSMenuItem(title: "Find previous", action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "G")
        findPrevItem.keyEquivalentModifierMask = [.command, .shift]
        findPrevItem.tag = Int(NSTextFinder.Action.previousMatch.rawValue)
        findPrevItem.target = target
        findMenu.addItem(findPrevItem)

        let useSelItem = NSMenuItem(title: "Use selection for find", action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "e")
        useSelItem.tag = Int(NSTextFinder.Action.setSearchString.rawValue)
        useSelItem.target = target
        findMenu.addItem(useSelItem)

        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findMenuItem.submenu = findMenu
        menu.addItem(findMenuItem)

        menu.addItem(.separator())

        let toggleChecklistItem = NSMenuItem(title: "Toggle checklist", action: #selector(AppDelegate.toggleChecklistAction), keyEquivalent: "l")
        toggleChecklistItem.keyEquivalentModifierMask = [.command, .shift]
        toggleChecklistItem.target = target
        menu.addItem(toggleChecklistItem)

        let moveUpItem = NSMenuItem(title: "Move line up", action: #selector(AppDelegate.moveLineUpAction), keyEquivalent: "")
        moveUpItem.keyEquivalent = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        moveUpItem.keyEquivalentModifierMask = [.command, .option]
        moveUpItem.target = target
        menu.addItem(moveUpItem)

        let moveDownItem = NSMenuItem(title: "Move line down", action: #selector(AppDelegate.moveLineDownAction), keyEquivalent: "")
        moveDownItem.keyEquivalent = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        moveDownItem.keyEquivalentModifierMask = [.command, .option]
        moveDownItem.target = target
        menu.addItem(moveDownItem)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    func buildViewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")

        let zoomInItem = NSMenuItem(title: "Increase font size", action: #selector(AppDelegate.increaseFontSize), keyEquivalent: "+")
        zoomInItem.target = target
        menu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Decrease font size", action: #selector(AppDelegate.decreaseFontSize), keyEquivalent: "-")
        zoomOutItem.target = target
        menu.addItem(zoomOutItem)

        let resetZoomItem = NSMenuItem(title: "Reset font size", action: #selector(AppDelegate.resetFontSize), keyEquivalent: "0")
        resetZoomItem.target = target
        menu.addItem(resetZoomItem)

        menu.addItem(.separator())

        let wordWrapItem = NSMenuItem(title: "Word wrap", action: #selector(AppDelegate.toggleWordWrap), keyEquivalent: "")
        wordWrapItem.target = target
        menu.addItem(wordWrapItem)

        let lineNumbersItem = NSMenuItem(title: "Show line numbers", action: #selector(AppDelegate.toggleLineNumbers), keyEquivalent: "")
        lineNumbersItem.target = target
        menu.addItem(lineNumbersItem)

        menu.addItem(.separator())

        let nextTabItem = NSMenuItem(title: "Next tab", action: #selector(AppDelegate.nextTabAction), keyEquivalent: "\t")
        nextTabItem.keyEquivalentModifierMask = [.control]
        nextTabItem.target = target
        menu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Previous tab", action: #selector(AppDelegate.previousTabAction), keyEquivalent: "\t")
        prevTabItem.keyEquivalentModifierMask = [.control, .shift]
        prevTabItem.target = target
        menu.addItem(prevTabItem)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
