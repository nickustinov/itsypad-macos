import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: View {
    var label: String
    @Binding var shortcut: String
    @Binding var shortcutKeys: ShortcutKeys?
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)

                Spacer()

                Button {
                    isRecording.toggle()
                } label: {
                    if isRecording {
                        Text(String(localized: "shortcut.press_keys", defaultValue: "Press keys..."))
                            .foregroundStyle(.orange)
                    } else if shortcut.isEmpty {
                        Text(String(localized: "shortcut.click_to_record", defaultValue: "Click to record"))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(shortcut)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .buttonStyle(.bordered)
                .background(
                    ShortcutRecorderHelper(
                        isRecording: $isRecording,
                        shortcut: $shortcut,
                        shortcutKeys: $shortcutKeys
                    )
                )

                if !shortcut.isEmpty {
                    Button {
                        shortcut = ""
                        shortcutKeys = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Text(String(localized: "shortcut.hint", defaultValue: "Record a key combination (e.g. ⌃⌥Space) or tap a modifier key 3 times for a triple-tap shortcut. Left and right modifier keys are distinguished."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ShortcutRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var shortcut: String
    @Binding var shortcutKeys: ShortcutKeys?

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutRecorded = { keys, displayString in
            shortcut = displayString
            shortcutKeys = keys
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? ShortcutRecorderNSView {
            view.isRecording = isRecording
        }
    }
}

class ShortcutRecorderNSView: NSView {
    var isRecording = false
    var onShortcutRecorded: ((ShortcutKeys, String) -> Void)?

    private var monitor: Any?
    private var tripleTapTimestamps: [String: [Date]] = [:]

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupMonitor()
    }

    private func modifierSymbol(_ mod: String) -> String {
        if mod.contains("option") { return "⌥" }
        if mod.contains("control") { return "⌃" }
        if mod.contains("shift") { return "⇧" }
        if mod.contains("command") { return "⌘" }
        return "?"
    }

    private func setupMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let keyCode = event.keyCode
                let modifier = ModifierKeyDetection.modifierName(for: keyCode, flags: flags)

                if let mod = modifier {
                    let now = Date()
                    var timestamps = self.tripleTapTimestamps[mod] ?? []
                    timestamps.append(now)
                    timestamps = timestamps.filter { now.timeIntervalSince($0) < 0.5 }
                    self.tripleTapTimestamps[mod] = timestamps

                    if timestamps.count >= 3 {
                        self.tripleTapTimestamps[mod] = []
                        let symbol = self.modifierSymbol(mod)
                        let side = mod.hasPrefix("left-") ? "L" : "R"
                        let keys = ShortcutKeys(modifiers: 0, keyCode: 0, isTripleTap: true, tapModifier: mod)
                        self.onShortcutRecorded?(keys, "\(symbol)\(symbol)\(symbol) \(side)")
                        return nil
                    }
                }
                return event
            }

            if event.type == .keyDown {
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard !modifiers.isEmpty else { return event }

                let keyCode = event.keyCode
                let displayString = self.shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
                let keys = ShortcutKeys(
                    modifiers: modifiers.rawValue,
                    keyCode: keyCode,
                    isTripleTap: false,
                    tapModifier: nil
                )
                self.onShortcutRecorded?(keys, displayString)
                return nil
            }

            return event
        }
    }

    private func shortcutDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += keyCodeToString(keyCode)
        return result
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let char = keyCodeToCharacter(keyCode) {
                return char.uppercased()
            }
            return "?"
        }
    }

    private func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let result = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard result == noErr && length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
