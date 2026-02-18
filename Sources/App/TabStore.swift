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
    var isPinned: Bool
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
        isPinned: Bool = false,
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
        self.isPinned = isPinned
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
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
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
    private var kvsMigration: KVSMigration?

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

        let isFirstLaunch = !FileManager.default.fileExists(atPath: self.sessionURL.path)

        TabStore.migrateLegacyData(to: sessionURL ?? self.sessionURL)
        restoreSession()
        kvsMigration = KVSMigration(flagKey: "kvsTabsMigrated") { [weak self] kvs in
            self?.importKVSTabs(from: kvs) ?? false
        }

        if tabs.isEmpty {
            if isFirstLaunch {
                addWelcomeTab()
            } else {
                addNewTab()
            }
        }
    }

    // MARK: - Tab operations

    func addNewTab() {
        let tab = TabData()
        tabs.append(tab)
        selectedTabID = tab.id
        CloudSyncEngine.shared.recordChanged(tab.id)
        G2SyncEngine.shared.schedulePush(id: tab.id)
        scheduleSave()
    }

    static var welcomeContent: String {
        String(localized: "welcome.content", defaultValue: """
        # Welcome to Itsypad

        A tiny, fast scratchpad that lives in your menu bar.

        Here's what you can do:

        - [x] Download Itsypad
        - [ ] Write notes, ideas, code snippets
        - [ ] Use automatic checklists, bullet and numbered lists
        - [ ] Split the editor into multiple panes
        - [ ] Browse clipboard history
        - [ ] Try Itsypad for iOS
        - [ ] Sync tabs across devices with iCloud
        - [ ] Switch between themes in settings

        Happy writing! Close this tab whenever you're ready to start.
        """)
    }

    func addWelcomeTab() {
        let tab = TabData(
            name: String(localized: "welcome.tab_name", defaultValue: "Welcome to Itsypad"),
            content: Self.welcomeContent,
            language: "markdown"
        )
        tabs.append(tab)
        selectedTabID = tab.id
        scheduleSave()
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let isScratch = tabs[index].fileURL == nil
        if let url = tabs[index].fileURL {
            url.stopAccessingSecurityScopedResource()
        }
        if isScratch {
            CloudSyncEngine.shared.recordDeleted(id)
            G2SyncEngine.shared.scheduleDelete(id: id)
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
            CloudSyncEngine.shared.recordChanged(id)
            G2SyncEngine.shared.schedulePush(id: id)
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
            CloudSyncEngine.shared.recordChanged(id)
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
            // During first sync, local tabs are authoritative – skip updates
            if CloudSyncEngine.shared.isFirstSync { return }
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
                isDirty: !data.content.isEmpty,
                lastModified: data.lastModified
            )
            tabs.append(tab)
            result.newTabIDs.append(data.id)
        }

        let changed = !result.newTabIDs.isEmpty || !result.updatedTabIDs.isEmpty
        lastICloudSync = Date()

        if changed {
            for id in result.newTabIDs + result.updatedTabIDs {
                G2SyncEngine.shared.schedulePush(id: id)
            }
            NotificationCenter.default.post(
                name: Self.cloudTabsMerged,
                object: self,
                userInfo: ["result": result]
            )
            scheduleSave()
        }
    }

    func removeCloudTab(id: UUID) {
        // During first sync, local tabs are authoritative – skip removals
        if CloudSyncEngine.shared.isFirstSync { return }
        guard tabs.contains(where: { $0.id == id }) else { return }

        var result = CloudMergeResult()
        result.removedTabIDs.append(id)
        tabs.removeAll { $0.id == id }

        G2SyncEngine.shared.scheduleDelete(id: id)

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

    // MARK: - G2 sync

    func applyG2Note(id: UUID, name: String, content: String, lastModified: Date) {
        guard !tabs.contains(where: { $0.id == id }) else { return }
        let tab = TabData(
            id: id,
            name: name,
            content: content,
            language: "plain",
            isDirty: !content.isEmpty,
            lastModified: lastModified
        )
        tabs.append(tab)
        scheduleSave()
    }

    func removeG2DeletedNotes(keeping remoteIDs: Set<UUID>, pendingPush: Set<UUID>) {
        let before = tabs.count
        let removedIDs = tabs
            .filter { $0.fileURL == nil && !remoteIDs.contains($0.id) && !pendingPush.contains($0.id) }
            .map { $0.id }
        guard !removedIDs.isEmpty else { return }

        var result = CloudMergeResult()
        result.removedTabIDs = removedIDs

        tabs = tabs.filter { !removedIDs.contains($0.id) }
        print("[G2] tabs \(before) -> \(tabs.count)")

        for id in removedIDs {
            CloudSyncEngine.shared.recordDeleted(id)
        }

        if tabs.isEmpty {
            addNewTab()
        } else if let sel = selectedTabID, !tabs.contains(where: { $0.id == sel }) {
            selectedTabID = tabs.first?.id
        }

        NotificationCenter.default.post(
            name: Self.cloudTabsMerged,
            object: self,
            userInfo: ["result": result]
        )
        scheduleSave()
    }

    // MARK: - KVS migration (v1.6.0 iCloud sync → App Store)

    @discardableResult
    private func importKVSTabs(from kvs: NSUbiquitousKeyValueStore) -> Bool {
        // The old KVS sync stored tabs under the "tabs" key as JSON-encoded [TabData].
        // TabData's Codable init handles missing optional fields (isPinned, bookmark, etc.)
        // via defaults, so decoding old payloads works without a legacy struct.
        guard let data = kvs.data(forKey: "tabs"),
              let kvsTabs = try? JSONDecoder().decode([TabData].self, from: data),
              !kvsTabs.isEmpty else { return false }

        let existingIDs = Set(tabs.map { $0.id })
        let newTabs = kvsTabs.filter { !existingIDs.contains($0.id) }

        if !newTabs.isEmpty {
            // If the only local tab is the empty default "Untitled" tab created on
            // first launch, replace it entirely with the KVS tabs.
            let isDefaultOnly = tabs.count == 1 && tabs[0].content.isEmpty
            if isDefaultOnly {
                tabs = kvsTabs
                selectedTabID = kvsTabs.first?.id
            } else {
                tabs.append(contentsOf: newTabs)
            }
            scheduleSave()
        }

        // Remove KVS keys so the old data isn't re-imported if this code runs again
        // (belt-and-suspenders alongside the UserDefaults flag).
        kvs.removeObject(forKey: "tabs")
        kvs.removeObject(forKey: "deletedTabIDs")
        kvs.synchronize()
        UserDefaults.standard.set(true, forKey: "kvsTabsMigrated")
        NSLog("[KVS Migration] Imported %d tabs from iCloud KVS", newTabs.count)
        return true
    }

    // MARK: - Legacy data migration (non-sandboxed → sandboxed path)
    //
    // Background: versions up to 1.6.0 ran without App Sandbox, so session.json
    // lived at ~/Library/Application Support/Itsypad/session.json. Starting with
    // 1.8.0 we enabled App Sandbox for App Store distribution, which moves the
    // data directory into ~/Library/Containers/com.nickustinov.itsypad/Data/
    // Library/Application Support/Itsypad/session.json.
    //
    // Problem: users upgrading from ≤1.6.0 to 1.8.x lost all their tabs because
    // the sandboxed app couldn't see the old session.json at the non-sandboxed path.
    //
    // Solution: the direct-download build (itsypad-direct.entitlements) has a
    // temporary-exception entitlement granting read-write access to the old path
    // (com.apple.security.temporary-exception.files.home-relative-path.read-write).
    // On first launch, this method reads the old session.json, merges its tabs
    // into the new sandboxed session, and deletes the old file.
    //
    // Note: the App Store build does NOT have this entitlement (Apple would reject
    // it), so this migration only works for users upgrading the direct-download
    // version. App Store users coming from ≤1.6.0 are covered by the KVS migration
    // above (if they had iCloud sync enabled) or are out of luck (no local file
    // access from sandbox).
    //
    // Uses getpwuid() to find the real home directory because NSHomeDirectory()
    // returns the sandbox container path when sandboxed.

    private static func migrateLegacyData(to sandboxedURL: URL) {
        let fm = FileManager.default

        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir else { return }
        let realHome = String(cString: home)
        let oldDir = "\(realHome)/Library/Application Support/Itsypad"
        let oldFile = "\(oldDir)/session.json"

        NSLog("[Migration] session: oldFile=%@ sandboxed=%@ exists=%d",
              oldFile, sandboxedURL.path, fm.fileExists(atPath: oldFile))

        // Same path means we're running non-sandboxed – nothing to migrate
        guard oldFile != sandboxedURL.path else { return }

        guard fm.fileExists(atPath: oldFile) else { return }

        guard let oldData = try? Data(contentsOf: URL(fileURLWithPath: oldFile)),
              let oldSession = try? JSONDecoder().decode(SessionData.self, from: oldData),
              !oldSession.tabs.isEmpty else {
            try? fm.removeItem(atPath: oldFile)
            return
        }

        let existingSession: SessionData?
        if let data = try? Data(contentsOf: sandboxedURL) {
            existingSession = try? JSONDecoder().decode(SessionData.self, from: data)
        } else {
            existingSession = nil
        }

        var mergedTabs: [TabData]
        if let existing = existingSession {
            let existingIDs = Set(existing.tabs.map { $0.id })
            let newTabs = oldSession.tabs.filter { !existingIDs.contains($0.id) }
            let isDefaultOnly = existing.tabs.count == 1 && existing.tabs[0].content.isEmpty
            mergedTabs = isDefaultOnly ? oldSession.tabs : existing.tabs + newTabs
        } else {
            mergedTabs = oldSession.tabs
        }

        let selectedID = existingSession?.selectedTabID ?? oldSession.selectedTabID
        let layout = existingSession?.layout ?? oldSession.layout
        let merged = SessionData(tabs: mergedTabs, selectedTabID: selectedID, layout: layout)

        do {
            let encoded = try JSONEncoder().encode(merged)
            try encoded.write(to: sandboxedURL, options: .atomic)
            try? fm.removeItem(atPath: oldFile)
            NSLog("[Migration] Merged %d legacy tabs into session", oldSession.tabs.count)
        } catch {
            NSLog("[Migration] Failed to migrate session.json: \(error)")
        }
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
