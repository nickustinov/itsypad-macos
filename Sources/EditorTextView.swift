import AppKit

final class EditorTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    var onTextChange: ((String) -> Void)?

    // MARK: - Word wrap (CotEditor approach)

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

    // MARK: - Reject Bonsplit tab drags

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if isTabTransferDrag(sender) { return [] }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if isTabTransferDrag(sender) { return false }
        return super.performDragOperation(sender)
    }

    private func isTabTransferDrag(_ sender: any NSDraggingInfo) -> Bool {
        guard let str = sender.draggingPasteboard.string(forType: .string) else { return false }
        return str.contains("\"sourcePaneId\"")
    }

    // MARK: - Typing helpers

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let s = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        // Auto-indent on newline
        if s == "\n" {
            let ns = (string as NSString)
            let sel = selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let currentLine = ns.substring(with: NSRange(
                location: lineRange.location,
                length: max(0, sel.location - lineRange.location)
            ))
            let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
            super.insertText("\n" + indent, replacementRange: replacementRange)
            return
        }

        // Tab key — indent selection or insert indent
        if s == "\t" {
            let sel = selectedRange()
            if sel.length > 0 {
                indentSelectedLines()
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
        let store = SettingsStore.shared
        guard store.indentUsingSpaces else {
            super.deleteBackward(sender)
            return
        }

        let sel = selectedRange()
        guard sel.length == 0, sel.location > 0 else {
            super.deleteBackward(sender)
            return
        }

        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let columnOffset = sel.location - lineRange.location
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

    // MARK: - Duplicate line (Cmd+D)

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "d" {
            duplicateLine()
            return
        }
        super.keyDown(with: event)
    }

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
