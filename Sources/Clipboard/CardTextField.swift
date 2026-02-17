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

// MARK: - Key code to number mapping

func clipboardNumberFromKeyCode(_ keyCode: UInt16) -> Int? {
    switch keyCode {
    case 18: return 1  case 19: return 2  case 20: return 3
    case 21: return 4  case 23: return 5  case 22: return 6
    case 26: return 7  case 28: return 8  case 25: return 9
    default: return nil
    }
}

// MARK: - Shared clipboard helpers

func clipboardRelativeTime(from date: Date) -> String {
    let interval = -date.timeIntervalSinceNow
    if interval < 60 { return String(localized: "time.just_now", defaultValue: "just now") }
    if interval < 3600 { return String(localized: "time.minutes_ago", defaultValue: "\(Int(interval / 60))m ago") }
    if interval < 86400 { return String(localized: "time.hours_ago", defaultValue: "\(Int(interval / 3600))h ago") }
    let days = Int(interval / 86400)
    if days == 1 { return String(localized: "time.yesterday", defaultValue: "yesterday") }
    return String(localized: "time.days_ago", defaultValue: "\(days)d ago")
}
