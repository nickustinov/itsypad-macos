import Foundation

enum ListKind: Equatable {
    case bullet(Character)   // '-' or '*'
    case ordered(Int)        // the number
    case unchecked           // - [ ]
    case checked             // - [x]
}

struct ListMatch: Equatable {
    let indent: String       // leading whitespace
    let prefix: String       // marker text: "- ", "1. ", "- [ ] ", "- [x] "
    let kind: ListKind
    let contentStart: Int    // char offset from line start where content begins
}

enum MoveDirection {
    case up, down
}

enum ListHelper {

    static func isKindEnabled(_ kind: ListKind) -> Bool {
        let store = SettingsStore.shared
        switch kind {
        case .bullet: return store.bulletListsEnabled
        case .ordered: return store.numberedListsEnabled
        case .unchecked, .checked: return store.checklistsEnabled
        }
    }

    // MARK: - Regex patterns (compiled once)

    private static let bulletRegex = try! NSRegularExpression(
        pattern: "^([ \\t]*)([-*]) (\\[[ x]\\] )?",
        options: .anchorsMatchLines
    )

    private static let orderedRegex = try! NSRegularExpression(
        pattern: "^([ \\t]*)(\\d+)\\. ",
        options: .anchorsMatchLines
    )

    // MARK: - Parse

    static func parseLine(_ line: String) -> ListMatch? {
        let ns = line as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Try bullet/checkbox first
        if let m = bulletRegex.firstMatch(in: line, range: fullRange) {
            let indent = ns.substring(with: m.range(at: 1))
            let marker = ns.substring(with: m.range(at: 2)).first!
            let checkboxRange = m.range(at: 3)

            if checkboxRange.location != NSNotFound {
                let checkbox = ns.substring(with: checkboxRange)
                let kind: ListKind = checkbox.hasPrefix("[x]") ? .checked : .unchecked
                let prefix = "\(marker) \(checkbox)"
                return ListMatch(
                    indent: indent,
                    prefix: prefix,
                    kind: kind,
                    contentStart: indent.count + prefix.count
                )
            } else {
                let prefix = "\(marker) "
                return ListMatch(
                    indent: indent,
                    prefix: prefix,
                    kind: .bullet(marker),
                    contentStart: indent.count + prefix.count
                )
            }
        }

        // Try ordered
        if let m = orderedRegex.firstMatch(in: line, range: fullRange) {
            let indent = ns.substring(with: m.range(at: 1))
            let numStr = ns.substring(with: m.range(at: 2))
            guard let num = Int(numStr) else { return nil }
            let prefix = "\(numStr). "
            return ListMatch(
                indent: indent,
                prefix: prefix,
                kind: .ordered(num),
                contentStart: indent.count + prefix.count
            )
        }

        return nil
    }

    // MARK: - Next prefix

    static func nextPrefix(for match: ListMatch) -> String {
        let marker: String
        switch match.kind {
        case .bullet(let ch):
            marker = "\(ch) "
        case .ordered(let n):
            marker = "\(n + 1). "
        case .unchecked, .checked:
            marker = "- [ ] "
        }
        return match.indent + marker
    }

    // MARK: - Empty item check

    static func isEmptyItem(_ line: String, match: ListMatch) -> Bool {
        line.count <= match.contentStart
    }

    // MARK: - Toggle checkbox

    static func toggleCheckbox(in line: String) -> String {
        guard let match = parseLine(line) else { return line }
        switch match.kind {
        case .unchecked:
            let ns = line as NSString
            let bracketStart = match.contentStart - 4 // "[ ] " → bracket at -4
            return ns.replacingCharacters(
                in: NSRange(location: bracketStart, length: 3),
                with: "[x]"
            )
        case .checked:
            let ns = line as NSString
            let bracketStart = match.contentStart - 4
            return ns.replacingCharacters(
                in: NSRange(location: bracketStart, length: 3),
                with: "[ ]"
            )
        default:
            return line
        }
    }

    // MARK: - Toggle checklist

    static func toggleChecklist(line: String) -> String {
        guard let match = parseLine(line) else {
            // Plain text → checklist
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let content = line.dropFirst(indent.count)
            return indent + "- [ ] " + content
        }

        switch match.kind {
        case .unchecked, .checked:
            // Checklist → plain (remove indent + prefix)
            let content = String(line.dropFirst(match.contentStart))
            return match.indent + content
        case .bullet:
            // Bullet → checklist
            let content = String(line.dropFirst(match.contentStart))
            return match.indent + "- [ ] " + content
        case .ordered:
            // Ordered → checklist
            let content = String(line.dropFirst(match.contentStart))
            return match.indent + "- [ ] " + content
        }
    }

    // MARK: - Swap lines

    static func swapLines(
        _ text: String,
        lineRange: NSRange,
        direction: MoveDirection
    ) -> (newText: String, newSelection: NSRange)? {
        let ns = text as NSString
        let totalLength = ns.length

        switch direction {
        case .down:
            let lineEnd = lineRange.location + lineRange.length
            guard lineEnd < totalLength else { return nil }
            let nextLineRange = ns.lineRange(for: NSRange(location: lineEnd, length: 0))

            var currentLine = ns.substring(with: lineRange)
            var nextLine = ns.substring(with: nextLineRange)

            // Handle swapping when next line has no trailing newline (last line)
            if !nextLine.hasSuffix("\n") && currentLine.hasSuffix("\n") {
                currentLine = String(currentLine.dropLast())
                nextLine = nextLine + "\n"
            }

            let combined = nextLine + currentLine
            let replaceRange = NSRange(
                location: lineRange.location,
                length: lineRange.length + nextLineRange.length
            )
            var result = ns.replacingCharacters(in: replaceRange, with: combined)
            // Trim if we added a trailing newline that wasn't there before
            if !text.hasSuffix("\n") && result.hasSuffix("\n") {
                result = String(result.dropLast())
            }
            let newLocation = lineRange.location + nextLine.count
            return (result, NSRange(location: newLocation, length: lineRange.length))

        case .up:
            guard lineRange.location > 0 else { return nil }
            let prevLineRange = ns.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))

            var prevLine = ns.substring(with: prevLineRange)
            var currentLine = ns.substring(with: lineRange)

            // Handle swapping when current line has no trailing newline (last line)
            if !currentLine.hasSuffix("\n") && prevLine.hasSuffix("\n") {
                currentLine = currentLine + "\n"
                prevLine = String(prevLine.dropLast())
            }

            let combined = currentLine + prevLine
            let replaceRange = NSRange(
                location: prevLineRange.location,
                length: prevLineRange.length + lineRange.length
            )
            var result = ns.replacingCharacters(in: replaceRange, with: combined)
            if !text.hasSuffix("\n") && result.hasSuffix("\n") {
                result = String(result.dropLast())
            }
            let newLocation = prevLineRange.location
            return (result, NSRange(location: newLocation, length: lineRange.length))
        }
    }
}
