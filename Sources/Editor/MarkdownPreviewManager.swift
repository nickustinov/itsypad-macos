import Foundation
import Bonsplit

final class MarkdownPreviewManager {
    private var previewingTabs: Set<TabID> = []
    private var htmlCache: [TabID: String] = [:]
    private var baseURLCache: [TabID: URL] = [:]
    private var debounceWork: DispatchWorkItem?

    func isActive(for tabID: TabID) -> Bool {
        previewingTabs.contains(tabID)
    }

    func html(for tabID: TabID) -> String? {
        htmlCache[tabID]
    }

    func baseURL(for tabID: TabID) -> URL? {
        baseURLCache[tabID]
    }

    /// Toggle preview on/off. Returns true if preview is now active.
    @discardableResult
    func toggle(for tabID: TabID, language: String?, content: String, fileURL: URL?, theme: EditorTheme) -> Bool {
        if previewingTabs.contains(tabID) {
            previewingTabs.remove(tabID)
            htmlCache.removeValue(forKey: tabID)
            baseURLCache.removeValue(forKey: tabID)
            return false
        } else {
            guard language == "markdown" else { return false }
            render(for: tabID, content: content, fileURL: fileURL, theme: theme)
            previewingTabs.insert(tabID)
            return true
        }
    }

    /// Debounced re-render on text change.
    func scheduleUpdate(for tabID: TabID, content: String, fileURL: URL?, theme: EditorTheme, onChange: (() -> Void)? = nil) {
        guard previewingTabs.contains(tabID) else { return }
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.render(for: tabID, content: content, fileURL: fileURL, theme: theme)
            onChange?()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Re-render all active previews (e.g. after settings/theme change).
    func renderAll(tabs: [(id: TabID, content: String, fileURL: URL?)], theme: EditorTheme, onChange: (() -> Void)? = nil) {
        var didRender = false
        for tab in tabs where previewingTabs.contains(tab.id) {
            render(for: tab.id, content: tab.content, fileURL: tab.fileURL, theme: theme)
            didRender = true
        }
        if didRender { onChange?() }
    }

    /// Cleanup on tab close.
    func removeTab(_ tabID: TabID) {
        previewingTabs.remove(tabID)
        htmlCache.removeValue(forKey: tabID)
        baseURLCache.removeValue(forKey: tabID)
    }

    /// Exit preview if language changed away from markdown.
    /// Returns true if the tab was previewing and got removed.
    @discardableResult
    func exitIfNotMarkdown(for tabID: TabID, language: String) -> Bool {
        guard language != "markdown", previewingTabs.contains(tabID) else { return false }
        previewingTabs.remove(tabID)
        htmlCache.removeValue(forKey: tabID)
        return true
    }

    private func render(for tabID: TabID, content: String, fileURL: URL?, theme: EditorTheme) {
        htmlCache[tabID] = MarkdownRenderer.shared.render(markdown: content, theme: theme)
        baseURLCache[tabID] = fileURL?.deletingLastPathComponent()
    }
}
