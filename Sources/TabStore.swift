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

struct TabData: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var language: String
    var fileURL: URL?
    var languageLocked: Bool
    var isDirty: Bool
    var cursorPosition: Int

    init(
        id: UUID = UUID(),
        name: String = "Untitled",
        content: String = "",
        language: String = "plain",
        fileURL: URL? = nil,
        languageLocked: Bool = false,
        isDirty: Bool = false,
        cursorPosition: Int = 0
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.language = language
        self.fileURL = fileURL
        self.languageLocked = languageLocked
        self.isDirty = isDirty
        self.cursorPosition = cursorPosition
    }
}

class TabStore: ObservableObject {
    static let shared = TabStore()

    @Published var tabs: [TabData] = []
    @Published var selectedTabID: UUID?

    private var saveDebounceWork: DispatchWorkItem?
    private let sessionURL: URL
    private let cloudStore: KeyValueStoreProtocol
    private var icloudObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private static let cloudTabsKey = "tabs"

    var selectedTab: TabData? {
        tabs.first { $0.id == selectedTabID }
    }

    var selectedTabIndex: Int? {
        tabs.firstIndex { $0.id == selectedTabID }
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
        tabs[index].content = content
        tabs[index].isDirty = true

        // Auto-name from first line when no file
        if tabs[index].fileURL == nil {
            let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            tabs[index].name = trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(30))
        }

        // Auto-detect language if not locked
        if !tabs[index].languageLocked {
            let result = LanguageDetector.shared.detect(
                text: content,
                name: tabs[index].name,
                fileURL: tabs[index].fileURL
            )
            if result.confidence > 5 {
                tabs[index].language = result.lang
            }
        }

        scheduleSave()
    }

    func updateLanguage(id: UUID, language: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].language = language
        tabs[index].languageLocked = true
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

    func startICloudSync() {
        guard icloudObserver == nil else { return }
        cloudStore.synchronize()
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
        cloudStore.synchronize()
    }

    private func saveToICloud() {
        guard SettingsStore.shared.icloudSync else { return }
        let scratchTabs = tabs.filter { $0.fileURL == nil }
        guard let data = try? JSONEncoder().encode(scratchTabs) else { return }
        cloudStore.setData(data, forKey: Self.cloudTabsKey)
        cloudStore.synchronize()
    }

    private func mergeCloudTabs() {
        guard SettingsStore.shared.icloudSync,
              let data = cloudStore.data(forKey: Self.cloudTabsKey),
              let cloudTabs = try? JSONDecoder().decode([TabData].self, from: data)
        else { return }

        var changed = false
        for cloudTab in cloudTabs {
            if let localIndex = tabs.firstIndex(where: { $0.id == cloudTab.id }) {
                if tabs[localIndex].content != cloudTab.content
                    || tabs[localIndex].name != cloudTab.name
                    || tabs[localIndex].language != cloudTab.language {
                    tabs[localIndex].content = cloudTab.content
                    tabs[localIndex].name = cloudTab.name
                    tabs[localIndex].language = cloudTab.language
                    changed = true
                }
            } else {
                tabs.append(cloudTab)
                changed = true
            }
        }

        if changed {
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
            let data = try JSONEncoder().encode(SessionData(tabs: tabs, selectedTabID: selectedTabID))
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
    }
}

struct SessionData: Codable {
    let tabs: [TabData]
    let selectedTabID: UUID?
}
