import Foundation

enum MultiCursorHelpers {
    static func isWordChar(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
    }

    static func wordRange(at index: Int, in text: String) -> NSRange? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        guard index >= 0, index <= ns.length else { return nil }

        var startIndex = index
        if startIndex == ns.length {
            startIndex -= 1
        } else if !isWordCharacter(at: startIndex, in: ns) {
            return nil
        }

        guard isWordCharacter(at: startIndex, in: ns) else { return nil }

        var left = startIndex
        while left > 0, isWordCharacter(at: left - 1, in: ns) {
            left -= 1
        }

        var right = startIndex + 1
        while right < ns.length, isWordCharacter(at: right, in: ns) {
            right += 1
        }

        return NSRange(location: left, length: right - left)
    }

    static func nextWholeWordMatch(of word: String, after index: Int, in text: String) -> NSRange? {
        let ns = text as NSString
        guard ns.length > 0, !word.isEmpty else { return nil }

        let safeStart = min(max(index, 0), ns.length)
        guard safeStart < ns.length else { return nil }

        let startAt = safeStart
        var searchStart = startAt

        while searchStart < ns.length {
            let searchRange = NSRange(location: searchStart, length: ns.length - searchStart)
            let found = ns.range(of: word, options: [], range: searchRange)
            guard found.location != NSNotFound else { return nil }

            if isWholeWordMatch(wordRange: found, in: ns) {
                return found
            }

            searchStart = found.location + max(found.length, 1)
        }
        return nil
    }

    static func splitSelectionIntoLineCursors(selectedRanges: [NSRange], in text: String) -> [NSRange] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }

        var lineCursors: [NSRange] = []

        for range in selectedRanges {
            let clampedLength = max(0, min(range.length, ns.length - min(range.location, ns.length)))
            guard clampedLength > 0 else { continue }

            let start = min(range.location, ns.length)
            let end = min(range.location + clampedLength, ns.length)

            let startLine = ns.lineRange(for: NSRange(location: start, length: 0))
            let endLine = ns.lineRange(for: NSRange(location: max(end - 1, 0), length: 0))
            if startLine.location == endLine.location {
                continue
            }

            var currentLine = startLine
            while true {
                lineCursors.append(NSRange(location: currentLine.location, length: 0))

                if currentLine.location == endLine.location { break }

                let nextLineStart = currentLine.location + currentLine.length
                guard nextLineStart < ns.length else { break }
                currentLine = ns.lineRange(for: NSRange(location: nextLineStart, length: 0))
            }
        }

        return lineCursors
    }

    static func addCursorToAdjacentLine(from selectedRanges: [NSRange], direction: MoveDirection, in text: String) -> [NSRange] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }

        var result: [NSRange] = []

        for range in selectedRanges {
            let location = min(max(range.location, 0), ns.length)
            let currentLine = ns.lineRange(for: NSRange(location: location, length: 0))
            let columnOffset = location - currentLine.location

            let targetLine: NSRange
            switch direction {
            case .up:
                guard currentLine.location > 0 else { continue }
                targetLine = ns.lineRange(for: NSRange(location: currentLine.location - 1, length: 0))
            case .down:
                let nextLineStart = currentLine.location + currentLine.length
                guard nextLineStart < ns.length else { continue }
                targetLine = ns.lineRange(for: NSRange(location: nextLineStart, length: 0))
            }

            let lineText = ns.substring(with: targetLine)
            let lineContentLength = (lineText as NSString).length - (lineText.hasSuffix("\n") ? 1 : 0)
            let clampedColumn = min(columnOffset, max(0, lineContentLength))
            result.append(NSRange(location: targetLine.location + clampedColumn, length: 0))
        }

        return result
    }

    private static func isWholeWordMatch(wordRange: NSRange, in text: NSString) -> Bool {
        let beforeIndex = wordRange.location
        let afterIndex = wordRange.location + wordRange.length

        let beforeValid = beforeIndex == 0 || !isWordCharacter(at: beforeIndex - 1, in: text)
        let afterValid = afterIndex == text.length || !isWordCharacter(at: afterIndex, in: text)
        return beforeValid && afterValid
    }

    private static func isWordCharacter(at index: Int, in text: NSString) -> Bool {
        guard index >= 0, index < text.length else { return false }
        guard let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
        return isWordChar(scalar)
    }
}
