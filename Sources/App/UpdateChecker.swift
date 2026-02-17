#if !APPSTORE
import AppKit
import os.log

private let log = Logger(subsystem: "com.nickustinov.itsypad", category: "UpdateChecker")

enum UpdateChecker {

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    static func check() {
        let url = URL(string: "https://api.github.com/repos/nickustinov/itsypad-macos/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    showAlert(message: "Failed to check for updates: \(error.localizedDescription)")
                    return
                }
                guard let data else {
                    showAlert(message: "Failed to check for updates: no data received.")
                    return
                }
                do {
                    let release = try JSONDecoder().decode(Release.self, from: data)
                    let remoteVersion = release.tag_name.hasPrefix("v")
                        ? String(release.tag_name.dropFirst())
                        : release.tag_name
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                    if isNewer(remoteVersion, than: currentVersion) {
                        showUpdateAvailable(version: release.tag_name, url: release.html_url)
                    } else {
                        showUpToDate(version: currentVersion)
                    }
                } catch {
                    showAlert(message: "Failed to parse update info: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    private static func isNewer(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(remoteParts.count, currentParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }

    private static func showUpdateAvailable(version: String, url: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "update.available.title", defaultValue: "Update available: \(version)")
        alert.informativeText = String(localized: "update.available.message", defaultValue: "A new version of Itsypad is available.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "update.available.open_downloads", defaultValue: "Open downloads"))
        alert.addButton(withTitle: String(localized: "update.available.later", defaultValue: "Later"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func showUpToDate(version: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "update.up_to_date.title", defaultValue: "You're up to date")
        alert.informativeText = String(localized: "update.up_to_date.message", defaultValue: "Itsypad \(version) is the latest version.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "update.up_to_date.ok", defaultValue: "OK"))
        alert.runModal()
    }

    private static func showAlert(message: String) {
        log.error("\(message)")
        let alert = NSAlert()
        alert.messageText = String(localized: "update.failed.title", defaultValue: "Update check failed")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "update.failed.ok", defaultValue: "OK"))
        alert.runModal()
    }
}
#endif
