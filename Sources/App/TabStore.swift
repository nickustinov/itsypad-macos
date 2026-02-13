import Cocoa

struct TabData: Identifiable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var language: String
    var fileURL: URL?
    var bookmark: Data?
    var languageLocked: Bool
    var isDirty: Bool
    var cursorPosition: Int
    var lastModified: Date

    init(
        id: UUID = UUID(),
        name: String = "Untitled",
        content: String = "",
        language: String = "plain",
        fileURL: URL? = nil,
        bookmark: Data? = nil,
        languageLocked: Bool = false,
        isDirty: Bool = false,
        cursorPosition: Int = 0,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.language = language
        self.fileURL = fileURL
        self.bookmark = bookmark
        self.languageLocked = languageLocked
        self.isDirty = isDirty
        self.cursorPosition = cursorPosition
        self.lastModified = lastModified
    }
}

extension TabData: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        content = try c.decode(String.self, forKey: .content)
        language = try c.decode(String.self, forKey: .language)
        fileURL = try c.decodeIfPresent(URL.self, forKey: .fileURL)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        languageLocked = try c.decode(Bool.self, forKey: .languageLocked)
        isDirty = try c.decodeIfPresent(Bool.self, forKey: .isDirty) ?? false
        cursorPosition = try c.decode(Int.self, forKey: .cursorPosition)
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? .distantPast
    }
}

class TabStore: ObservableObject {
    static let shared = TabStore()

    @Published var tabs: [TabData] = []
    @Published var selectedTabID: UUID?
    @Published var lastICloudSync: Date?
    private(set) var savedLayout: LayoutNode?
    var currentLayout: LayoutNode?

    private var saveDebounceWork: DispatchWorkItem?
    private var languageDetectWork: DispatchWorkItem?
    private let sessionURL: URL

    var selectedTab: TabData? {
        tabs.first { $0.id == selectedTabID }
    }

    init(sessionURL: URL? = nil) {
        if let sessionURL {
            self.sessionURL = sessionURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let itsypadDir = appSupport.appendingPathComponent("Itsypad")
            try? FileManager.default.createDirectory(at: itsypadDir, withIntermediateDirectories: true)
            self.sessionURL = itsypadDir.appendingPathComponent("session.json")
        }

        restoreSession()

        if tabs.isEmpty {
            addNewTab()
        }
    }

    // MARK: - Tab operations

    func addNewTab() {
        let tab = TabData()
        tabs.append(tab)
        selectedTabID = tab.id
        CloudSyncEngine.shared.recordChanged(tab.id, type: .scratchTab)
        scheduleSave()
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let isScratch = tabs[index].fileURL == nil
        if let url = tabs[index].fileURL {
            url.stopAccessingSecurityScopedResource()
        }
        if isScratch {
            CloudSyncEngine.shared.recordDeleted(id, type: .scratchTab)
        }
        tabs.remove(at: index)

        if selectedTabID == id {
            if tabs.isEmpty {
                addNewTab()
            } else {
                let newIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[newIndex].id
            }
        }
        scheduleSave()
    }

    func updateContent(id: UUID, content: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard tabs[index].content != content else { return }

        // Batch mutations into a single array setter to fire @Published once
        var tab = tabs[index]
        tab.content = content
        tab.isDirty = true
        tab.lastModified = Date()

        // Auto-name from first line when no file
        if tab.fileURL == nil {
            let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let newName = trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(30))
            tab.name = newName
        }

        tabs[index] = tab

        // Auto-detect language if not locked (debounced to avoid per-keystroke cost)
        if !tab.languageLocked {
            scheduleLanguageDetection(id: tab.id, content: content, name: tab.name, fileURL: tab.fileURL)
        }

        if tab.fileURL == nil {
            CloudSyncEngine.shared.recordChanged(id, type: .scratchTab)
        }

