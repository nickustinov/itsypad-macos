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
        if t.contains("<?php") {
            return Result(lang: "php", confidence: 95)
        }
        if t.contains("#!/bin/bash") || t.contains("#!/usr/bin/env bash") {
            return Result(lang: "bash", confidence: 90)
        }
        if t.contains("#!/bin/zsh") || t.contains("#!/usr/bin/env zsh") {
            return Result(lang: "zsh", confidence: 90)
        }

        // Short-snippet heuristics (highlight.js auto-detect needs ~50+ chars to be reliable)
        if t.contains("\ndef ") || t.hasPrefix("def ") { return Result(lang: "python", confidence: 15) }
        if t.hasPrefix("import ") && t.contains(":\n") { return Result(lang: "python", confidence: 15) }
        if t.hasPrefix("from ") && t.contains("import ") { return Result(lang: "python", confidence: 15) }
        if t.contains("package ") && t.contains("func ") { return Result(lang: "go", confidence: 15) }
        if t.hasPrefix("#include") || t.contains("\n#include") { return Result(lang: "cpp", confidence: 15) }
        if t.contains("console.log") || (t.contains("function ") && t.contains("=>")) {
            return Result(lang: "javascript", confidence: 15)
        }

        // Delegate to highlight.js auto-detection for longer/complex snippets
        let knownLanguages = Set(Self.allLanguages)
        if let auto = HighlightJS.shared.highlightAuto(text),
           auto.relevance >= 7,
           knownLanguages.contains(auto.language) {
            return Result(lang: auto.language, confidence: auto.relevance)
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
