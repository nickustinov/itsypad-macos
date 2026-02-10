import AppKit

final class EditorTextView: NSTextView {
    static let fileDropNotification = Notification.Name("editorTextViewFileDrop")
    static let didReceiveClickNotification = Notification.Name("editorTextViewDidReceiveClick")

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    var onTextChange: ((String) -> Void)?
    var isActiveTab: Bool = true

    override func mouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: Self.didReceiveClickNotification, object: self)

        // Check if click lands on a checkbox region
        if SettingsStore.shared.checklistsEnabled, handleCheckboxClick(event: event) { return }

        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - Word wrap

    var wrapsLines: Bool {
        get { textContainer?.widthTracksTextView ?? false }
        set {
            guard newValue != wrapsLines,
                  let textContainer,
                  let scrollView = enclosingScrollView else { return }

            let visibleRange = self.visibleRange

            scrollView.hasHorizontalScroller = !newValue
            isHorizontallyResizable = !newValue

            if newValue {
                let clipWidth = scrollView.contentView.bounds.width
                frame.size.width = clipWidth
                textContainer.size.width = clipWidth
                textContainer.widthTracksTextView = true
            } else {
                textContainer.widthTracksTextView = false
                textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }

            // Reset horizontal scroll and force layout recalculation
            let clipOrigin = scrollView.contentView.bounds.origin
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clipOrigin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            needsLayout = true
            needsDisplay = true

            if let visibleRange {
                scrollRangeToVisible(visibleRange)
            }
        }
    }

    private var visibleRange: NSRange? {
        guard let layoutManager, let textContainer else { return nil }
        let visibleRect = self.visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRectWithoutAdditionalLayout: visibleRect, in: textContainer)
        return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    }

    // MARK: - File drop from Finder

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isFileURLDrag(sender) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isFileURLDrag(sender) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []
        if !urls.isEmpty {
            NotificationCenter.default.post(name: Self.fileDropNotification, object: nil, userInfo: ["urls": urls])
        }
        return !urls.isEmpty
    }

    private func isFileURLDrag(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }

    // MARK: - Layout fix for word-wrapped lines

    override func didChangeText() {
        super.didChangeText()
        if wrapsLines {
            layoutManager?.ensureLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length))
            needsDisplay = true
        }
    }

    // MARK: - Typing helpers

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let s = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        // Auto-indent on newline (list-aware)
        if s == "\n" {
            let ns = (string as NSString)
            let sel = selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let currentLine = ns.substring(with: NSRange(
                location: lineRange.location,
                length: max(0, sel.location - lineRange.location)
            ))

            if let match = ListHelper.parseLine(currentLine), ListHelper.isKindEnabled(match.kind) {
                if ListHelper.isEmptyItem(currentLine, match: match) {
                    // Empty list item — remove prefix, exit list mode
                    let prefixRange = NSRange(location: lineRange.location, length: currentLine.count)
                    if shouldChangeText(in: prefixRange, replacementString: "") {
                        textStorage?.replaceCharacters(in: prefixRange, with: "")
                        didChangeText()
                        setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    }
                } else {
                    // Continue list with next prefix
                    let next = ListHelper.nextPrefix(for: match)
                    super.insertText("\n" + next, replacementRange: replacementRange)
                }
                return
            }

            let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
            super.insertText("\n" + indent, replacementRange: replacementRange)
            return
        }

        // Tab key — indent selection or indent list line
        if s == "\t" {
            let sel = selectedRange()
            if sel.length > 0 {
                indentSelectedLines()
                return
            }
            // On a list line, indent the whole line instead of inserting a tab
            let ns = string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let lineText = ns.substring(with: lineRange)
            let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
            if let listMatch = ListHelper.parseLine(cleanLine), ListHelper.isKindEnabled(listMatch.kind) {
                let store2 = SettingsStore.shared
                let indent = store2.indentUsingSpaces ? String(repeating: " ", count: store2.tabWidth) : "\t"
                let insertRange = NSRange(location: lineRange.location, length: 0)
                if shouldChangeText(in: insertRange, replacementString: indent) {
                    textStorage?.replaceCharacters(in: insertRange, with: indent)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location + indent.count, length: 0))
                }
                return
            }
            let store = SettingsStore.shared
            if store.indentUsingSpaces {
                let spaces = String(repeating: " ", count: store.tabWidth)
                super.insertText(spaces, replacementRange: replacementRange)
            } else {
                super.insertText("\t", replacementRange: replacementRange)
            }
            return
        }

        // Auto-close bracket pairs
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
        if let closing = pairs[s] {
            let sel = selectedRange()
            super.insertText(s + closing, replacementRange: replacementRange)
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length == 0, sel.location > 0 else {
            super.deleteBackward(sender)
            return
        }

        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let columnOffset = sel.location - lineRange.location

        // Check if cursor is at content start of a list item — remove the prefix
        let lineText = ns.substring(with: lineRange)
        let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
        if let match = ListHelper.parseLine(cleanLine), ListHelper.isKindEnabled(match.kind), columnOffset == match.contentStart {
            let prefixRange = NSRange(location: lineRange.location, length: match.contentStart)
            if shouldChangeText(in: prefixRange, replacementString: match.indent) {
                textStorage?.replaceCharacters(in: prefixRange, with: match.indent)
                didChangeText()
                setSelectedRange(NSRange(location: lineRange.location + match.indent.count, length: 0))
            }
            return
        }

        let store = SettingsStore.shared
        guard store.indentUsingSpaces else {
            super.deleteBackward(sender)
            return
        }

        let textBeforeCursor = ns.substring(with: NSRange(location: lineRange.location, length: columnOffset))

        // Only act if everything before cursor on this line is spaces
        guard !textBeforeCursor.isEmpty, textBeforeCursor.allSatisfy({ $0 == " " }) else {
            super.deleteBackward(sender)
            return
        }

        let width = store.tabWidth
        let toDelete = ((columnOffset - 1) % width) + 1
        let deleteRange = NSRange(location: sel.location - toDelete, length: toDelete)
        if shouldChangeText(in: deleteRange, replacementString: "") {
            textStorage?.replaceCharacters(in: deleteRange, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: deleteRange.location, length: 0))
        }
    }

    // MARK: - Block indent / unindent

    override func insertBacktab(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0 {
            unindentSelectedLines()
        } else {
            unindentCurrentLine()
        }
    }

    private func indentSelectedLines() {
        let store = SettingsStore.shared
        let indent = store.indentUsingSpaces ? String(repeating: " ", count: store.tabWidth) : "\t"
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)

        var newText = ""
        var addedChars = 0
        ns.substring(with: lineRange).enumerateLines { line, _ in
            newText += indent + line + "\n"
            addedChars += indent.count
        }
        // Remove trailing newline if original didn't end with one
        if lineRange.location + lineRange.length <= ns.length,
           !ns.substring(with: lineRange).hasSuffix("\n") {
            newText = String(newText.dropLast())
        }

        if shouldChangeText(in: lineRange, replacementString: newText) {
            textStorage?.replaceCharacters(in: lineRange, with: newText)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: newText.count))
        }
    }

    private func unindentCurrentLine() {
        let store = SettingsStore.shared
        let width = store.tabWidth
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = ns.substring(with: lineRange)

        let toRemove: Int
        if line.hasPrefix("\t") {
            toRemove = 1
        } else {
            let spaces = line.prefix { $0 == " " }
            toRemove = min(spaces.count, width)
        }
        guard toRemove > 0 else { return }

        let removeRange = NSRange(location: lineRange.location, length: toRemove)
        if shouldChangeText(in: removeRange, replacementString: "") {
            textStorage?.replaceCharacters(in: removeRange, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: max(lineRange.location, sel.location - toRemove), length: 0))
        }
    }

    private func unindentSelectedLines() {
        let store = SettingsStore.shared
        let width = store.tabWidth
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)

        var newText = ""
        ns.substring(with: lineRange).enumerateLines { line, _ in
            if line.hasPrefix("\t") {
                newText += String(line.dropFirst()) + "\n"
            } else {
                let spaces = line.prefix { $0 == " " }
                let toRemove = min(spaces.count, width)
                newText += String(line.dropFirst(toRemove)) + "\n"
            }
        }
        if lineRange.location + lineRange.length <= ns.length,
           !ns.substring(with: lineRange).hasSuffix("\n") {
            newText = String(newText.dropLast())
        }

        if shouldChangeText(in: lineRange, replacementString: newText) {
            textStorage?.replaceCharacters(in: lineRange, with: newText)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: newText.count))
        }
    }

    // MARK: - Fn+Up / Fn+Down: move cursor, not just scroll

    override func scrollPageDown(_ sender: Any?) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let pageHeight = clip.bounds.height
        let newY = min(clip.bounds.origin.y + pageHeight, frame.height - pageHeight)
        clip.scroll(to: NSPoint(x: 0, y: max(0, newY)))
        scrollView.reflectScrolledClipView(clip)
        let cursorY = clip.bounds.origin.y + textContainerOrigin.y
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: NSPoint(x: textContainerOrigin.x, y: cursorY)), length: 0))
    }

    override func scrollPageUp(_ sender: Any?) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let pageHeight = clip.bounds.height
        let newY = max(clip.bounds.origin.y - pageHeight, 0)
        clip.scroll(to: NSPoint(x: 0, y: newY))
        scrollView.reflectScrolledClipView(clip)
        let cursorY = clip.bounds.origin.y + textContainerOrigin.y
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: NSPoint(x: textContainerOrigin.x, y: cursorY)), length: 0))
    }

    // MARK: - Key commands

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""

        // Cmd+D — duplicate line
        if mods == .command, key == "d" {
            duplicateLine()
            return
        }

        // Cmd+Return — toggle checkbox
        if mods == .command, event.keyCode == 36, SettingsStore.shared.checklistsEnabled {
            toggleCheckbox()
            return
        }

        // Cmd+Shift+L — toggle checklist
        if mods == [.command, .shift], key.lowercased() == "l", SettingsStore.shared.checklistsEnabled {
            toggleChecklist()
            return
        }

        // Cmd+Option+Up — move line up
        if mods == [.command, .option], event.keyCode == 126 {
            moveLine(.up)
            return
        }

        // Cmd+Option+Down — move line down
        if mods == [.command, .option], event.keyCode == 125 {
            moveLine(.down)
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - List helpers

    private func handleCheckboxClick(event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        let ns = string as NSString
        guard charIndex < ns.length else { return false }

        let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineText = ns.substring(with: lineRange)
        let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

        guard let match = ListHelper.parseLine(cleanLine) else { return false }
        guard match.kind == .unchecked || match.kind == .checked else { return false }

        // Check if click is in the bracket region "[ ]" or "[x]"
        let bracketStart = lineRange.location + match.contentStart - 4 // "[ ] " → bracket starts 4 chars before content
        let bracketEnd = bracketStart + 3 // 3 chars: "[", " "/" x", "]"
        guard charIndex >= bracketStart && charIndex < bracketEnd else { return false }

        let toggled = ListHelper.toggleCheckbox(in: cleanLine)
        let replaceRange = NSRange(location: lineRange.location, length: cleanLine.count)
        if shouldChangeText(in: replaceRange, replacementString: toggled) {
            textStorage?.replaceCharacters(in: replaceRange, with: toggled)
            didChangeText()
        }
        return true
    }

    private func toggleCheckbox() {
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText = ns.substring(with: lineRange)
        let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

        let toggled = ListHelper.toggleCheckbox(in: cleanLine)
        guard toggled != cleanLine else { return }

        let replaceRange = NSRange(location: lineRange.location, length: cleanLine.count)
        if shouldChangeText(in: replaceRange, replacementString: toggled) {
            textStorage?.replaceCharacters(in: replaceRange, with: toggled)
            didChangeText()
            let safeLoc = min(sel.location, lineRange.location + toggled.count)
            setSelectedRange(NSRange(location: safeLoc, length: 0))
        }
    }

    func toggleChecklist() {
        guard SettingsStore.shared.checklistsEnabled else { return }
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)

        var newLines: [String] = []
        let blockText = ns.substring(with: lineRange)
        blockText.enumerateLines { line, _ in
            newLines.append(ListHelper.toggleChecklist(line: line))
        }

        var newText = newLines.joined(separator: "\n")
        if blockText.hasSuffix("\n") { newText += "\n" }

        if shouldChangeText(in: lineRange, replacementString: newText) {
            textStorage?.replaceCharacters(in: lineRange, with: newText)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: newText.count - (blockText.hasSuffix("\n") ? 1 : 0)))
        }
    }

    func moveLine(_ direction: MoveDirection) {
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))

        guard let result = ListHelper.swapLines(string, lineRange: lineRange, direction: direction) else { return }

        let fullRange = NSRange(location: 0, length: ns.length)
        if shouldChangeText(in: fullRange, replacementString: result.newText) {
            textStorage?.replaceCharacters(in: fullRange, with: result.newText)
            didChangeText()
            let cursorOffset = sel.location - lineRange.location
            setSelectedRange(NSRange(location: result.newSelection.location + cursorOffset, length: 0))
        }
    }

    // MARK: - Duplicate line (Cmd+D)

    private func duplicateLine() {
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)
        let lineText = ns.substring(with: lineRange)

        let insertAt: Int
        let insertion: String
        if lineText.hasSuffix("\n") {
            insertAt = lineRange.location + lineRange.length
            insertion = lineText
        } else {
            insertAt = lineRange.location + lineRange.length
            insertion = "\n" + lineText
        }

        let insertRange = NSRange(location: insertAt, length: 0)
        if shouldChangeText(in: insertRange, replacementString: insertion) {
            textStorage?.replaceCharacters(in: insertRange, with: insertion)
            didChangeText()
            let newCursorPos = sel.location + insertion.count
            setSelectedRange(NSRange(location: newCursorPos, length: sel.length))
        }
    }
}
