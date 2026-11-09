import AppKit
import Carbon.HIToolbox

/// A global shortcut: a Carbon key code and Carbon modifier flags.
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// ⌃⌥ and the key at T's position on the keyboard.
    static let `default` = HotKey(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(controlKey | optionKey)
    )

    /// The Carbon modifiers a shortcut can use.
    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)

    static let defaultsKey = "translateHotKey"

    /// What the recorder does with a shortcut.
    enum Verdict: Equatable {
        /// Save it, nothing to warn about.
        case ok
        /// Save it, but say which keys the user loses (a sentence that
        /// names the shortcut).
        case warning(String)
        /// Don't save it; the sentence says what to change.
        case blocked(String)
    }

    /// Why a shortcut can't be saved at all.
    enum Block: Equatable {
        /// No ⌘, ⌃ or ⌥ and not an F-key, so the key still has to type.
        case typesCharacter
        /// One of Konnyaku's own shortcuts in the current keyboard layout.
        case konnyakuShortcut
    }

    private var hasCommand: Bool {
        carbonModifiers & UInt32(cmdKey) != 0
    }

    /// Blocks only what would make the Mac hard to use: a key that still
    /// has to type, and the shortcuts Konnyaku itself uses. Builds no name,
    /// so load and layout changes can ask cheaply.
    var block: Block? {
        block(commandCharacters: Self.commandCharacters(keyCode: Int(keyCode)))
    }

    /// `block`, given the characters the key can be matched by (only asked
    /// for when the modifiers don't already decide).
    func block(commandCharacters characters: @autoclosure () -> Set<String>) -> Block? {
        let shortcutModifiers = UInt32(cmdKey | controlKey | optionKey)
        let hasShortcutModifier = carbonModifiers & shortcutModifiers != 0
        if !hasShortcutModifier {
            // F-keys type nothing, so they work alone (F13 is a common pick).
            let isFunctionKey = Self.functionKeyCodes.contains(Int(keyCode))
            if !isFunctionKey {
                return .typesCharacter
            }
        }
        if hasCommand && konnyakuShortcutCharacter(in: characters()) != nil {
            return .konnyakuShortcut
        }
        return nil
    }

    /// Which of Konnyaku's own shortcuts this is on the current layout, as
    /// shown in menus (e.g. "⌘C"), or nil.
    var konnyakuShortcutName: String? {
        // All of them use ⌘.
        if !hasCommand {
            return nil
        }
        let characters = Self.commandCharacters(keyCode: Int(keyCode))
        guard let character = konnyakuShortcutCharacter(in: characters) else {
            return nil
        }
        return Self.modifierSymbols(carbonModifiers) + character.uppercased()
    }

    /// The character of the Konnyaku shortcut this matches, given the
    /// characters the key can be matched by.
    private func konnyakuShortcutCharacter(in characters: Set<String>) -> String? {
        let modifiers = Int(carbonModifiers)
        let shortcut = Self.konnyakuShortcuts.first { shortcut in
            shortcut.modifiers == modifiers && characters.contains(shortcut.character)
        }
        return shortcut?.character
    }

    /// A global hotkey takes the keystroke from every app. Most choices are
    /// the user's to make, so this only warns about what they lose, and
    /// blocks only what `block` names. `isSystemShortcut` is
    /// GlobalHotKey.isSystemShortcut(_:), passed in so tests don't depend
    /// on this Mac's settings; it is only asked for shortcuts that aren't
    /// blocked.
    func verdict(isSystemShortcut: @autoclosure () -> Bool) -> Verdict {
        switch block {
        case .typesCharacter:
            return .blocked("Add ⌘, ⌃ or ⌥ so you can still type this key.")
        case .konnyakuShortcut:
            return .blocked("\(displayString) is used inside Konnyaku. Try a different shortcut.")
        case nil:
            break
        }
        if isSystemShortcut() {
            return .warning(
                "\(displayString) is also a macOS shortcut, so one of the two won't work. "
                    + "Pick another if you need both."
            )
        }
        if let appleMenuItem = appleMenuItem {
            return .warning("\(displayString) is also \(appleMenuItem); that won't work while it's your shortcut.")
        }
        if carbonModifiers == UInt32(cmdKey) {
            return .warning(
                "\(displayString) may also be a shortcut in other apps, like ⌘C for Copy; "
                    + "that will stop working."
            )
        }
        // ⌥ and ⌃ without ⌘ are what typing and text editing use; ⇧ doesn't
        // change that.
        let withoutShift = carbonModifiers & ~UInt32(shiftKey)
        let isOptionOnly = withoutShift == UInt32(optionKey)
        let isControlOnly = withoutShift == UInt32(controlKey)
        if !isOptionOnly && !isControlOnly {
            return .ok
        }
        // F-keys neither type nor edit.
        if Self.functionKeyCodes.contains(Int(keyCode)) {
            return .ok
        }
        if isOptionOnly {
            return .warning(
                "\(displayString) may also type a character or edit text in other apps "
                    + "(like ⌥E for é, or ⌥⌫ to delete a word); that will stop working."
            )
        }
        return .warning(
            "\(displayString) may also edit text or switch tabs in other apps "
                + "(like ⌃A or ⌃Tab); that will stop working."
        )
    }

    /// The Apple menu item this shortcut also is, by name.
    private var appleMenuItem: String? {
        // All of them use ⌘.
        if !hasCommand {
            return nil
        }
        let modifiers = Int(carbonModifiers)
        let character = Self.commandLayerCharacter(keyCode: Int(keyCode))
        let item = Self.appleMenuItems.first { item in
            item.modifiers == modifiers && item.character == character
        }
        return item?.name
    }

    /// Konnyaku's own ⌘ shortcuts, which would stop working inside it:
    /// ⌘C is the editor's Copy and the copy SelectionReader sends;
    /// ⇧⌘C and ⇧⌘R are ContentView's Copy and Translate Again; ⌘E is the
    /// popup's "open editor" (TranslatePanel.handle).
    private static let konnyakuShortcuts: [(modifiers: Int, character: String)] = [
        (cmdKey, "c"),
        (cmdKey, "e"),
        (shiftKey | cmdKey, "c"),
        (shiftKey | cmdKey, "r"),
    ]

    /// Apple menu items that CopySymbolicHotKeys doesn't list.
    private static let appleMenuItems: [(modifiers: Int, character: String, name: String)] = [
        (controlKey | cmdKey, "q", "Lock Screen"),
        (shiftKey | cmdKey, "q", "Log Out"),
        (optionKey | shiftKey | cmdKey, "q", "Log Out"),
        (optionKey | cmdKey, "\u{1B}", "Force Quit"),
    ]

    /// Where the characters above sit on a U.S. keyboard, for when there
    /// is no layout to ask.
    private static let usCommandCharacters: [Int: String] = [
        kVK_ANSI_C: "c",
        kVK_ANSI_E: "e",
        kVK_ANSI_R: "r",
        kVK_ANSI_Q: "q",
        kVK_Escape: "\u{1B}",
    ]

    /// The standard macOS order: ⌃⌥⇧⌘, then the key as the current layout
    /// labels it (e.g. "Y" for T's position on Dvorak).
    /// Builds the label from the keyboard layout on every call; views use
    /// GlobalHotKey's cached names instead.
    var displayString: String {
        let text = Self.modifierSymbols(carbonModifiers)
        let keyLabel = Self.label(forKeyCode: Int(keyCode)) ?? "Key \(keyCode)"
        return text + keyLabel
    }

    /// ⌃⌥⇧⌘ in the standard macOS order, for the modifiers set.
    static func modifierSymbols(_ modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 {
            text += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            text += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            text += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            text += "⌘"
        }
        return text
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

    /// F-keys type nothing, so a shortcut can use them without ⌘, ⌃ or ⌥.
    private static let functionKeyLabels: [Int: String] = [
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

    private static let functionKeyCodes = Set(functionKeyLabels.keys)

    /// Keys that don't type a visible character, labelled as in macOS menus.
    static let specialKeyLabels: [Int: String] = functionKeyLabels.merging([
        kVK_Space: "Space",
        kVK_Escape: "⎋",
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
    ]) { function, _ in function }

    /// The stored shortcut if the recorder could have saved it in some
    /// keyboard layout. Nothing here asks the current layout.
    static func loadStored(from defaults: UserDefaults) -> HotKey? {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return nil
        }
        guard let hotKey = try? JSONDecoder().decode(HotKey.self, from: data) else {
            return nil
        }
        // A hand-edited or corrupt value must not become an unusable
        // shortcut. Virtual key codes stop at 127.
        guard hotKey.keyCode < 128 else {
            return nil
        }
        // Other bits (e.g. Caps Lock) would make the shortcut need them too.
        guard hotKey.carbonModifiers & ~modifierMask == 0 else {
            return nil
        }
        // Keys the recorder can't label (a modifier key, Help) would show
        // as "Key 55". Asking the layout would fail while it is momentarily
        // unavailable (e.g. at login) and drop a valid shortcut.
        guard isLabelledInAnyLayout(keyCode: Int(hotKey.keyCode)) else {
            return nil
        }
        // The recorder never saves this, in any layout. Only the modifiers
        // decide it, so no layout characters are needed.
        if hotKey.block(commandCharacters: []) == .typesCharacter {
            return nil
        }
        return hotKey
    }

    /// Whether the key has a label whatever the layout: every key that types
    /// on an Apple keyboard (key codes 0-50 hold the letters, digits,
    /// punctuation and the ISO extra key; a Japanese keyboard adds ¥ and _),
    /// plus the named and keypad keys.
    private static func isLabelledInAnyLayout(keyCode: Int) -> Bool {
        let isANSIOrISOKey = (kVK_ANSI_A...kVK_ANSI_Grave).contains(keyCode)
        let isJISKey = keyCode == kVK_JIS_Yen || keyCode == kVK_JIS_Underscore
        let isNamedKey = specialKeyLabels[keyCode] != nil
        let isKeypadKey = keypadKeyLabels[keyCode] != nil
        return isANSIOrISOKey || isJISKey || isNamedKey || isKeypadKey
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
        if Self.label(forKeyCode: keyCode) == nil {
            return nil
        }
        self.init(
            keyCode: UInt32(keyCode),
            carbonModifiers: Self.carbonModifiers(from: event.modifierFlags)
        )
    }

    static func label(forKeyCode keyCode: Int) -> String? {
        // Virtual key codes stop at 127; UCKeyTranslate takes a UInt16.
        guard (0..<128).contains(keyCode) else {
            return nil
        }
        if let special = specialKeyLabels[keyCode] {
            return special
        }
        if let keypad = keypadKeyLabels[keyCode] {
            return "Keypad " + keypad
        }
        // The ASCII-capable layout (e.g. U.S. or German, never Kana input)
        // with no modifiers, so ⌥E shows "E", not "´" or "え".
        let typed = KeyboardLayout.withASCIICapableLayout { translate in
            translate(keyCode, 0)
        }
        guard let typed else {
            return nil
        }
        let label = typed.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Keycap style, unless uppercasing changes the key ("ß" → "SS").
        let uppercased = label.uppercased()
        if uppercased.count != label.count {
            return label
        }
        return uppercased
    }

    /// What the key types with ⌘ held in the current layout, lowercased.
    /// Menus and SwiftUI match ⌘ shortcuts by this character, which
    /// differs from the key's label on layouts like "Dvorak - QWERTY ⌘".
    /// Without a layout, the U.S. key positions.
    static func commandLayerCharacter(keyCode: Int) -> String? {
        let typed = KeyboardLayout.withCurrentLayout { translate in
            translate(keyCode, cmdKey)
        }
        return commandLayerCharacter(typed: typed, keyCode: keyCode)
    }

    /// `typed` is what the key typed with ⌘ held; "" means the translation
    /// failed.
    private static func commandLayerCharacter(typed: String?, keyCode: Int) -> String? {
        if let typed, !typed.isEmpty {
            return typed.lowercased()
        }
        return usCommandCharacters[keyCode]
    }

    /// Every character a key can be matched by when checking Konnyaku's own
    /// shortcuts: the popup matches ⌘E by the character the key types
    /// without modifiers, menus by the one it types with ⌘. They differ on
    /// "Dvorak - QWERTY ⌘", and a non-Latin layout's ⌘ layer may not be
    /// Latin at all, which the ASCII-capable layout covers.
    static func commandCharacters(keyCode: Int) -> Set<String> {
        var characters: Set<String> = []
        let current = KeyboardLayout.withCurrentLayout { translate in
            (withCommand: translate(keyCode, cmdKey), plain: translate(keyCode, 0))
        }
        let layerCharacter = commandLayerCharacter(typed: current?.withCommand, keyCode: keyCode)
        if let layerCharacter {
            characters.insert(layerCharacter)
        }
        if let plain = current?.plain, !plain.isEmpty {
            characters.insert(plain.lowercased())
        }
        let asciiTyped = KeyboardLayout.withASCIICapableLayout { translate in
            translate(keyCode, cmdKey)
        }
        if let asciiTyped, !asciiTyped.isEmpty {
            characters.insert(asciiTyped.lowercased())
        }
        return characters
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
        kVK_JIS_KeypadComma: ",",
    ]
}
