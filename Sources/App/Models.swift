import Cocoa

let appVersion: String = {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    return "\(version) (\(build))"
}()
let githubURL = "https://github.com/nickustinov/itsypad-macos"

struct ShortcutKeys: Codable, Equatable {
    var modifiers: UInt
    var keyCode: UInt16
    var isTripleTap: Bool
    var tapModifier: String?
}
