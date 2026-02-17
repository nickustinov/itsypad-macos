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
    private var kvsObserver: NSObjectProtocol?

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
        ClipboardStore.migrateLegacyData(to: self.storageURL, imagesDir: self.imagesDirectory)
        restoreEntries()
        migrateFromKVS()
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
            CloudSyncEngine.shared.recordChanged(entry.id)
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
                CloudSyncEngine.shared.recordDeleted(entry.id)
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
        CloudSyncEngine.shared.recordDeleted(id)
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
                CloudSyncEngine.shared.recordDeleted(entry.id)
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

    // MARK: - KVS migration (v1.6.0 iCloud sync → App Store)
    //
    // Same situation as TabStore.migrateFromKVS – see detailed comment there.
    //
    // Versions up to 1.6.0 synced clipboard entries via NSUbiquitousKeyValueStore.
    // The old code used a ClipboardCloudEntry struct (id, text, timestamp) – a
    // text-only subset of ClipboardEntry (no images in KVS due to 1MB size limit).
    // We re-declare it here as LegacyCloudClipboardEntry for decoding.
    //
    // KVS keys (from the old ClipboardStore):
    //   "clipboard"           – JSON-encoded [ClipboardCloudEntry] (text entries only)
    //   "deletedClipboardIDs" – JSON-encoded [String] of deleted entry UUIDs

    // The original struct was called ClipboardCloudEntry and was deleted in the
    // CloudKit migration (commit ddaf107). We need it back to decode KVS payloads.
    private struct LegacyCloudClipboardEntry: Codable {
        let id: UUID
        let text: String
        let timestamp: Date
    }

    private func migrateFromKVS() {
        guard !UserDefaults.standard.bool(forKey: "kvsClipboardMigrated") else { return }

        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

        if importKVSClipboard(from: kvs) { return }

        // See TabStore.migrateFromKVS for why we need the observer fallback.
        kvsObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { [weak self] _ in
            guard let self, !UserDefaults.standard.bool(forKey: "kvsClipboardMigrated") else { return }
            self.importKVSClipboard(from: kvs)
            UserDefaults.standard.set(true, forKey: "kvsClipboardMigrated")
            if let observer = self.kvsObserver {
                NotificationCenter.default.removeObserver(observer)
                self.kvsObserver = nil
            }
        }
    }

    @discardableResult
    private func importKVSClipboard(from kvs: NSUbiquitousKeyValueStore) -> Bool {
        guard let data = kvs.data(forKey: "clipboard"),
              let kvsEntries = try? JSONDecoder().decode([LegacyCloudClipboardEntry].self, from: data),
              !kvsEntries.isEmpty else { return false }

        let existingIDs = Set(entries.map { $0.id })
        let existingTexts = Set(entries.compactMap { $0.text })
        var imported = 0

        for kvsEntry in kvsEntries {
            guard !existingIDs.contains(kvsEntry.id) else { continue }
            // Dedup by text content – Universal Clipboard can create duplicates
            // with different UUIDs for the same text
            guard !existingTexts.contains(kvsEntry.text) else { continue }

            let entry = ClipboardEntry(
                id: kvsEntry.id,
                kind: .text,
                text: kvsEntry.text,
                timestamp: kvsEntry.timestamp
            )
            // Maintain newest-first sort order
            let insertIndex = entries.firstIndex(where: { $0.timestamp < entry.timestamp }) ?? entries.endIndex
            entries.insert(entry, at: insertIndex)
            imported += 1
        }

        while entries.count > maxEntries {
            let evicted = entries.removeLast()
            cleanupImageFile(for: evicted)
        }

        if imported > 0 {
            saveEntries()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }

        // Remove KVS keys to prevent re-import
        kvs.removeObject(forKey: "clipboard")
        kvs.removeObject(forKey: "deletedClipboardIDs")
        kvs.synchronize()
        UserDefaults.standard.set(true, forKey: "kvsClipboardMigrated")
        NSLog("[KVS Migration] Imported %d clipboard entries from iCloud KVS", imported)
        return true
    }

    // MARK: - Legacy data migration (non-sandboxed → sandboxed path)
    //
    // Same situation as TabStore.migrateLegacyData – see detailed comment there.
    //
    // Migrates clipboard.json and the clipboard-images/ directory from the old
    // non-sandboxed path (~/Library/Application Support/Itsypad/) into the
    // sandboxed container. Only works in the direct-download build which has the
    // temporary-exception entitlement for the old path. The App Store build can't
    // reach these files – clipboard recovery for App Store users coming from ≤1.6.0
    // is handled by the KVS migration above (text entries only; images were never
    // synced via KVS due to the 1MB size limit).

    private static func migrateLegacyData(to sandboxedURL: URL, imagesDir: URL) {
        let fm = FileManager.default

        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir else { return }
        let realHome = String(cString: home)
        let oldDir = "\(realHome)/Library/Application Support/Itsypad"
        let oldFile = "\(oldDir)/clipboard.json"
        let oldImagesDir = "\(oldDir)/clipboard-images"

        NSLog("[Migration] clipboard: oldFile=%@ sandboxed=%@ exists=%d",
              oldFile, sandboxedURL.path, fm.fileExists(atPath: oldFile))

        guard oldFile != sandboxedURL.path else { return }

        let oldFileExists = fm.fileExists(atPath: oldFile)
        let oldImagesDirExists = fm.fileExists(atPath: oldImagesDir)
        guard oldFileExists || oldImagesDirExists else { return }

        if oldFileExists {
            let oldEntries: [ClipboardEntry]
            if let data = try? Data(contentsOf: URL(fileURLWithPath: oldFile)),
               let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
                oldEntries = decoded
            } else {
                oldEntries = []
            }

            let existingEntries: [ClipboardEntry]
            if let data = try? Data(contentsOf: sandboxedURL),
               let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
                existingEntries = decoded
            } else {
                existingEntries = []
            }

            if !oldEntries.isEmpty {
                let existingIDs = Set(existingEntries.map { $0.id })
                let newEntries = oldEntries.filter { !existingIDs.contains($0.id) }
                let merged = (existingEntries + newEntries).sorted { $0.timestamp > $1.timestamp }

                if let encoded = try? JSONEncoder().encode(merged) {
                    try? encoded.write(to: sandboxedURL, options: .atomic)
                }
                NSLog("[Migration] Merged %d legacy clipboard entries", oldEntries.count)
            }

            try? fm.removeItem(atPath: oldFile)
        }

        if oldImagesDirExists {
            let sandboxedImagesPath = imagesDir.path
            try? fm.createDirectory(atPath: sandboxedImagesPath, withIntermediateDirectories: true)

            if let files = try? fm.contentsOfDirectory(atPath: oldImagesDir) {
                for file in files {
                    let src = "\(oldImagesDir)/\(file)"
                    let dst = "\(sandboxedImagesPath)/\(file)"
                    if !fm.fileExists(atPath: dst) {
                        try? fm.copyItem(atPath: src, toPath: dst)
                    }
                }
            }
            try? fm.removeItem(atPath: oldImagesDir)
            NSLog("[Migration] Merged legacy clipboard-images")
        }
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
