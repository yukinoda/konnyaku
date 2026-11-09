import Carbon.HIToolbox
import os

/// Registers the user's translate shortcut (⌃⌥T by default). Carbon hotkeys
/// need no permissions.
@MainActor
final class GlobalHotKey: ObservableObject {
    static let shared = GlobalHotKey()

    /// The shortcut the menu, the popup and Settings show.
    @Published private(set) var hotKey = HotKey.default
    /// False when even the shown shortcut couldn't be registered.
    @Published private(set) var isRegistered = false
    /// The saved shortcut that couldn't be registered at launch, so Settings
    /// can say why ⌃⌥T is in use instead.
    @Published private(set) var unavailableAtLaunch: HotKey?

    private static let logger = Logger(subsystem: "io.github.yukinoda.konnyaku", category: "hotkey")
    private static let signature: OSType = 0x4B4E594B  // "KNYK"

    private let defaults: UserDefaults
    private var hotKeyRef: EventHotKeyRef?
    private var isHandlerInstalled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start() {
        // A hotkey without its handler would swallow the keystroke in every
        // app and do nothing; Settings then reports it as not working.
        guard installHandler() else {
            return
        }
        let saved = HotKey.load(from: defaults) ?? .default
        if register(saved) {
            hotKey = saved
            return
        }
        guard saved != .default else {
            return
        }
        // The saved choice stays stored: the other app may be gone next launch.
        Self.logger.error("Falling back to ⌃⌥T: could not register \(saved.displayString)")
        unavailableAtLaunch = saved
        hotKey = .default
        _ = register(.default)
    }

    /// Switches to `newHotKey`, keeping the current one if it can't be
    /// registered. Returns whether the switch worked.
    func change(to newHotKey: HotKey) -> Bool {
        unregister()
        guard register(newHotKey) else {
            _ = register(hotKey)
            return false
        }
        hotKey = newHotKey
        unavailableAtLaunch = nil
        newHotKey.save(to: defaults)
        return true
    }

    /// While the recorder listens, the current shortcut must reach it
    /// instead of opening the popup.
    func suspend() {
        unregister()
    }

    func resume() {
        guard hotKeyRef == nil else {
            return
        }
        _ = register(hotKey)
    }

    /// Installed once; registering a new shortcut reuses it.
    private func installHandler() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in
                    TranslatePanelController.shared.translateSelectionOrClipboard()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        if installStatus != noErr {
            Self.logger.error("Could not install the hotkey handler (OSStatus \(installStatus))")
            return false
        }
        isHandlerInstalled = true
        return true
    }

    /// True if the shortcut matches an enabled macOS shortcut (Spotlight,
    /// screenshots, Mission Control…). RegisterEventHotKey still succeeds
    /// for those, but the system gets the keystroke first.
    static func isSystemShortcut(_ candidate: HotKey) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let unmanaged else {
            return false
        }
        let entries = unmanaged.takeRetainedValue() as? [[String: Any]] ?? []
        let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        return entries.contains { entry in
            let isEnabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool ?? false
            let keyCode = entry[kHISymbolicHotKeyCode as String] as? Int
            let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int ?? 0
            let sameKey = keyCode == Int(candidate.keyCode)
            let sameModifiers = UInt32(modifiers) & modifierMask == candidate.carbonModifiers
            return isEnabled && sameKey && sameModifiers
        }
    }

    private func register(_ candidate: HotKey) -> Bool {
        guard isHandlerInstalled else {
            return false
        }
        // Checked here so launch and reset get it too: macOS would take the
        // keystroke first, so registering would only advertise a dead key.
        if Self.isSystemShortcut(candidate) {
            Self.logger.error("\(candidate.displayString) is a macOS shortcut")
            isRegistered = false
            return false
        }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var newRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            candidate.keyCode,
            candidate.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        let name = candidate.displayString
        if registerStatus == eventHotKeyExistsErr {
            Self.logger.error("\(name) is already in use by another app")
        } else if registerStatus != noErr {
            Self.logger.error("Could not register \(name) (OSStatus \(registerStatus))")
        }
        let succeeded = registerStatus == noErr
        if succeeded {
            hotKeyRef = newRef
        }
        isRegistered = succeeded
        return succeeded
    }

    private func unregister() {
        guard let hotKeyRef else {
            return
        }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}
