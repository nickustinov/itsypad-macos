import Cocoa

enum ClipboardContentKind: String, Codable {
    case text
    case image
}

struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardContentKind
    let text: String?
    let imageFileName: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        kind: ClipboardContentKind = .text,
        text: String? = nil,
        imageFileName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFileName = imageFileName
        self.timestamp = timestamp
    }
}

class ClipboardStore {
    static let shared = ClipboardStore()

    var entries: [ClipboardEntry] = []

    private var timer: Timer?
    private var lastChangeCount: Int
    private var saveDebounceWork: DispatchWorkItem?
    private var lastPruneDate: Date = .distantPast
    private let storageURL: URL
    let imagesDirectory: URL

    static let didChangeNotification = Notification.Name("clipboardStoreDidChange")
    static let clipboardTabSelectedNotification = Notification.Name("clipboardTabSelected")

    private let maxEntries = 1000

    init(storageURL: URL? = nil, imagesDirectory: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let itsypadDir = appSupport.appendingPathComponent("Itsypad")
        try? FileManager.default.createDirectory(at: itsypadDir, withIntermediateDirectories: true)

        if let storageURL {
            self.storageURL = storageURL
        } else {
            self.storageURL = itsypadDir.appendingPathComponent("clipboard.json")
        }

        if let imagesDirectory {
            self.imagesDirectory = imagesDirectory
        } else {
            self.imagesDirectory = itsypadDir.appendingPathComponent("clipboard-images")
        }

        try? FileManager.default.createDirectory(at: self.imagesDirectory, withIntermediateDirectories: true)

        lastChangeCount = NSPasteboard.general.changeCount
        restoreEntries()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        pruneExpiredEntries()
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
        if Date().timeIntervalSince(lastPruneDate) >= 900 {
            lastPruneDate = Date()
            pruneExpiredEntries()
        }

        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Priority 1: image
        if let image = NSImage(pasteboard: pasteboard), image.isValid,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let fileName = "\(UUID().uuidString).png"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            do {
                try pngData.write(to: fileURL, options: .atomic)
                let entry = ClipboardEntry(kind: .image, imageFileName: fileName)
                insertEntry(entry)
            } catch {
                NSLog("Failed to save clipboard image: \(error)")
            }
            return
        }

        // Priority 2: text
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Deduplicate consecutive identical text
        if let last = entries.first, last.kind == .text, last.text == text { return }

        let entry = ClipboardEntry(kind: .text, text: text)
        insertEntry(entry)
    }

    private func insertEntry(_ entry: ClipboardEntry) {
        entries.insert(entry, at: 0)

        // FIFO eviction
        while entries.count > maxEntries {
            let evicted = entries.removeLast()
            cleanupImageFile(for: evicted)
        }

        if entry.kind == .text {
            CloudSyncEngine.shared.recordChanged(entry.id, type: .clipboardEntry)
        }

        scheduleSave()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - Actions

    func copyToClipboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.kind {
        case .text:
            if let text = entry.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let fileName = entry.imageFileName {
                let fileURL = imagesDirectory.appendingPathComponent(fileName)
                if let data = try? Data(contentsOf: fileURL) {
                    pasteboard.setData(data, forType: .png)
                }
            }
        }

        lastChangeCount = pasteboard.changeCount

        // Re-add as newest entry if this isn't already the most recent,
        // so iCloud sync picks it up as the latest across devices.
        let alreadyFirst: Bool
        if let first = entries.first, first.kind == entry.kind {
            switch entry.kind {
            case .text: alreadyFirst = first.text == entry.text
            case .image: alreadyFirst = first.imageFileName == entry.imageFileName
            }
        } else {
            alreadyFirst = false
        }
        if !alreadyFirst {
            let copy = ClipboardEntry(
                kind: entry.kind,
                text: entry.text,
                imageFileName: entry.imageFileName
            )
            insertEntry(copy)
        }
    }

    func clearAll() {
        for entry in entries {
            if entry.kind == .text {
                CloudSyncEngine.shared.recordDeleted(entry.id, type: .clipboardEntry)
            }
            cleanupImageFile(for: entry)
        }
        entries.removeAll()
        scheduleSave()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func deleteEntry(id: UUID) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries.remove(at: index)
            cleanupImageFile(for: entry)
        }
        CloudSyncEngine.shared.recordDeleted(id, type: .clipboardEntry)
        scheduleSave()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func search(query: String) -> [ClipboardEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            switch entry.kind {
            case .text:
                return entry.text?.localizedCaseInsensitiveContains(query) ?? false
            case .image:
                return "image".localizedCaseInsensitiveContains(query)
            }
        }
    }

    // MARK: - Auto-delete

    static func autoDeleteInterval(for setting: String) -> TimeInterval? {
        switch setting {
        case "1h": return 3600
        case "12h": return 43200
        case "1d": return 86400
        case "7d": return 604800
        case "14d": return 1209600
        case "30d": return 2592000
        default: return nil
        }
    }

    func pruneExpiredEntries(setting: String? = nil) {
        let autoDelete = setting ?? SettingsStore.shared.clipboardAutoDelete
        guard let interval = Self.autoDeleteInterval(for: autoDelete) else { return }

        let cutoff = Date().addingTimeInterval(-interval)
        let expired = entries.filter { $0.timestamp < cutoff }
        guard !expired.isEmpty else { return }

        for entry in expired {
            cleanupImageFile(for: entry)
            if entry.kind == .text {
                CloudSyncEngine.shared.recordDeleted(entry.id, type: .clipboardEntry)
            }
        }

        entries.removeAll { $0.timestamp < cutoff }
        saveEntries()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - Image cleanup

    func cleanupImageFile(for entry: ClipboardEntry) {
        guard entry.kind == .image, let fileName = entry.imageFileName else { return }
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Cloud sync

    func applyCloudClipboardEntry(_ data: CloudClipboardRecord) {
        // Skip if this entry already exists locally (by UUID or identical text)
        guard !entries.contains(where: { $0.id == data.id }) else { return }
        guard !entries.contains(where: { $0.text == data.text }) else { return }

        let entry = ClipboardEntry(
            id: data.id,
            kind: .text,
            text: data.text,
            timestamp: data.timestamp
        )
        // Insert in chronological position (entries are sorted newest-first)
        let insertIndex = entries.firstIndex(where: { $0.timestamp < entry.timestamp }) ?? entries.endIndex
        entries.insert(entry, at: insertIndex)

        // Evict if over maxEntries
        while entries.count > maxEntries {
            let evicted = entries.removeLast()
            cleanupImageFile(for: evicted)
        }

        scheduleSave()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func removeCloudClipboardEntry(id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        if let index = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries.remove(at: index)
            cleanupImageFile(for: entry)
        }
        scheduleSave()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
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
