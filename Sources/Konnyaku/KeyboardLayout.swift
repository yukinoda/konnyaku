import Carbon.HIToolbox

/// What the keys of a keyboard layout type, via UCKeyTranslate.
enum KeyboardLayout {
    /// What `keyCode` types with the Carbon `modifiers` held in `source`
    /// ("" if nothing). Nil if `source` has no Unicode layout data.
    static func typedCharacter(in source: TISInputSource, keyCode: Int, modifiers: Int) -> String? {
        guard let layoutProperty = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutProperty).takeUnretainedValue() as Data
        let modifierState = UInt32((modifiers >> 8) & 0xFF)
        let keyboardType = UInt32(LMGetKbdType())
        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                modifierState,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            if status != noErr {
                return ""
            }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
