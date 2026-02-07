import Cocoa
import ServiceManagement

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private var isLoading = true

    @Published var launchAtLogin: Bool = false {
        didSet {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    @Published var shortcut: String = "" {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(shortcut, forKey: shortcutKey)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var shortcutKeys: ShortcutKeys? = nil {
        didSet {
            guard !isLoading else { return }
            if let keys = shortcutKeys, let data = try? JSONEncoder().encode(keys) {
                UserDefaults.standard.set(data, forKey: shortcutKeysKey)
            } else {
                UserDefaults.standard.removeObject(forKey: shortcutKeysKey)
            }
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var editorFontName: String = "System Mono" {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(editorFontName, forKey: "editorFontName")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var editorFontSize: Double = 14 {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(editorFontSize, forKey: "editorFontSize")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var highlightTheme: String = "horizon-dark" {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(highlightTheme, forKey: "highlightTheme")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var showLineNumbers: Bool = false {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(showLineNumbers, forKey: "showLineNumbers")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var highlightCurrentLine: Bool = false {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(highlightCurrentLine, forKey: "highlightCurrentLine")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    var editorFont: NSFont {
        if editorFontName == "System Mono" {
            return NSFont.monospacedSystemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
        }
        return NSFont(name: editorFontName, size: CGFloat(editorFontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
    }

    @Published var availableThemes: [String] = []

    static let availableFonts: [(name: String, displayName: String)] = {
        var fonts: [(String, String)] = [("System Mono", "System mono")]
        let monoFamilies = NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return font.isFixedPitch || family.lowercased().contains("mono") || family.lowercased().contains("code")
        }
        for family in monoFamilies.sorted() {
            fonts.append((family, family))
        }
        return fonts
    }()

    private let shortcutKey = "shortcut"
    private let shortcutKeysKey = "shortcutKeys"

    private init() {
        loadSettings()
        syncLaunchAtLoginStatus()
        isLoading = false
    }

    func syncLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func loadSettings() {
        shortcut = UserDefaults.standard.string(forKey: shortcutKey) ?? ""
        editorFontName = UserDefaults.standard.string(forKey: "editorFontName") ?? "System Mono"
        let savedSize = UserDefaults.standard.double(forKey: "editorFontSize")
        editorFontSize = savedSize > 0 ? savedSize : 14
        highlightTheme = UserDefaults.standard.string(forKey: "highlightTheme") ?? "horizon-dark"
        showLineNumbers = UserDefaults.standard.bool(forKey: "showLineNumbers")
        highlightCurrentLine = UserDefaults.standard.bool(forKey: "highlightCurrentLine")

        if let data = UserDefaults.standard.data(forKey: shortcutKeysKey),
           let keys = try? JSONDecoder().decode(ShortcutKeys.self, from: data) {
            shortcutKeys = keys
        }
    }
}
