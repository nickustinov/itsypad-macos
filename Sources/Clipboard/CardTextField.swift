import Cocoa

// MARK: - Non-interactive text field (prevents I-beam cursor from NSTextFieldCell)

class CardTextField: NSTextField {
    override func resetCursorRects() {
        discardCursorRects()
    }

    convenience init(label string: String) {
        self.init(frame: .zero)
        stringValue = string
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
    }
}

// MARK: - Shared clipboard helpers

func clipboardRelativeTime(from date: Date) -> String {
    let interval = -date.timeIntervalSinceNow
    if interval < 60 { return "just now" }
    if interval < 3600 { return "\(Int(interval / 60))m ago" }
    if interval < 86400 { return "\(Int(interval / 3600))h ago" }
    let days = Int(interval / 86400)
    if days == 1 { return "yesterday" }
    return "\(days)d ago"
}
