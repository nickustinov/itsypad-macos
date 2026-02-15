import Foundation
import os.log

final class G2SyncEngine: ObservableObject {
    static let shared = G2SyncEngine()

    private static let baseURL = "http://localhost:3000"

    enum State: Equatable {
        case disabled
        case pairing(code: String)
        case linked
    }

    @Published private(set) var state: State = .disabled

    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.nickustinov.itsypad", category: "G2Sync")

    private static let deviceIdKey = "g2DeviceId"
    private static let secretKey = "g2Secret"
    private static let linkedKey = "g2Linked"
    private static let versionKey = "g2Version"

    private var deviceId: String? {
        get { defaults.string(forKey: Self.deviceIdKey) }
        set { defaults.set(newValue, forKey: Self.deviceIdKey) }
    }

    private var secret: String? {
        get { defaults.string(forKey: Self.secretKey) }
        set { defaults.set(newValue, forKey: Self.secretKey) }
    }

    private var isLinked: Bool {
        get { defaults.bool(forKey: Self.linkedKey) }
        set { defaults.set(newValue, forKey: Self.linkedKey) }
    }

    private var version: Int {
        get { defaults.integer(forKey: Self.versionKey) }
        set { defaults.set(newValue, forKey: Self.versionKey) }
    }

    private var pairingTimer: Timer?
    private var syncTimer: Timer?
    private var pushDebounceWork: DispatchWorkItem?
    private var pendingPushIDs: Set<UUID> = []
    private var pendingDeleteIDs: Set<UUID> = []

    private var authHeader: String? {
        guard let deviceId, let secret else { return nil }
        return "Bearer \(deviceId):\(secret)"
    }

    // MARK: - Public API

    func startIfEnabled() {
        guard SettingsStore.shared.g2SyncEnabled else { return }
        enable()
    }

    func enable() {
        if deviceId == nil {
            deviceId = UUID().uuidString
        }
        if secret == nil {
            secret = generateSecret()
        }

        if isLinked {
            state = .linked
            startSyncTimers()
            return
        }

        let code = generatePairingCode()
        state = .pairing(code: code)

        Task {
            await registerPairingCode(code)
            await MainActor.run { startPairingPoll() }
        }
    }

    func disable() {
        stopAllTimers()
        pushDebounceWork?.cancel()
        pushDebounceWork = nil

        if isLinked {
            Task { await revokeSession() }
        }

        isLinked = false
        state = .disabled
    }

    func schedulePush(id: UUID) {
        guard state == .linked else { return }
        pendingDeleteIDs.remove(id)
        pendingPushIDs.insert(id)
        scheduleFlush()
    }

    func scheduleDelete(id: UUID) {
        guard state == .linked else { return }
        pendingPushIDs.remove(id)
        pendingDeleteIDs.insert(id)
        scheduleFlush()
    }

    private func scheduleFlush() {
        pushDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let pushIDs = self.pendingPushIDs
            let deleteIDs = self.pendingDeleteIDs
            self.pendingPushIDs.removeAll()
            self.pendingDeleteIDs.removeAll()
            Task {
                for id in pushIDs { await self.pushNote(id: id) }
                for id in deleteIDs { await self.deleteNote(id: id) }
            }
        }
        pushDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    // MARK: - Networking

