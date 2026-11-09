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

    /// Why the user's shortcut was set aside for ⌃⌥T.
    enum SkipReason {
        /// Registering it failed at launch (another app had it).
        case notRegisteredAtLaunch
        /// The keyboard layout makes it unusable (see HotKey.isUsable).
        case keyboardLayout
    }

    /// The user's shortcut that ⌃⌥T stands in for, so Settings can say why.
    @Published private(set) var skipped: HotKey? {
        didSet {
            skippedName = skipped?.displayString
        }
    }
    @Published private(set) var skipReason = SkipReason.notRegisteredAtLaunch

    /// Display strings, cached: building one asks Text Input Sources for
    /// the keyboard layout, which is too slow to repeat on every render.
    /// Refreshed when the shortcut or the keyboard layout changes.
    @Published private(set) var name = ""
    @Published private(set) var defaultName = ""
    @Published private(set) var skippedName: String?

    var isRegistered: Bool {
        failure == nil
    }

    private static let logger = Logger(subsystem: "io.github.yukinoda.konnyaku", category: "hotkey")
    private static let signature: OSType = 0x4B4E594B  // "KNYK"

    private let defaults = UserDefaults.standard
    private var hotKeyRef: EventHotKeyRef?
    private var isHandlerInstalled = false
    /// While the recorder listens, nothing may be registered.
    private var isSuspended = false

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
        // The hotkey is bound to the key's position, so the new layout can
        // turn it into ⌘C, which would then take Copy from every app and
        // from SelectionReader's own ⌘C.
        if hotKey == .default {
            restoreAfterLayoutSwitchBack()
            return
        }
        if hotKey.isUsable {
            return
        }
        unregister()
        fallBack(from: hotKey, because: .keyboardLayout)
    }

    /// Switching back to the layout the shortcut was chosen in brings it
    /// back for this session, not just at the next launch.
    private func restoreAfterLayoutSwitchBack() {
        guard let skipped else {
            return
        }
        if skipReason != .keyboardLayout {
            return
        }
        // Checked first so input-source switches (Kana ⇄ Eisu) don't
        // re-register ⌃⌥T each time.
        if !skipped.isUsable {
            return
        }
        // resume() tries it when recording ends.
        if isSuspended {
            return
        }
        unregister()
        registerCurrent()
    }

    private func refreshNames() {
        name = hotKey.displayString
        defaultName = HotKey.default.displayString
        skippedName = skipped?.displayString
    }

    /// Uses ⌃⌥T instead of `unusable`, which stays stored: the other app
    /// may be gone, or the other layout back, next launch.
    private func fallBack(from unusable: HotKey, because reason: SkipReason) {
        Self.logger.error("Falling back to ⌃⌥T from \(unusable.displayString, privacy: .public)")
        skipReason = reason
        skipped = unusable
        hotKey = .default
        // resume() registers it when recording ends.
        if isSuspended {
            return
        }
        failure = register(.default)
    }

    func start() {
        let stored = HotKey.loadStored(from: defaults)
        if let stored, !stored.isUsable {
            fallBack(from: stored, because: .keyboardLayout)
            return
        }
        let saved = stored ?? .default
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
        fallBack(from: saved, because: .notRegisteredAtLaunch)
    }

    /// Switches to `newHotKey`, keeping the current one if it can't be
    /// registered. Returns why the switch failed, or nil.
    func change(to newHotKey: HotKey) -> HotKeyFailure? {
        isSuspended = false
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
        skipped = nil
        newHotKey.save(to: defaults)
        return nil
    }

    /// While the recorder listens, the current shortcut must reach it
    /// instead of opening the popup.
    func suspend() {
        isSuspended = true
        unregister()
    }

    func resume() {
        isSuspended = false
        guard hotKeyRef == nil else {
            return
        }
        registerCurrent()
    }

    /// Registers the shortcut in effect. The user's skipped shortcut is
    /// tried first if ⌃⌥T was failing (it may be free by now) or if it was
    /// skipped for the layout. A working ⌃⌥T is never swapped out for one
    /// another app had, and a shortcut the layout rules out is never tried.
    private func registerCurrent() {
        // One skipped for the layout comes back whenever the layout allows.
        var triesSkipped = skipReason == .keyboardLayout
        if failure != nil {
            triesSkipped = true
        }
        if triesSkipped {
            if restoreSkipped() {
                return
            }
        }
        failure = register(hotKey)
    }

    /// Switches back to the user's skipped shortcut if the current layout
    /// allows it and it registers. Returns true if it did. Call with
    /// nothing registered.
    private func restoreSkipped() -> Bool {
        guard let saved = skipped else {
            return false
        }
        // The layout may have turned it into ⌘C since it was skipped.
        guard saved.isUsable else {
            return false
        }
        guard register(saved) == nil else {
            return false
        }
        hotKey = saved
        skipped = nil
        failure = nil
        return true
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
