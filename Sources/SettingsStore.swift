import Cocoa
import ServiceManagement

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private var isLoading = true
    let defaults: UserDefaults

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
            defaults.set(shortcut, forKey: shortcutKey)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var shortcutKeys: ShortcutKeys? = nil {
        didSet {
            guard !isLoading else { return }
            if let keys = shortcutKeys, let data = try? JSONEncoder().encode(keys) {
                defaults.set(data, forKey: shortcutKeysKey)
            } else {
                defaults.removeObject(forKey: shortcutKeysKey)
            }
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var editorFontName: String = "System Mono" {
        didSet {
            guard !isLoading else { return }
            defaults.set(editorFontName, forKey: "editorFontName")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var editorFontSize: Double = 14 {
        didSet {
            guard !isLoading else { return }
            defaults.set(editorFontSize, forKey: "editorFontSize")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var appearanceOverride: String = "system" {
        didSet {
            guard !isLoading else { return }
            defaults.set(appearanceOverride, forKey: "appearanceOverride")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var showInDock: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(showInDock, forKey: "showInDock")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var showInMenuBar: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(showInMenuBar, forKey: "showInMenuBar")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var showLineNumbers: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(showLineNumbers, forKey: "showLineNumbers")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var highlightCurrentLine: Bool = false {
        didSet {
            guard !isLoading else { return }
            defaults.set(highlightCurrentLine, forKey: "highlightCurrentLine")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var indentUsingSpaces: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(indentUsingSpaces, forKey: "indentUsingSpaces")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var tabWidth: Int = 4 {
        didSet {
            guard !isLoading else { return }
            defaults.set(tabWidth, forKey: "tabWidth")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var wordWrap: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(wordWrap, forKey: "wordWrap")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var clipboardEnabled: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(clipboardEnabled, forKey: "clipboardEnabled")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var clipboardShortcut: String = "" {
        didSet {
            guard !isLoading else { return }
            defaults.set(clipboardShortcut, forKey: "clipboardShortcut")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var clipboardShortcutKeys: ShortcutKeys? = nil {
        didSet {
            guard !isLoading else { return }
            if let keys = clipboardShortcutKeys, let data = try? JSONEncoder().encode(keys) {
                defaults.set(data, forKey: "clipboardShortcutKeys")
            } else {
                defaults.removeObject(forKey: "clipboardShortcutKeys")
            }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadSettings()
        syncLaunchAtLoginStatus()
        isLoading = false
    }

    func syncLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func loadSettings() {
        shortcut = defaults.string(forKey: shortcutKey) ?? "⌥⌥⌥ L"
        editorFontName = defaults.string(forKey: "editorFontName") ?? "System Mono"
        let savedSize = defaults.double(forKey: "editorFontSize")
        editorFontSize = savedSize > 0 ? savedSize : 14
        appearanceOverride = defaults.string(forKey: "appearanceOverride") ?? "system"
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        showLineNumbers = defaults.object(forKey: "showLineNumbers") as? Bool ?? true
        highlightCurrentLine = defaults.bool(forKey: "highlightCurrentLine")
        indentUsingSpaces = defaults.object(forKey: "indentUsingSpaces") as? Bool ?? true
        let savedTabWidth = defaults.integer(forKey: "tabWidth")
        tabWidth = savedTabWidth > 0 ? savedTabWidth : 4
        wordWrap = defaults.object(forKey: "wordWrap") as? Bool ?? true
        clipboardEnabled = defaults.object(forKey: "clipboardEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: shortcutKeysKey),
           let keys = try? JSONDecoder().decode(ShortcutKeys.self, from: data) {
            shortcutKeys = keys
        } else {
            shortcutKeys = ShortcutKeys(modifiers: 0, keyCode: 0, isTripleTap: true, tapModifier: "left-option")
        }

        clipboardShortcut = defaults.string(forKey: "clipboardShortcut") ?? ""
        if let data = defaults.data(forKey: "clipboardShortcutKeys"),
           let keys = try? JSONDecoder().decode(ShortcutKeys.self, from: data) {
            clipboardShortcutKeys = keys
        }
    }
}
