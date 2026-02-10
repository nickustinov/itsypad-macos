import Cocoa

enum AccessibilityHelper {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = "Itsypad needs accessibility access to paste into other apps. The item has been copied to your clipboard — you can paste manually with ⌘V."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
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
