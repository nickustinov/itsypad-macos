import Cocoa

// Shared scaffolding for one-shot NSUbiquitousKeyValueStore migration.
//
// Background: versions up to 1.6.0 used NSUbiquitousKeyValueStore (iCloud KVS)
// for syncing tabs and clipboard entries. In 1.8.0 we migrated to CloudKit via
// CKSyncEngine and stripped all KVS code. However, users who had KVS sync
// enabled still have data sitting in iCloud KVS.
//
// When a user switches from the direct-download version to the App Store
// version, the sandboxed build can't read the old local session.json. CloudKit
// users are fine, but KVS-era users (v1.6.0 and earlier) would lose their data.
// Both distributions share the same KVS identifier, so we can import from KVS.
//
// This class handles: check flag, synchronize KVS, try immediate import,
// register one-shot observer fallback. The actual data import logic is provided
// by the caller via the `importData` closure.
//
// This migration can be removed once we're confident no users remain on <=1.6.0.

final class KVSMigration {
    private let flagKey: String
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - flagKey: UserDefaults key used to track whether migration has completed.
    ///   - importData: Called with the KVS store. Return `true` if data was found and imported.
    init(flagKey: String, importData: @escaping (NSUbiquitousKeyValueStore) -> Bool) {
        self.flagKey = flagKey

        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

        if importData(kvs) { return }

        // synchronize() only hints the system to pull data -- KVS might not be
        // available yet on first launch (e.g. slow network, fresh iCloud login).
        // Register a one-shot observer: didChangeExternallyNotification fires
        // once initial sync completes, at which point the data is either there
        // or genuinely doesn't exist.
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { [weak self] _ in
            guard let self, !UserDefaults.standard.bool(forKey: self.flagKey) else { return }
            _ = importData(kvs)
            // Mark done after first notification regardless -- if no data was found,
            // initial sync has completed and the KVS store is genuinely empty.
            UserDefaults.standard.set(true, forKey: self.flagKey)
            if let observer = self.observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
