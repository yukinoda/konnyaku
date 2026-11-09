import Carbon.HIToolbox
import os

/// Why a shortcut couldn't be registered, so Settings can say what to do.
enum HotKeyFailure: Equatable {
    case inUse
    case systemShortcut
    case noHandler

    /// A plain sentence for Settings.
    func message(for hotKey: HotKey) -> String {
        let name = hotKey.displayString
        switch self {
        case .inUse:
            return "\(name) is already in use. Try a different shortcut."
        case .systemShortcut:
            return "\(name) is a macOS shortcut. Try a different shortcut."
        case .noHandler:
            return "Konnyaku couldn't turn on shortcuts. Quit and reopen Konnyaku."
        }
    }
}

/// Registers the user's translate shortcut (⌃⌥T by default). Carbon hotkeys
/// need no permissions.
@MainActor
final class GlobalHotKey: ObservableObject {
    static let shared = GlobalHotKey()

    /// The shortcut the menu, the popup and Settings show.
    @Published private(set) var hotKey = HotKey.default
    /// Set when even the shown shortcut couldn't be registered.
    @Published private(set) var failure: HotKeyFailure?
    /// The saved shortcut that couldn't be registered at launch, so Settings
    /// can say why ⌃⌥T is in use instead.
    @Published private(set) var unavailableAtLaunch: HotKey?

    var isRegistered: Bool {
        failure == nil
    }

    private static let logger = Logger(subsystem: "io.github.yukinoda.konnyaku", category: "hotkey")
    private static let signature: OSType = 0x4B4E594B  // "KNYK"

    private let defaults: UserDefaults
    private var hotKeyRef: EventHotKeyRef?
    private var isHandlerInstalled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start() {
        let saved = HotKey.load(from: defaults) ?? .default
        failure = register(saved)
        if failure == nil {
            hotKey = saved
            return
        }
        // Without a handler, ⌃⌥T would fail the same way.
        if saved == .default || failure == .noHandler {
            return
        }
        // The saved choice stays stored: the other app may be gone next launch.
        Self.logger.error("Falling back to ⌃⌥T: could not register \(saved.displayString)")
        unavailableAtLaunch = saved
        hotKey = .default
        failure = register(.default)
    }

    /// Switches to `newHotKey`, keeping the current one if it can't be
    /// registered. Returns why the switch failed, or nil.
    func change(to newHotKey: HotKey) -> HotKeyFailure? {
        unregister()
        if let newFailure = register(newHotKey) {
            failure = register(hotKey)
            return newFailure
        }
        failure = nil
        hotKey = newHotKey
        unavailableAtLaunch = nil
        newHotKey.save(to: defaults)
        return nil
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
        failure = register(hotKey)
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

    /// Installed once, retried until it works; every shortcut reuses it.
    private func installHandlerIfNeeded() -> Bool {
        if isHandlerInstalled {
            return true
        }
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

    /// Returns why `candidate` couldn't be registered, or nil.
    private func register(_ candidate: HotKey) -> HotKeyFailure? {
        // A hotkey without its handler would swallow the keystroke in every
        // app and do nothing.
        guard installHandlerIfNeeded() else {
            return .noHandler
        }
        let name = candidate.displayString
        // Checked here so launch and reset get it too: macOS would take the
        // keystroke first, so registering would only advertise a dead key.
        if Self.isSystemShortcut(candidate) {
            Self.logger.error("\(name) is a macOS shortcut")
            return .systemShortcut
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
        if registerStatus == eventHotKeyExistsErr {
            Self.logger.error("\(name) is already in use by another app")
        } else if registerStatus != noErr {
            Self.logger.error("Could not register \(name) (OSStatus \(registerStatus))")
        }
        if registerStatus != noErr {
            return .inUse
        }
        hotKeyRef = newRef
        return nil
    }

    private func unregister() {
        guard let hotKeyRef else {
            return
        }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}
