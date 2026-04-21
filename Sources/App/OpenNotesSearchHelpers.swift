import Foundation

enum OpenNotesSearchHelpers {
    static func matches(_ tab: TabData, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        let haystack = "\(tab.name)\n\(tab.content)"
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func filteredTabs(_ tabs: [TabData], query: String) -> [TabData] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tabs
        }
        return tabs.filter { matches($0, query: query) }
    }
}
