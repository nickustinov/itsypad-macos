import Cocoa

class ICloudSyncManager {
    static let shared = ICloudSyncManager()

    let cloudStore: KeyValueStoreProtocol
    private var observer: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    init(cloudStore: KeyValueStoreProtocol = NSUbiquitousKeyValueStore.default) {
        self.cloudStore = cloudStore

        if SettingsStore.shared.icloudSync {
            start()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if SettingsStore.shared.icloudSync {
                self.start()
            } else {
                self.stop()
            }
        }
    }

    func start() {
        guard observer == nil else { return }
        cloudStore.synchronize()
        TabStore.shared.lastICloudSync = Date()
        TabStore.shared.mergeCloudTabs(from: cloudStore)
        ClipboardStore.shared.mergeCloudClipboard(from: cloudStore)

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            TabStore.shared.mergeCloudTabs(from: self.cloudStore)
            ClipboardStore.shared.mergeCloudClipboard(from: self.cloudStore)
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        TabStore.shared.clearCloudData(from: cloudStore)
        ClipboardStore.shared.clearCloudData(from: cloudStore)
        cloudStore.synchronize()
    }

    func check() {
        guard SettingsStore.shared.icloudSync else { return }
        cloudStore.synchronize()
        TabStore.shared.mergeCloudTabs(from: cloudStore)
        ClipboardStore.shared.mergeCloudClipboard(from: cloudStore)
    }

    func saveTabs() {
        guard SettingsStore.shared.icloudSync else { return }
        TabStore.shared.saveTabsToCloud(cloudStore)
        cloudStore.synchronize()
        TabStore.shared.lastICloudSync = Date()
    }

    func saveClipboard() {
        guard SettingsStore.shared.icloudSync else { return }
        ClipboardStore.shared.saveClipboardToCloud(cloudStore)
        cloudStore.synchronize()
        TabStore.shared.lastICloudSync = Date()
    }
}
