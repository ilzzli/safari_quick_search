import AppKit
import Carbon

enum HotkeyConfig {
    // ⌥⌘N
    static let panelKeyCode = UInt32(kVK_ANSI_N)
    static let panelEventModifiers: NSEvent.ModifierFlags = [.option, .command]
    static let panelModifiers = UInt32(optionKey | cmdKey)
    static let panelID = EventHotKeyID(signature: 0x53515348, id: 1)
}
