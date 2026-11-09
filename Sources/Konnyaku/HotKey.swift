import AppKit
import Carbon.HIToolbox

/// A global shortcut: a Carbon key code and Carbon modifier flags, plus the
/// key's label in the keyboard layout it was recorded with.
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// Captured at record time, so a printable key shows what the user's
    /// layout types (e.g. "Z" on a German layout, not "Y").
    var keyLabel: String

    static let `default` = HotKey(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(controlKey | optionKey),
        keyLabel: "T"
    )

    static let defaultsKey = "translateHotKey"

    var isValid: Bool {
        problem == nil
    }

    /// What the user should change, in Settings' words; nil if usable.
    /// A global hotkey takes the keystroke from every app, so one modifier
    /// is not enough: ⇧ and ⌥ type characters (é, or @ on many European
    /// layouts), ⌘ alone holds app shortcuts like ⌘C (including the ⌘C
    /// SelectionReader sends), and ⌃ alone holds text navigation like ⌃A.
    var problem: String? {
        let hasControlOrCommand = carbonModifiers & UInt32(cmdKey | controlKey) != 0
        let allModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let modifierCount = (carbonModifiers & allModifiers).nonzeroBitCount
        if !hasControlOrCommand || modifierCount < 2 {
            return "Use ⌃ or ⌘ plus one more modifier key, like ⌃⌥ or ⇧⌘."
        }
        return nil
    }

    /// The standard macOS order: ⌃⌥⇧⌘, then the key.
    var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 {
            text += "⌃"
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            text += "⌥"
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            text += "⇧"
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            text += "⌘"
        }
        return text + keyLabel
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        return modifiers
    }

    /// Keys that don't type a visible character, labelled as in macOS menus.
    static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12",
        kVK_F13: "F13",
        kVK_F14: "F14",
        kVK_F15: "F15",
        kVK_F16: "F16",
        kVK_F17: "F17",
        kVK_F18: "F18",
        kVK_F19: "F19",
        kVK_F20: "F20",
    ]

    static func load(from defaults: UserDefaults) -> HotKey? {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return nil
        }
        guard let hotKey = try? JSONDecoder().decode(HotKey.self, from: data) else {
            return nil
        }
        // A hand-edited or corrupt value must not become an unusable shortcut.
        guard hotKey.isValid else {
            return nil
        }
        return hotKey
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

// In an extension so the struct keeps its memberwise initializer.
extension HotKey {
    /// Nil when the key has no label we can show (e.g. Help, or a key that
    /// types nothing in the ASCII-capable layout).
    init?(event: NSEvent) {
        let keyCode = Int(event.keyCode)
        guard let label = Self.label(forKeyCode: keyCode) else {
            return nil
        }
        self.init(
            keyCode: UInt32(keyCode),
            carbonModifiers: Self.carbonModifiers(from: event.modifierFlags),
            keyLabel: label
        )
    }

    static func label(forKeyCode keyCode: Int) -> String? {
        if let special = specialKeyLabels[keyCode] {
            return special
        }
        if let keypad = keypadKeyLabels[keyCode] {
            return "Keypad " + keypad
        }
        // The ASCII-capable layout (e.g. U.S. or German, never Kana input)
        // with no modifiers, so ⌥E shows "E", not "´" or "え".
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let typed = KeyboardLayout.typedCharacters(in: source, modifiers: 0) else {
            return nil
        }
        guard keyCode < typed.count else {
            return nil
        }
        let label = typed[keyCode].trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty {
            return nil
        }
        // Keys like Help or keypad Clear type control or private-use
        // characters that no font draws.
        let privateUse: ClosedRange<UInt32> = 0xE000...0xF8FF
        let hasUndrawable = label.unicodeScalars.contains { scalar in
            let isControl = CharacterSet.controlCharacters.contains(scalar)
            return isControl || privateUse.contains(scalar.value)
        }
        if hasUndrawable {
            return nil
        }
        return label.uppercased()
    }

    /// Named so they don't look like the number row.
    static let keypadKeyLabels: [Int: String] = [
        kVK_ANSI_Keypad0: "0",
        kVK_ANSI_Keypad1: "1",
        kVK_ANSI_Keypad2: "2",
        kVK_ANSI_Keypad3: "3",
        kVK_ANSI_Keypad4: "4",
        kVK_ANSI_Keypad5: "5",
        kVK_ANSI_Keypad6: "6",
        kVK_ANSI_Keypad7: "7",
        kVK_ANSI_Keypad8: "8",
        kVK_ANSI_Keypad9: "9",
        kVK_ANSI_KeypadDecimal: ".",
        kVK_ANSI_KeypadPlus: "+",
        kVK_ANSI_KeypadMinus: "-",
        kVK_ANSI_KeypadMultiply: "*",
        kVK_ANSI_KeypadDivide: "/",
        kVK_ANSI_KeypadEquals: "=",
    ]
}
