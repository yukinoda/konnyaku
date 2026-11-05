import Carbon.HIToolbox

/// Registers the fixed ⌃⌥T hotkey. Carbon hotkeys need no permissions.
@MainActor
enum GlobalHotKey {
    private static let signature: OSType = 0x4B4F4E4A  // "KONJ"

    static func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in
                    TranslatePanelController.shared.toggleWithClipboard()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let modifiers = UInt32(controlKey | optionKey)
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
