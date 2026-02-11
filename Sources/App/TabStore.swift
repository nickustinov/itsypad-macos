import Cocoa

protocol KeyValueStoreProtocol: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueStoreProtocol {
    func setData(_ data: Data?, forKey key: String) {
        set(data, forKey: key)
    }
}

struct TabData: Identifiable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var language: String
    var fileURL: URL?
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
        languageLocked = try c.decode(Bool.self, forKey: .languageLocked)
        isDirty = try c.decode(Bool.self, forKey: .isDirty)
        cursorPosition = try c.decode(Int.self, forKey: .cursorPosition)
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? .distantPast
    }
}

class TabStore: ObservableObject {
    static let shared = TabStore()

    @Published var tabs: [TabData] = []
    @Published var selectedTabID: UUID?
    @Published private(set) var lastICloudSync: Date?
    private(set) var savedLayout: LayoutNode?
    var currentLayout: LayoutNode?

    private var saveDebounceWork: DispatchWorkItem?
    private var languageDetectWork: DispatchWorkItem?
    private let sessionURL: URL
    private let cloudStore: KeyValueStoreProtocol
    private var icloudObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private static let cloudTabsKey = "tabs"
    private static let cloudDeletedKey = "deletedTabIDs"
    private var deletedTabIDs: Set<UUID> = []

    var selectedTab: TabData? {
        tabs.first { $0.id == selectedTabID }
    }

    init(sessionURL: URL? = nil, cloudStore: KeyValueStoreProtocol = NSUbiquitousKeyValueStore.default) {
        self.cloudStore = cloudStore

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

        if SettingsStore.shared.icloudSync {
            startICloudSync()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if SettingsStore.shared.icloudSync {
                self.startICloudSync()
            } else {
                self.stopICloudSync()
            }
        }
    }

    // MARK: - Tab operations

    func addNewTab() {
        let tab = TabData()
        tabs.append(tab)
        selectedTabID = tab.id
        scheduleSave()
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        // Record tombstone for scratch tabs so other devices don't re-add
        if tabs[index].fileURL == nil && SettingsStore.shared.icloudSync {
            deletedTabIDs.insert(id)
            syncDeletedIDs()
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

            let tab = TabData(
                name: name,
                content: content,
                language: lang,
                fileURL: url,
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

    // MARK: - iCloud sync

    struct CloudMergeResult {
        var newTabIDs: [UUID] = []
        var updatedTabIDs: [UUID] = []
        var removedTabIDs: [UUID] = []
    }

    static let cloudTabsMerged = Notification.Name("cloudTabsMerged")

    private func syncDeletedIDs() {
        let strings = deletedTabIDs.map(\.uuidString)
        cloudStore.setData(try? JSONEncoder().encode(strings), forKey: Self.cloudDeletedKey)
        cloudStore.synchronize()
    }

    private func loadDeletedIDs() {
        guard let data = cloudStore.data(forKey: Self.cloudDeletedKey),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return }
        deletedTabIDs = Set(strings.compactMap(UUID.init))
    }

    func startICloudSync() {
        guard icloudObserver == nil else { return }
        let synced = cloudStore.synchronize()
        if synced { lastICloudSync = Date() }
        loadDeletedIDs()
        mergeCloudTabs()
        icloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore, queue: .main
        ) { [weak self] _ in
            self?.mergeCloudTabs()
        }
    }

    func stopICloudSync() {
        if let observer = icloudObserver {
            NotificationCenter.default.removeObserver(observer)
            icloudObserver = nil
        }
        cloudStore.removeObject(forKey: Self.cloudTabsKey)
        cloudStore.removeObject(forKey: Self.cloudDeletedKey)
        deletedTabIDs.removeAll()
        cloudStore.synchronize()
    }

    func checkICloud() {
        guard SettingsStore.shared.icloudSync else { return }
        cloudStore.synchronize()
        loadDeletedIDs()
        mergeCloudTabs()
    }

    private func saveToICloud() {
        guard SettingsStore.shared.icloudSync else { return }
        let scratchTabs = tabs.filter { $0.fileURL == nil }
        guard let data = try? JSONEncoder().encode(scratchTabs) else { return }
        cloudStore.setData(data, forKey: Self.cloudTabsKey)
        cloudStore.synchronize()
        lastICloudSync = Date()
    }

    private func mergeCloudTabs() {
        guard SettingsStore.shared.icloudSync else { return }
        guard let data = cloudStore.data(forKey: Self.cloudTabsKey) else { return }
        guard let cloudTabs = try? JSONDecoder().decode([TabData].self, from: data) else { return }

        var result = CloudMergeResult()
        for cloudTab in cloudTabs {
            // Never resurrect a deleted tab
            if deletedTabIDs.contains(cloudTab.id) { continue }
            if let localIndex = tabs.firstIndex(where: { $0.id == cloudTab.id }) {
                // Only accept cloud version if it's newer than local
                guard cloudTab.lastModified > tabs[localIndex].lastModified else { continue }
                if tabs[localIndex].content != cloudTab.content
                    || tabs[localIndex].name != cloudTab.name
                    || tabs[localIndex].language != cloudTab.language {
                    tabs[localIndex].content = cloudTab.content
                    tabs[localIndex].name = cloudTab.name
                    tabs[localIndex].language = cloudTab.language
                    tabs[localIndex].lastModified = cloudTab.lastModified
                    result.updatedTabIDs.append(cloudTab.id)
                }
            } else {
                tabs.append(cloudTab)
                result.newTabIDs.append(cloudTab.id)
            }
        }

        // Remove local scratch tabs that were tombstoned on another device
        let toRemove = tabs.filter { $0.fileURL == nil && deletedTabIDs.contains($0.id) }
        for tab in toRemove {
            result.removedTabIDs.append(tab.id)
        }
        tabs.removeAll { $0.fileURL == nil && deletedTabIDs.contains($0.id) }

        // Ensure at least one tab exists
        if tabs.isEmpty {
            addNewTab()
        }

        let changed = !result.newTabIDs.isEmpty || !result.updatedTabIDs.isEmpty || !result.removedTabIDs.isEmpty
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
        saveToICloud()
    }

    private func restoreSession() {
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data)
        else { return }

        tabs = session.tabs
        selectedTabID = session.selectedTabID ?? tabs.first?.id
        savedLayout = session.layout

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