        scheduleSave()
    }

    /// Fires when auto-detection changes a tab's language: (tabID, newLanguage).
    var onLanguageDetected: ((UUID, String) -> Void)?

    private func scheduleLanguageDetection(id: UUID, content: String, name: String?, fileURL: URL?) {
        languageDetectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let index = self.tabs.firstIndex(where: { $0.id == id }),
                  !self.tabs[index].languageLocked else { return }
            let result = LanguageDetector.shared.detect(text: content, name: name, fileURL: fileURL)
            let oldLang = self.tabs[index].language
            if result.confidence > 0 {
                self.tabs[index].language = result.lang
            } else if oldLang != "plain" && result.lang == "plain" {
                self.tabs[index].language = "plain"
            }
            let newLang = self.tabs[index].language
            NSLog("[AutoDetect] RESULT: '%@' -> '%@' (confidence=%d, name=%@)",
                  oldLang, newLang, result.confidence, name ?? "(untitled)")
            if newLang != oldLang {
                self.onLanguageDetected?(id, newLang)
            }
        }
        languageDetectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func updateLanguage(id: UUID, language: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].language = language
        tabs[index].languageLocked = true
        tabs[index].lastModified = Date()
        if tabs[index].fileURL == nil {
            CloudSyncEngine.shared.recordChanged(id, type: .scratchTab)
        }
        scheduleSave()
    }

    func updateCursorPosition(id: UUID, position: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].cursorPosition = position
    }

    // MARK: - File operations

    func saveFile(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        if let fileURL = tabs[index].fileURL {
            do {
                try tabs[index].content.write(to: fileURL, atomically: true, encoding: .utf8)
                tabs[index].isDirty = false
                scheduleSave()
            } catch {
                NSLog("Failed to save file: \(error)")
            }
        } else {
            saveFileAs(id: id)
        }
    }

    func saveFileAs(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = tabs[index].name
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try tabs[index].content.write(to: url, atomically: true, encoding: .utf8)
            tabs[index].fileURL = url
            tabs[index].name = url.lastPathComponent
            tabs[index].isDirty = false
            tabs[index].bookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            if let lang = LanguageDetector.shared.detectFromExtension(name: url.lastPathComponent) {
                tabs[index].language = lang
                tabs[index].languageLocked = true
            }

            scheduleSave()
        } catch {
            NSLog("Failed to save file: \(error)")
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            openFile(url: url)
        }
    }

    func openFile(url: URL) {
        // Check if already open
        if let existing = tabs.firstIndex(where: { $0.fileURL == url }) {
            selectedTabID = tabs[existing].id
            return
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let name = url.lastPathComponent
            let lang = LanguageDetector.shared.detectFromExtension(name: name)
                ?? LanguageDetector.shared.detect(text: content, name: name, fileURL: url).lang
            let bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let tab = TabData(
                name: name,
                content: content,
                language: lang,
                fileURL: url,
                bookmark: bookmarkData,
                languageLocked: true
            )
            tabs.append(tab)
            selectedTabID = tab.id
            scheduleSave()
        } catch {
            NSLog("Failed to open file: \(error)")
        }
    }

    func reloadFromDisk(id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              let fileURL = tabs[index].fileURL else { return false }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            tabs[index].content = content
            tabs[index].isDirty = false
            scheduleSave()
            return true
        } catch {
            NSLog("Failed to reload file from disk: \(error)")
            return false
        }
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tabs.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        let insertAt = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        tabs.insert(tab, at: insertAt)
        scheduleSave()
    }

    // MARK: - Cloud sync

    struct CloudMergeResult {
        var newTabIDs: [UUID] = []
        var updatedTabIDs: [UUID] = []
        var removedTabIDs: [UUID] = []
    }

    static let cloudTabsMerged = Notification.Name("cloudTabsMerged")

    func applyCloudTab(_ data: CloudTabRecord) {
        var result = CloudMergeResult()

        if let localIndex = tabs.firstIndex(where: { $0.id == data.id }) {
            // Only accept cloud version if it's newer than local
            guard data.lastModified > tabs[localIndex].lastModified else { return }
            if tabs[localIndex].content != data.content
                || tabs[localIndex].name != data.name
                || tabs[localIndex].language != data.language {
                tabs[localIndex].content = data.content
                tabs[localIndex].name = data.name
                tabs[localIndex].language = data.language
                tabs[localIndex].languageLocked = data.languageLocked
                tabs[localIndex].lastModified = data.lastModified
                result.updatedTabIDs.append(data.id)
            }
        } else {
            let tab = TabData(
                id: data.id,
                name: data.name,
                content: data.content,
                language: data.language,
                languageLocked: data.languageLocked,
                lastModified: data.lastModified
            )
            tabs.append(tab)
            result.newTabIDs.append(data.id)
        }

        let changed = !result.newTabIDs.isEmpty || !result.updatedTabIDs.isEmpty
        lastICloudSync = Date()

        if changed {
            NotificationCenter.default.post(
                name: Self.cloudTabsMerged,
                object: self,
                userInfo: ["result": result]
            )
            scheduleSave()
        }
    }

    func removeCloudTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }

        var result = CloudMergeResult()
        result.removedTabIDs.append(id)
        tabs.removeAll { $0.id == id }

        if tabs.isEmpty {
            addNewTab()
        }

        lastICloudSync = Date()
        NotificationCenter.default.post(
            name: Self.cloudTabsMerged,
            object: self,
            userInfo: ["result": result]
        )
        scheduleSave()
    }

    // MARK: - Session persistence

    func scheduleSave() {
        saveDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveSession()
        }
        saveDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveSession() {
        do {
            let session = SessionData(tabs: tabs, selectedTabID: selectedTabID, layout: currentLayout)
            let data = try JSONEncoder().encode(session)
            try data.write(to: sessionURL, options: .atomic)
        } catch {
            NSLog("Failed to save session: \(error)")
        }
    }

    private func restoreSession() {
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data)
        else { return }

        tabs = session.tabs
        selectedTabID = session.selectedTabID ?? tabs.first?.id
        savedLayout = session.layout

        // Resolve security-scoped bookmarks for file-backed tabs
        for index in tabs.indices {
            guard let bookmarkData = tabs[index].bookmark else { continue }
            var isStale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            _ = resolvedURL.startAccessingSecurityScopedResource()
            tabs[index].fileURL = resolvedURL
            if isStale {
                tabs[index].bookmark = try? resolvedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
        }

        // Re-detect language for unlocked tabs to fix stale detection
        for index in tabs.indices where !tabs[index].languageLocked {
            let tab = tabs[index]
            let result = LanguageDetector.shared.detect(
                text: tab.content,
                name: tab.name,
                fileURL: tab.fileURL
            )
            if result.confidence > 0 {
                tabs[index].language = result.lang
            } else if result.lang == "plain" && tab.language != "plain" {
                tabs[index].language = "plain"
            }
        }
    }
}

struct SessionData: Codable {
    let tabs: [TabData]
    let selectedTabID: UUID?
    var layout: LayoutNode?
}

indirect enum LayoutNode: Codable, Equatable {
    case pane(PaneNodeData)
    case split(SplitNodeData)
}

struct PaneNodeData: Codable, Equatable {
    let tabIDs: [UUID]
    let selectedTabID: UUID?
    var hasClipboard: Bool

    init(tabIDs: [UUID], selectedTabID: UUID?, hasClipboard: Bool = false) {
        self.tabIDs = tabIDs
        self.selectedTabID = selectedTabID
        self.hasClipboard = hasClipboard
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabIDs = try container.decode([UUID].self, forKey: .tabIDs)
        selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        hasClipboard = try container.decodeIfPresent(Bool.self, forKey: .hasClipboard) ?? false
    }
}

struct SplitNodeData: Codable, Equatable {
    let orientation: String
    let dividerPosition: Double
    let first: LayoutNode
    let second: LayoutNode
}
