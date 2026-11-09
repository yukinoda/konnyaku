import Carbon.HIToolbox

/// What the keys of a keyboard layout type, via UCKeyTranslate.
enum KeyboardLayout {
    /// What a key code types with the given Carbon modifiers held ("" if
    /// nothing).
    typealias Translate = (_ keyCode: Int, _ modifiers: Int) -> String

    /// `withTranslator` for the current keyboard layout. Nil if there is
    /// none (TIS can return nil, e.g. while input sources change).
    static func withCurrentLayout<T>(_ body: (Translate) -> T?) -> T? {
        guard let unmanagedSource = TISCopyCurrentKeyboardLayoutInputSource() else {
            return nil
        }
        return withTranslator(for: unmanagedSource.takeRetainedValue(), body)
    }

    /// `withTranslator` for the ASCII-capable layout (e.g. U.S. or German,
    /// never Kana input). Nil if there is none.
    static func withASCIICapableLayout<T>(_ body: (Translate) -> T?) -> T? {
        guard let unmanagedSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource() else {
            return nil
        }
        return withTranslator(for: unmanagedSource.takeRetainedValue(), body)
    }

    /// Runs `body` with a translator for `source`, resolving the layout
    /// once for however many keys `body` translates. Nil if `source` has no
    /// Unicode layout data.
    static func withTranslator<T>(for source: TISInputSource, _ body: (Translate) -> T?) -> T? {
        guard let layoutProperty = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutProperty).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())
        return layoutData.withUnsafeBytes { buffer -> T? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }
            return body { keyCode, modifiers in
                // Virtual key codes stop at 127; UInt16(keyCode) would trap
                // on a corrupt value far past that.
                guard (0..<128).contains(keyCode) else {
                    return ""
                }
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout,
                    UInt16(keyCode),
                    UInt16(kUCKeyActionDown),
                    UInt32((modifiers >> 8) & 0xFF),
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
}
