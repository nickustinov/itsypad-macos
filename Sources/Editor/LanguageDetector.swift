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
    private static let autoDetectExcluded: Set<String> = ["plain", "zsh", "sql", "css", "markdown", "kotlin", "csharp"]

    /// Minimum relevance score from highlight.js auto-detect to accept a result.
    ///
    /// highlight.js relevance is an unbounded integer that accumulates as the
    /// highlighter matches language-specific keywords and modes.  Rough guide:
    ///   0–4   very low confidence, almost certainly a false positive
    ///   5–7   moderate, unreliable for short or mixed text
    ///   8+    decent confidence, multiple distinctive features matched
    ///   15+   high confidence
    ///
    /// Default threshold is 8.  Per-language overrides below for languages that
    /// need a higher (or could tolerate a lower) bar.
    private static let defaultRelevanceThreshold = 8

    private static let relevanceThreshold: [String: Int] = [
        "swift": 10,     // common English words overlap Swift keywords
    ]

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
        if let auto = Self.hljs.highlightAuto(text, subset: Self.autoDetectSubset) {
            let isProse = Self.looksLikeProse(text)
            let canonical = Self.hljsToCanonical[auto.language] ?? auto.language
            let preview = String(text.prefix(80)).replacingOccurrences(of: "\n", with: "\\n")
            NSLog("[AutoDetect] lang=%@ relevance=%d prose=%d ext=%@ text=\"%@\"",
                  canonical, auto.relevance, isProse ? 1 : 0, ext ?? "(none)", preview)
            let threshold = Self.relevanceThreshold[canonical] ?? Self.defaultRelevanceThreshold
            if auto.relevance >= threshold && !isProse {
                return Result(lang: canonical, confidence: auto.relevance)
            }
        }

        return Result(lang: "plain", confidence: 0)
    }

    /// Returns true when text is predominantly natural-language prose.
    /// Prose lines tend to have many space-separated words (8+), while code lines
    /// are short and punctuation-heavy.  If ≥ 30 % of non-empty lines are "long"
    /// (8+ words), we treat the text as prose and skip highlight.js auto-detection.
    private static func looksLikeProse(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3 else {
            NSLog("[AutoDetect] prose=NO (only %d non-empty lines, need 3+)", lines.count)
            return false
        }
        let longLines = lines.filter { $0.split(separator: " ").count >= 8 }.count
        let ratio = Double(longLines) / Double(lines.count)
        let result = ratio >= 0.3
        NSLog("[AutoDetect] prose=%@ lines=%d longLines=%d ratio=%.1f%% wordCounts=%@",
              result ? "YES" : "NO", lines.count, longLines, ratio * 100,
              lines.prefix(10).map { "\($0.split(separator: " ").count)" }.joined(separator: ","))
        return result
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
