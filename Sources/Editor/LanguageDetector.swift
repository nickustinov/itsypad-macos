import Foundation

struct LanguageDetector {
    static let shared = LanguageDetector()
    private init() {}

    /// Dedicated HighlightJS instance for auto-detection (separate from the shared
    /// instance used by SyntaxHighlightCoordinator, since JSContext isn't thread-safe).
    private static let hljs = HighlightJS()

    private let extensionMap: [String: String] = [
        "swift": "swift",
        "py": "python",
        "js": "javascript",
        "jsx": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "html": "html",
        "htm": "html",
        "css": "css",
        "c": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "hpp": "cpp",
        "h": "c",
        "cs": "csharp",
        "json": "json",
        "md": "markdown",
        "markdown": "markdown",
        "sh": "bash",
        "bash": "bash",
        "zsh": "zsh",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "go": "go",
        "rb": "ruby",
        "rs": "rust",
        "sql": "sql",
        "xml": "xml",
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "toml",
        "m": "objective-c",
        "mm": "objective-c",
        "php": "php",
        "ps1": "powershell",
        "txt": "plain",
    ]

    static let allLanguages: [String] = [
        "plain", "swift", "python", "javascript", "typescript", "html", "css",
        "c", "cpp", "csharp", "json", "markdown", "bash", "zsh", "java",
        "kotlin", "go", "ruby", "rust", "sql", "xml", "yaml", "toml",
        "objective-c", "php", "powershell",
    ]

    /// highlight.js names for auto-detect subset — maps back to our canonical names.
    /// Most are identical; only list exceptions here.
    private static let hljsToCanonical: [String: String] = [
        "objectivec": "objective-c",
    ]

    /// Languages excluded from auto-detect (too many false positives on plain text).
    /// These are still detected by file extension.
    private static let autoDetectExcluded: Set<String> = ["plain", "zsh", "sql", "css", "markdown"]

    /// Languages to pass as subset to highlightAuto (using highlight.js identifiers).
    private static let autoDetectSubset: [String] = {
        allLanguages.compactMap { lang in
            if autoDetectExcluded.contains(lang) { return nil }
            return hljsToCanonical.first(where: { $0.value == lang })?.key ?? lang
        }
    }()

    struct Result {
        let lang: String
        let confidence: Int
    }

    func detect(text: String, name: String?, fileURL: URL?) -> Result {
        // Extension-based detection (strong signal)
        let ext: String? = {
            if let url = fileURL { return url.pathExtension.lowercased() }
            if let name = name {
                let parts = name.split(separator: ".")
                return parts.count > 1 ? String(parts.last!).lowercased() : nil
            }
            return nil
        }()

        if let ext, let lang = extensionMap[ext] {
            return Result(lang: lang, confidence: 100)
        }

        // Delegate to highlight.js auto-detection (restricted to our supported languages)
        if let auto = Self.hljs.highlightAuto(text, subset: Self.autoDetectSubset),
           auto.relevance >= 5 {
            let canonical = Self.hljsToCanonical[auto.language] ?? auto.language
            return Result(lang: canonical, confidence: auto.relevance)
        }

        return Result(lang: "plain", confidence: 0)
    }

    func detectFromExtension(name: String) -> String? {
        let parts = name.split(separator: ".")
        guard parts.count > 1, let ext = parts.last else { return nil }
        return extensionMap[String(ext).lowercased()]
    }

    // MARK: - Highlightr language mapping

    private static let highlightrMap: [String: String] = [
        "objective-c": "objectivec",
        "zsh": "bash",
        "plain": "",
    ]

    func highlightrLanguage(for lang: String) -> String? {
        if lang == "plain" { return nil }
        return Self.highlightrMap[lang] ?? lang
    }
}