    private func registerPairingCode(_ code: String) async {
        guard let deviceId, let secret else { return }

        let url = URL(string: "\(Self.baseURL)/api/pair")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["code": code, "deviceId": deviceId, "secret": secret]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                logger.info("Pairing code registered: \(code)")
            } else {
                logger.error("Failed to register pairing code")
            }
        } catch {
            logger.error("Failed to register pairing code: \(error)")
        }
    }

    private func startPairingPoll() {
        pairingTimer?.invalidate()
        pairingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkPairingStatus() }
        }
    }

    private func checkPairingStatus() async {
        guard let authHeader else { return }

        let url = URL(string: "\(Self.baseURL)/api/pair/status")!
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            struct StatusResponse: Decodable { let linked: Bool }
            let status = try JSONDecoder().decode(StatusResponse.self, from: data)

            if status.linked {
                await MainActor.run {
                    pairingTimer?.invalidate()
                    pairingTimer = nil
                    isLinked = true
                    state = .linked
                    startSyncTimers()
                }
                await pushAllNotes()
                logger.info("G2 device linked successfully")
            }
        } catch {
            logger.error("Failed to check pairing status: \(error)")
        }
    }

    private func pushAllNotes() async {
        guard let authHeader else { return }

        let tabs = await MainActor.run {
            TabStore.shared.tabs.filter { $0.fileURL == nil }
        }

        let formatter = ISO8601DateFormatter()
        let notes: [[String: Any]] = tabs.map { tab in
            [
                "id": tab.id.uuidString,
                "name": tab.name,
                "content": tab.content,
                "lastModified": formatter.string(from: tab.lastModified),
            ]
        }

        let url = URL(string: "\(Self.baseURL)/api/notes")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["notes": notes, "version": version + 1]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 200 {
                logger.info("Pushed \(notes.count) notes")
            } else {
                logger.error("Push all failed with status \(http.statusCode)")
            }
        } catch {
            logger.error("Failed to push all notes: \(error)")
        }
    }

    private func pushNote(id: UUID) async {
        guard let authHeader else { return }

        let tab = await MainActor.run {
            TabStore.shared.tabs.first { $0.id == id && $0.fileURL == nil }
        }
        guard let tab else { return }

        let formatter = ISO8601DateFormatter()
        let url = URL(string: "\(Self.baseURL)/api/notes/\(id.uuidString)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "name": tab.name,
            "content": tab.content,
            "lastModified": formatter.string(from: tab.lastModified),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 200 {
                logger.info("Pushed note \(id.uuidString.prefix(8))")
            } else {
                logger.error("Push note failed with status \(http.statusCode)")
            }
        } catch {
            logger.error("Failed to push note: \(error)")
        }
    }

    private func deleteNote(id: UUID) async {
        guard let authHeader else { return }

        let url = URL(string: "\(Self.baseURL)/api/notes/\(id.uuidString)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 200 {
                logger.info("Deleted note \(id.uuidString.prefix(8))")
            } else {
                logger.error("Delete note failed with status \(http.statusCode)")
            }
        } catch {
            logger.error("Failed to delete note: \(error)")
        }
    }

    private func pullNotes() async {
        guard let authHeader else {
            logger.warning("pullNotes: no authHeader, skipping")
            return
        }

        logger.info("pullNotes: fetching...")

        let url = URL(string: "\(Self.baseURL)/api/notes")!
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            logger.info("pullNotes: status \(http.statusCode)")
            guard http.statusCode == 200 else { return }

            struct NotePayload: Decodable {
                let id: String
                let name: String
                let content: String
                let lastModified: String
            }
            struct NotesResponse: Decodable {
                let notes: [NotePayload]
                let version: Int
            }

            let store = try JSONDecoder().decode(NotesResponse.self, from: data)
            let remoteIDs = Set(store.notes.compactMap { UUID(uuidString: $0.id) })

            logger.info("pullNotes: \(store.notes.count) remote notes, v\(store.version)")

            let formatter = ISO8601DateFormatter()

            await MainActor.run {
                let localScratch = TabStore.shared.tabs.filter { $0.fileURL == nil }
                let localIDs = Set(localScratch.map { $0.id })
                let toRemove = localIDs.subtracting(remoteIDs).subtracting(self.pendingPushIDs)
                logger.info("pullNotes: \(localScratch.count) local scratch, \(toRemove.count) to remove")

                for note in store.notes {
                    guard let noteId = UUID(uuidString: note.id) else { continue }
                    let lastModified = formatter.date(from: note.lastModified) ?? Date()
                    TabStore.shared.applyG2Note(
                        id: noteId,
                        name: note.name,
                        content: note.content,
                        lastModified: lastModified
                    )
                }

                TabStore.shared.removeG2DeletedNotes(keeping: remoteIDs, pendingPush: self.pendingPushIDs)
                self.version = store.version
            }
        } catch {
            logger.error("pullNotes: \(error)")
        }
    }

    private func revokeSession() async {
        guard let authHeader else { return }

        let url = URL(string: "\(Self.baseURL)/api/session")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                logger.info("Revoke session: \(http.statusCode)")
            }
        } catch {
            logger.error("Failed to revoke session: \(error)")
        }
    }

    // MARK: - Timers

    private func startSyncTimers() {
        syncTimer?.invalidate()
        logger.info("startSyncTimers: starting 30s poll")
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.pullNotes() }
        }
    }

    private func stopAllTimers() {
        pairingTimer?.invalidate()
        pairingTimer = nil
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Helpers

    private func generatePairingCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    private func generateSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
