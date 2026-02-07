import Cocoa

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
let githubURL = "https://github.com/nickustinov/itsypad-macos"

struct ShortcutKeys: Codable, Equatable {
    var modifiers: UInt
    var keyCode: UInt16
    var isTripleTap: Bool
    var tapModifier: String?
}
