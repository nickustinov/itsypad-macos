import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let theme: EditorTheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true

        loadHTML(in: webView)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if html != context.coordinator.lastHTML {
            // Capture scroll position, reload, then restore
            webView.evaluateJavaScript("window.scrollY") { result, _ in
                let scrollY = result as? CGFloat ?? 0
                context.coordinator.pendingScrollY = scrollY
                loadHTML(in: webView)
                context.coordinator.lastHTML = html
            }
        }
    }

    private func loadHTML(in webView: WKWebView) {
        if let baseURL {
            // Write HTML to a temp file inside the app container, then grant
            // WKWebView read access to the original file's directory so that
            // relative image paths still resolve.
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("markdown-preview", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFile = tempDir.appendingPathComponent("preview.html")
            try? html.write(to: tempFile, atomically: true, encoding: .utf8)
            webView.loadFileURL(tempFile, allowingReadAccessTo: baseURL)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        var pendingScrollY: CGFloat?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let scrollY = pendingScrollY, scrollY > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))")
                pendingScrollY = nil
            }
        }
    }
}
