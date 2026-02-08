import Foundation

/// A menu item for tab context menus
public struct TabContextMenuItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let icon: String?
    public let isEnabled: Bool
    public let action: () -> Void

    public init(title: String, icon: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }
}
