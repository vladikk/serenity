import AppKit
import Carbon.HIToolbox

enum HotkeyAction: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable {
    case toggle, play, stop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .toggle: return "Play / Stop"
        case .play: return "Play"
        case .stop: return "Stop"
        }
    }
}

struct Hotkey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt  // NSEvent.ModifierFlags raw value
    var key: String

    var display: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key
    }

    fileprivate var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    private static let functionKeys: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19",
    ]

    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
    ]

    /// Names the key using the ASCII-capable layout, so a Cyrillic/Hebrew layout still shows "P" rather than "З".
    private static func asciiName(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw in
            UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode, UInt16(kUCKeyActionDisplay),
                           0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                           &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    /// Builds a hotkey from a key press. Requires ⌘, ⌥ or ⌃ unless it's a function key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let fn = Self.functionKeys[event.keyCode]
        guard fn != nil || !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        guard let name = fn ?? Self.specialKeys[event.keyCode]
                ?? Self.asciiName(keyCode: event.keyCode), !name.isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = flags.rawValue
        key = name
    }
}

/// System-wide hotkeys via Carbon, which works without Accessibility permission.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotkeyCenter.shared.handlers[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(_ bindings: [(Hotkey, () -> Void)]) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        handlers = [:]
        for (i, (hotkey, handler)) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x53524E54), id: UInt32(i + 1))  // 'SRNT'
            let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                handlers[id.id] = handler
            } else {
                NSLog("Serenity: could not register hotkey \(hotkey.display) (\(status))")
            }
        }
    }
}
