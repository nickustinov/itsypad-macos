import Cocoa

enum AccessibilityHelper {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        let alert = NSAlert()
        alert.messageText = String(localized: "accessibility.alert.title", defaultValue: "Accessibility permission required")
        alert.informativeText = String(localized: "accessibility.alert.message", defaultValue: "Itsypad needs accessibility access to paste into other apps. The item has been copied to your clipboard – you can paste manually with ⌘V.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "accessibility.alert.open_settings", defaultValue: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "accessibility.alert.cancel", defaultValue: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    static func simulatePaste() {
        let keyCode: CGKeyCode = 9 // V
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
