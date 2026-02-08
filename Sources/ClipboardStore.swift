import Cocoa

struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), content: String, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }
}

class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var entries: [ClipboardEntry] = []

    private var timer: Timer?
    private var lastChangeCount: Int
    private var saveDebounceWork: DispatchWorkItem?
    private let storageURL: URL
    private let maxEntries = 500

    static let didChangeNotification = Notification.Name("clipboardStoreDidChange")

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let itsypadDir = appSupport.appendingPathComponent("Itsypad")
        try? FileManager.default.createDirectory(at: itsypadDir, withIntermediateDirectories: true)
        storageURL = itsypadDir.appendingPathComponent("clipboard.json")

        lastChangeCount = NSPasteboard.general.changeCount
        restoreEntries()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        saveEntries()
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Deduplicate consecutive identical entries
        if let last = entries.first, last.content == text { return }

        let entry = ClipboardEntry(content: text)
        entries.insert(entry, at: 0)

        // FIFO eviction
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        scheduleSave()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - Actions

    func copyToClipboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.content, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        scheduleSave()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func search(query: String) -> [ClipboardEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.content.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveEntries()
        }
        saveDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("Failed to save clipboard history: \(error)")
        }
    }

    private func restoreEntries() {
        guard let data = try? Data(contentsOf: storageURL),
              let restored = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = restored
    }
}
