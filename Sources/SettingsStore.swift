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

    @Published var appearanceOverride: String = "system" {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(appearanceOverride, forKey: "appearanceOverride")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var showInDock: Bool = false {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(showInDock, forKey: "showInDock")
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
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

    @Published var indentUsingSpaces: Bool = true {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(indentUsingSpaces, forKey: "indentUsingSpaces")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var tabWidth: Int = 4 {
        didSet {
            guard !isLoading else { return }
            UserDefaults.standard.set(tabWidth, forKey: "tabWidth")
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
        shortcut = UserDefaults.standard.string(forKey: shortcutKey) ?? "⌥⌥⌥ L"
        editorFontName = UserDefaults.standard.string(forKey: "editorFontName") ?? "System Mono"
        let savedSize = UserDefaults.standard.double(forKey: "editorFontSize")
        editorFontSize = savedSize > 0 ? savedSize : 14
        appearanceOverride = UserDefaults.standard.string(forKey: "appearanceOverride") ?? "system"
        showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? false
        showLineNumbers = UserDefaults.standard.bool(forKey: "showLineNumbers")
        highlightCurrentLine = UserDefaults.standard.bool(forKey: "highlightCurrentLine")
        indentUsingSpaces = UserDefaults.standard.object(forKey: "indentUsingSpaces") as? Bool ?? true
        let savedTabWidth = UserDefaults.standard.integer(forKey: "tabWidth")
        tabWidth = savedTabWidth > 0 ? savedTabWidth : 4

        if let data = UserDefaults.standard.data(forKey: shortcutKeysKey),
           let keys = try? JSONDecoder().decode(ShortcutKeys.self, from: data) {
            shortcutKeys = keys
        } else {
            shortcutKeys = ShortcutKeys(modifiers: 0, keyCode: 0, isTripleTap: true, tapModifier: "left-option")
        }
    }
}
