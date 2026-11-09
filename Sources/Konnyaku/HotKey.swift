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
    var problem: String? {
        // Shift alone is not enough: ⇧+letter is just typing a capital.
        let required = UInt32(cmdKey | controlKey | optionKey)
        if carbonModifiers & required == 0 {
            return "Add ⌘, ⌃ or ⌥ to the shortcut."
        }
        // A global ⌘+key would take ⌘C, ⌘V and the like from every app,
        // including the ⌘C that SelectionReader sends to copy a selection.
        if carbonModifiers == UInt32(cmdKey) {
            return "⌘ alone would block app shortcuts like ⌘C. Add ⌃, ⌥ or ⇧ too."
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

    /// Nil when the event has no usable key label (e.g. a dead key).
    init?(event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let label: String
        if let special = Self.specialKeyLabels[keyCode] {
            label = special
        } else {
            // Without modifiers, so ⌥E shows "E", not "´".
            let typed = event.characters(byApplyingModifiers: []) ?? ""
            let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            label = trimmed.uppercased()
        }
        self.init(
            keyCode: UInt32(keyCode),
            carbonModifiers: Self.carbonModifiers(from: event.modifierFlags),
            keyLabel: label
        )
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
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
