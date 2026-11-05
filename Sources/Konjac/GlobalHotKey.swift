import Carbon.HIToolbox
import os

/// Registers the fixed ⌃⌥T hotkey. Carbon hotkeys need no permissions.
@MainActor
enum GlobalHotKey {
    private static let logger = Logger(subsystem: "org.konjac.app", category: "hotkey")
    private static let signature: OSType = 0x4B4F4E4A  // "KONJ"

    static func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
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
        guard installStatus == noErr else {
            logger.error("Could not install the hotkey handler (OSStatus \(installStatus))")
            return
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let modifiers = UInt32(controlKey | optionKey)
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            logger.error("⌃⌥T is already in use by another app (OSStatus \(registerStatus))")
        }
    }
}
