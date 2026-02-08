import AppKit

@Observable
public final class BonsplitTheme: @unchecked Sendable {
    public static let shared = BonsplitTheme()

    public var barBackground: NSColor?
    public var activeTabBackground: NSColor?
    public var separator: NSColor?

    private init() {}
}
