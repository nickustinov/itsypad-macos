import AppKit
import JavaScriptCore

class MarkdownRenderer {
    static let shared = MarkdownRenderer()

    private var context: JSContext?
    private var didLoad = false

    private static let appBundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }()

    init() {}

    private func ensureLoaded() -> JSContext? {
        if didLoad { return context }
        didLoad = true

        guard let ctx = JSContext() else { return nil }

        // Load marked.min.js
        guard let markedPath = Self.appBundle.path(forResource: "marked.min", ofType: "js"),
              let markedSrc = try? String(contentsOfFile: markedPath) else { return nil }
        ctx.evaluateScript(markedSrc)

        // Load highlight.min.js for code block highlighting
        if let hljsPath = Self.appBundle.path(forResource: "highlight.min", ofType: "js"),
           let hljsSrc = try? String(contentsOfFile: hljsPath) {
            ctx.evaluateScript(hljsSrc)
        }

        context = ctx
        return ctx
    }

    func render(markdown: String, theme: EditorTheme) -> String {
        guard let ctx = ensureLoaded() else {
            return wrapHTML(body: "<p>Failed to load markdown renderer</p>", syntaxCSS: "", theme: theme)
        }

        // Escape markdown for JavaScript string
        let escaped = stripFrontmatter(markdown)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let result = ctx.evaluateScript("marked.parse(`\(escaped)`)")
        let html = result?.toString() ?? ""

        // Load the current syntax CSS for code blocks
        let syntaxCSS = loadSyntaxCSS(isDark: theme.isDark)

        // Apply highlight.js to code blocks client-side via post-processing
        let highlightedHTML = highlightCodeBlocks(html: html, ctx: ctx)

        return wrapHTML(body: highlightedHTML, syntaxCSS: syntaxCSS, theme: theme)
    }

    private func highlightCodeBlocks(html: String, ctx: JSContext) -> String {
        // Use JS to parse and highlight code blocks
        let escaped = html
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let script = """
        (function() {
            var div = `\(escaped)`;
            // Match <code class="language-xxx">...</code> blocks
            return div.replace(/<code class="language-([^"]+)">([\\s\\S]*?)<\\/code>/g, function(match, lang, code) {
                // Decode HTML entities for highlight.js input
                var decoded = code.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
                try {
                    if (typeof hljs !== 'undefined' && hljs.getLanguage(lang)) {
                        var result = hljs.highlight(decoded, {language: lang, ignoreIllegals: true});
                        return '<code class="hljs language-' + lang + '">' + result.value + '</code>';
                    }
                } catch(e) {}
                return '<code class="hljs language-' + lang + '">' + code + '</code>';
            });
        })()
        """

        let result = ctx.evaluateScript(script)
        return result?.toString() ?? html
    }

    private func loadSyntaxCSS(isDark: Bool) -> String {
        let themeId = SettingsStore.shared.syntaxTheme
        let cssName = SyntaxThemeRegistry.cssResource(for: themeId, isDark: isDark)
        guard let url = Self.appBundle.url(forResource: cssName, withExtension: "css"),
              let css = try? String(contentsOf: url) else { return "" }
        return css
    }

    private func wrapHTML(body: String, syntaxCSS: String, theme: EditorTheme) -> String {
        let bg = hexString(theme.background)
        let fg = hexString(theme.foreground)
        let linkColor = hexString(theme.linkColor)
        let codeBg = theme.isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.06)"
        let borderColor = theme.isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(syntaxCSS)

        * { box-sizing: border-box; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: 14px;
            line-height: 1.6;
            color: \(fg);
            background: \(bg);
            padding: 16px 24px;
            margin: 0;
            -webkit-font-smoothing: antialiased;
        }

        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.4em;
            margin-bottom: 0.6em;
            font-weight: 600;
            line-height: 1.25;
        }
        h1 { font-size: 1.8em; border-bottom: 1px solid \(borderColor); padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; border-bottom: 1px solid \(borderColor); padding-bottom: 0.3em; }
        h3 { font-size: 1.25em; }
        h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }

        p { margin: 0.8em 0; }

        a { color: \(linkColor); text-decoration: none; }
        a:hover { text-decoration: underline; }

        code {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 0.9em;
            background: \(codeBg);
            padding: 0.2em 0.4em;
            border-radius: 4px;
        }

        pre {
            background: \(codeBg);
            border-radius: 6px;
            padding: 12px 16px;
            overflow-x: auto;
            margin: 1em 0;
        }
        pre code {
            background: none;
            padding: 0;
            font-size: 0.85em;
            line-height: 1.5;
        }

        /* Override highlight.js block styling to match our container */
        pre code.hljs {
            background: none;
            padding: 0;
        }

        blockquote {
            border-left: 3px solid \(borderColor);
            margin: 1em 0;
            padding: 0.5em 1em;
            color: \(fg);
            opacity: 0.8;
        }

        img {
            max-width: 100%;
            height: auto;
            border-radius: 4px;
        }

        table {
            border-collapse: collapse;
            width: 100%;
            margin: 1em 0;
        }
        th, td {
            border: 1px solid \(borderColor);
            padding: 8px 12px;
            text-align: left;
        }
        th { font-weight: 600; }

        hr {
            border: none;
            border-top: 1px solid \(borderColor);
            margin: 1.5em 0;
        }

        ul, ol { padding-left: 2em; margin: 0.5em 0; }
        li { margin: 0.3em 0; }

        /* Checklist styling */
        ul li input[type="checkbox"] {
            margin-right: 0.4em;
        }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    func stripFrontmatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else {
            return markdown
        }
        // Find the closing --- after the opening one
        let searchStart = markdown.index(markdown.startIndex, offsetBy: 4)
        guard searchStart < markdown.endIndex else { return markdown }
        let rest = markdown[searchStart...]
        if let closingRange = rest.range(of: "\n---\n") {
            return String(rest[closingRange.upperBound...])
        }
        if let closingRange = rest.range(of: "\r\n---\r\n") {
            return String(rest[closingRange.upperBound...])
        }
        // Frontmatter at end of file (no trailing content)
        if rest.hasSuffix("\n---") || rest.hasSuffix("\r\n---") {
            return ""
        }
        return markdown
    }

    private func hexString(_ color: NSColor) -> String {
        guard let srgb = color.usingColorSpace(.sRGB) else { return "#808080" }
        let r = Int(round(srgb.redComponent * 255))
        let g = Int(round(srgb.greenComponent * 255))
        let b = Int(round(srgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
