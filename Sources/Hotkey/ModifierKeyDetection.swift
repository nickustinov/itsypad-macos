import Carbon.HIToolbox
import Cocoa

enum ModifierKeyDetection {
    static func modifierName(for keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String? {
        switch Int(keyCode) {
        case kVK_Option:
            if flags.contains(.option) { return "left-option" }
        case kVK_RightOption:
            if flags.contains(.option) { return "right-option" }
        case kVK_Command:
            if flags.contains(.command) { return "left-command" }
        case kVK_RightCommand:
            if flags.contains(.command) { return "right-command" }
        case kVK_Control:
            if flags.contains(.control) { return "left-control" }
        case kVK_RightControl:
            if flags.contains(.control) { return "right-control" }
        case kVK_Shift:
            if flags.contains(.shift) { return "left-shift" }
        case kVK_RightShift:
            if flags.contains(.shift) { return "right-shift" }
        default:
            break
        }
        return nil
    }
}
