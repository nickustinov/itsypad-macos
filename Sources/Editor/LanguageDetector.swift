import CodeEditLanguages
import Foundation

struct LanguageDetector {
    static let shared = LanguageDetector()
    private init() {}

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
        "ps1": "powershell",
        "txt": "plain",
    ]

    static let allLanguages: [String] = [
        "plain", "swift", "python", "javascript", "typescript", "html", "css",
        "c", "cpp", "csharp", "json", "markdown", "bash", "zsh", "java",
        "kotlin", "go", "ruby", "rust", "sql", "xml", "yaml", "toml",
        "objective-c", "powershell",
    ]

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

        // Content-based heuristic
        let t = text.lowercased()

        // Strong early returns
        if t.contains("import swiftui") || t.contains("import appkit") || t.contains("import uikit") {
            return Result(lang: "swift", confidence: 95)
        }
        if t.contains("@main") && (t.contains("struct ") || t.contains("class ")) {
            return Result(lang: "swift", confidence: 90)
        }
        if t.contains("@published") || t.contains("@stateobject") || t.contains("guard ") || t.contains(" if let ") {
            return Result(lang: "swift", confidence: 85)
        }

        // Quick checks
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, (first == "{" || first == "["), t.contains(":") {
            return Result(lang: "json", confidence: 80)
        }
        if t.contains("<html") || t.contains("<!doctype html") {
            return Result(lang: "html", confidence: 85)
        }
        if t.contains("#!/bin/bash") || t.contains("#!/usr/bin/env bash") {
            return Result(lang: "bash", confidence: 90)
        }
        if t.contains("#!/bin/zsh") || t.contains("#!/usr/bin/env zsh") {
            return Result(lang: "zsh", confidence: 90)
        }

        // Scoring
        var scores: [String: Int] = [:]

        func bump(_ key: String, _ amount: Int) { scores[key, default: 0] += amount }

        // Swift
        if t.contains("func ") { bump("swift", 5) }
        if t.contains("let ") || t.contains("var ") { bump("swift", 4) }
        if t.contains("->") { bump("swift", 4) }
        if t.contains("struct ") && t.contains(": view") { bump("swift", 14) }

        // Python
        if t.contains("\ndef ") || t.hasPrefix("def ") { bump("python", 15) }
        if t.contains("import ") && t.contains(":\n") { bump("python", 8) }

        // JavaScript
        if t.contains("function ") || t.contains("=>") || t.contains("console.log") { bump("javascript", 15) }

        // C/C++
        if t.contains("#include") || t.contains("std::") { bump("cpp", 20) }

        // CSS
        if t.contains("{") && t.contains("}") && t.contains(":") && t.contains(";") && !t.contains("func ") {
            bump("css", 8)
        }

        // Markdown
        if t.contains("\n# ") || t.hasPrefix("# ") { bump("markdown", 8) }

        // C#
        if t.contains("using system") || t.contains("namespace ") { bump("csharp", 15) }

        // Rust
        if t.contains("fn ") && t.contains("let mut ") { bump("rust", 15) }

        // Go
        if t.contains("package ") && t.contains("func ") { bump("go", 15) }
        if t.contains(":=") { bump("go", 10) }
        if t.contains("fmt.") { bump("go", 8) }
        if t.contains("make(") { bump("go", 5) }

        // Ruby
        if t.contains("\ndef ") && t.contains("\nend") { bump("ruby", 12) }

        let sorted = scores.sorted { $0.value > $1.value }
        if let top = sorted.first, top.value > 0 {
            let second = sorted.dropFirst().first?.value ?? 0
            return Result(lang: top.key, confidence: top.value - second)
        }

        return Result(lang: "plain", confidence: 0)
    }

    func detectFromExtension(name: String) -> String? {
        let parts = name.split(separator: ".")
        guard parts.count > 1, let ext = parts.last else { return nil }
        return extensionMap[String(ext).lowercased()]
    }

    // MARK: - Tree-sitter language mapping

    private static let codeLanguageMap: [String: CodeLanguage] = [
        "swift": .swift, "python": .python, "javascript": .javascript,
        "typescript": .typescript, "html": .html, "css": .css,
        "c": .c, "cpp": .cpp, "csharp": .cSharp,
        "json": .json, "markdown": .markdown, "bash": .bash,
        "zsh": .bash, "java": .java, "kotlin": .kotlin,
        "go": .go, "ruby": .ruby, "rust": .rust,
        "sql": .sql, "xml": .html, "yaml": .yaml,
        "toml": .toml, "objective-c": .objc, "powershell": .default,
        "plain": .default,
    ]

    func codeLanguage(for lang: String) -> CodeLanguage {
        Self.codeLanguageMap[lang] ?? .default
    }
}
