import Foundation

/// Represents a tab's metadata (read-only snapshot for library consumers)
public struct Tab: Identifiable, Hashable, Sendable {
    public let id: TabID
    public let title: String
    public let icon: String?
    public let isDirty: Bool
    public let isClosable: Bool
    public let isPinned: Bool

    public init(id: TabID = TabID(), title: String, icon: String? = nil, isDirty: Bool = false, isClosable: Bool = true, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isDirty = isDirty
        self.isClosable = isClosable
        self.isPinned = isPinned
    }

    internal init(from tabItem: TabItem) {
        self.id = TabID(id: tabItem.id)
        self.title = tabItem.title
        self.icon = tabItem.icon
        self.isDirty = tabItem.isDirty
        self.isClosable = tabItem.isClosable
        self.isPinned = tabItem.isPinned
    }
}
