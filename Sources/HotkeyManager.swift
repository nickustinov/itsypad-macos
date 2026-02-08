import Cocoa
import Carbon.HIToolbox

class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeyRef: EventHotKeyRef?
    private var hotkeyID: EventHotKeyID?

    // Triple-tap tracking
    private var modifierPressTimestamps: [String: [Date]] = [:]
    private let tripleTapWindow: TimeInterval = 0.5
    private var localEventMonitor: Any?

    private init() {
        installCarbonHandler()
        installTripleTapMonitor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .settingsChanged,
            object: nil
        )
    }

    @objc private func settingsChanged() {
        reregister()
    }

    // MARK: - Carbon hotkeys

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                DispatchQueue.main.async {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.toggleWindow()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    func register() {
        unregister()

        guard let keys = SettingsStore.shared.shortcutKeys, !keys.isTripleTap else { return }

        let id = EventHotKeyID(signature: OSType(0x4950_4144), id: 1) // "IPAD"
        var ref: EventHotKeyRef?

        let modifiers = carbonModifiers(from: NSEvent.ModifierFlags(rawValue: keys.modifiers))

        let status = RegisterEventHotKey(
            UInt32(keys.keyCode),
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            hotkeyRef = ref
            hotkeyID = id
        }
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
            hotkeyID = nil
        }
    }

    func reregister() {
        unregister()
        register()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    // MARK: - Triple-tap monitor

    private func installTripleTapMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard let modifier = ModifierKeyDetection.modifierName(for: event.keyCode, flags: flags) else { return }

        let now = Date()
        var timestamps = modifierPressTimestamps[modifier] ?? []
        timestamps.append(now)
        timestamps = timestamps.filter { now.timeIntervalSince($0) < tripleTapWindow }
        modifierPressTimestamps[modifier] = timestamps

        if timestamps.count >= 3 {
            modifierPressTimestamps[modifier] = []

            guard let keys = SettingsStore.shared.shortcutKeys,
                  keys.isTripleTap,
                  let tap = keys.tapModifier else { return }

            // Exact match, or backward-compat with old format (e.g. "option" matches both sides)
            let baseModifier = modifier.replacingOccurrences(of: "left-", with: "").replacingOccurrences(of: "right-", with: "")
            guard modifier == tap || baseModifier == tap else { return }

            DispatchQueue.main.async {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.toggleWindow()
                }
            }
        }
    }

    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
