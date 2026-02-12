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

struct ClipboardCloudEntry: Codable {
    let id: UUID
    let text: String
    let timestamp: Date
}

class ClipboardStore {
    static let shared = ClipboardStore()

    var entries: [ClipboardEntry] = []

    private var timer: Timer?
    private var lastChangeCount: Int
    private var saveDebounceWork: DispatchWorkItem?
    private let storageURL: URL
    let imagesDirectory: URL

    static let didChangeNotification = Notification.Name("clipboardStoreDidChange")
    static let clipboardTabSelectedNotification = Notification.Name("clipboardTabSelected")

    private let maxEntries = 1000
    private static let cloudClipboardKey = "clipboard"
    private static let maxCloudEntries = 200

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
    }

    func clearAll() {
        for entry in entries {
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

    // MARK: - Image cleanup

    func cleanupImageFile(for entry: ClipboardEntry) {
        guard entry.kind == .image, let fileName = entry.imageFileName else { return }
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - iCloud sync

    func saveClipboardToCloud(_ cloudStore: KeyValueStoreProtocol) {
        let textEntries = entries.filter { $0.kind == .text && $0.text != nil }
        let cloudEntries = textEntries.prefix(Self.maxCloudEntries).map {
            ClipboardCloudEntry(id: $0.id, text: $0.text!, timestamp: $0.timestamp)
        }
        guard let data = try? JSONEncoder().encode(Array(cloudEntries)) else { return }
        cloudStore.setData(data, forKey: Self.cloudClipboardKey)
    }

    func mergeCloudClipboard(from cloudStore: KeyValueStoreProtocol) {
        guard SettingsStore.shared.icloudSync else { return }
        guard let data = cloudStore.data(forKey: Self.cloudClipboardKey),
              let cloudEntries = try? JSONDecoder().decode([ClipboardCloudEntry].self, from: data) else { return }

        let existingIDs = Set(entries.map(\.id))
        var inserted = false

        for cloudEntry in cloudEntries {
            guard !existingIDs.contains(cloudEntry.id) else { continue }
            let entry = ClipboardEntry(
                id: cloudEntry.id,
                kind: .text,
                text: cloudEntry.text,
                timestamp: cloudEntry.timestamp
            )
            // Insert in chronological position (entries are sorted newest-first)
            let insertIndex = entries.firstIndex(where: { $0.timestamp < entry.timestamp }) ?? entries.endIndex
            entries.insert(entry, at: insertIndex)
            inserted = true
        }

        // Evict if over maxEntries
        while entries.count > maxEntries {
            let evicted = entries.removeLast()
            cleanupImageFile(for: evicted)
        }

        if inserted {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    func clearCloudData(from cloudStore: KeyValueStoreProtocol) {
        cloudStore.removeObject(forKey: Self.cloudClipboardKey)
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
        ICloudSyncManager.shared.saveClipboard()
    }

    private func restoreEntries() {
        guard let data = try? Data(contentsOf: storageURL),
              let restored = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = restored
    }
}
