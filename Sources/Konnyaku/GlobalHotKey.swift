import Carbon.HIToolbox
import Foundation
import os

/// Why a shortcut couldn't be registered, so Settings can say what to do.
enum HotKeyFailure: Equatable {
    case inUse
    case noHandler
    /// Any other RegisterEventHotKey error.
    case rejected

    /// A plain sentence for Settings, about the shortcut shown as `name`.
    func message(for name: String) -> String {
        switch self {
        case .inUse:
            return "\(name) is already in use. Try a different shortcut."
        case .noHandler:
            return "Konnyaku couldn't turn on shortcuts. Quit and reopen Konnyaku."
        case .rejected:
            return "\(name) can't be used. Try a different shortcut."
        }
    }
}

/// Registers the user's translate shortcut (⌃⌥T by default). Carbon hotkeys
/// need no permissions.
@MainActor
final class GlobalHotKey: NSObject, ObservableObject {
    static let shared = GlobalHotKey()

    /// The shortcut the menu, the popup and Settings show.
    @Published private(set) var hotKey = HotKey.default {
        didSet {
            name = hotKey.displayString
        }
    }
    /// Set when even the shown shortcut couldn't be registered.
    @Published private(set) var failure: HotKeyFailure?
    /// The saved shortcut that couldn't be registered at launch, so Settings
    /// can say why ⌃⌥T is in use instead.
    @Published private(set) var unavailableAtLaunch: HotKey? {
        didSet {
            unavailableName = unavailableAtLaunch?.displayString
        }
    }

    /// Display strings, cached: building one asks Text Input Sources for
    /// the keyboard layout, which is too slow to repeat on every render.
    /// Refreshed when the shortcut or the keyboard layout changes.
    @Published private(set) var name = ""
    @Published private(set) var defaultName = ""
    @Published private(set) var unavailableName: String?

    var isRegistered: Bool {
        failure == nil
    }

    private static let logger = Logger(subsystem: "io.github.yukinoda.konnyaku", category: "hotkey")
    private static let signature: OSType = 0x4B4E594B  // "KNYK"

    private let defaults = UserDefaults.standard
    private var hotKeyRef: EventHotKeyRef?
    private var isHandlerInstalled = false

    private override init() {
        super.init()
        refreshNames()
        // A layout switch can change the key's label (T is "Y" on Dvorak).
        // Delivered immediately: a menu-bar app is rarely active, and the
        // default holds distributed notifications back until it is.
        let layoutChanged = NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(keyboardLayoutChanged),
            name: layoutChanged,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func keyboardLayoutChanged() {
        refreshNames()
    }

    private func refreshNames() {
        name = hotKey.displayString
        defaultName = HotKey.default.displayString
        unavailableName = unavailableAtLaunch?.displayString
    }

    func start() {
        let saved = HotKey.load(from: defaults) ?? .default
        // Shown even if it fails: with no handler, Settings explains it and
        // a later retry should register the user's choice, not ⌃⌥T.
        hotKey = saved
        failure = register(saved)
        if failure == nil {
            return
        }
        // Without a handler, ⌃⌥T would fail the same way.
        if saved == .default || failure == .noHandler {
            return
        }
        // The saved choice stays stored: the other app may be gone next launch.
        Self.logger.error("Falling back to ⌃⌥T: could not register \(saved.displayString, privacy: .public)")
        unavailableAtLaunch = saved
        hotKey = .default
        failure = register(.default)
    }

    /// Switches to `newHotKey`, keeping the current one if it can't be
    /// registered. Returns why the switch failed, or nil.
    func change(to newHotKey: HotKey) -> HotKeyFailure? {
        unregister()
        if let newFailure = register(newHotKey) {
            // Only the shortcut the user already had: switching to the one
            // skipped at launch here would answer a request for a
            // different shortcut with a third one.
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
        registerCurrent()
    }

    /// Registers the shortcut in effect. If that was failing after a
    /// launch-time fallback (so nothing worked), the user's saved choice may
    /// be free by now and is tried first. A working ⌃⌥T is never swapped
    /// out silently.
    private func registerCurrent() {
        let wasFailing = failure != nil
        let skipped = wasFailing ? unavailableAtLaunch : nil
        if let saved = skipped, register(saved) == nil {
            hotKey = saved
            unavailableAtLaunch = nil
            failure = nil
            return
        }
        failure = register(hotKey)
    }

    /// True if the shortcut matches an enabled macOS shortcut (Spotlight,
    /// screenshots, Mission Control…). RegisterEventHotKey still succeeds
    /// for those, so the recorder checks new shortcuts and warns. Not
    /// checked on register: re-registering a shortcut the user already
    /// accepted needs no new warning.
    static func isSystemShortcut(_ candidate: HotKey) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let unmanaged else {
            return false
        }
        let entries = unmanaged.takeRetainedValue() as? [[String: Any]] ?? []
        return entries.contains { entry in
            let isEnabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool ?? false
            let keyCode = entry[kHISymbolicHotKeyCode as String] as? Int
            let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int ?? 0
            let sameKey = keyCode == Int(candidate.keyCode)
            let maskedModifiers = UInt32(truncatingIfNeeded: modifiers) & HotKey.modifierMask
            let sameModifiers = maskedModifiers == candidate.carbonModifiers
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
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var newRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            candidate.keyCode,
            candidate.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            // Exclusive: an app holding the combination exclusively then
            // fails us with eventHotKeyExistsErr (non-exclusive gets noErr
            // and never fires), and no app can take it from us later.
            OptionBits(kEventHotKeyExclusive),
            &newRef
        )
        if registerStatus == eventHotKeyExistsErr {
            Self.logger.error("\(candidate.displayString, privacy: .public) is already in use by another app")
            return .inUse
        }
        if registerStatus != noErr {
            Self.logger.error("Could not register \(candidate.displayString, privacy: .public) (OSStatus \(registerStatus))")
            return .rejected
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
