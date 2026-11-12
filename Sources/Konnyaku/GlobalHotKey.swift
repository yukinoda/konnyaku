import AppKit
import Carbon.HIToolbox
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
            refreshNames()
        }
    }
    /// Set when even the shown shortcut couldn't be registered.
    @Published private(set) var failure: HotKeyFailure?
    /// The saved shortcut that couldn't be registered at launch, so Settings
    /// can say why ⌃⌥T is in use instead.
    @Published private(set) var unavailableAtLaunch: HotKey? {
        didSet {
            refreshNames()
        }
    }
    /// While the recorder listens, nothing may be registered.
    @Published private(set) var isSuspended = false

    /// Display strings, cached: building one asks Text Input Sources for
    /// the keyboard layout, which is too slow to repeat on every render.
    /// Refreshed when the shortcut or the keyboard layout changes.
    @Published private(set) var name = ""
    @Published private(set) var defaultName = ""
    @Published private(set) var unavailableName: String?
    /// Which of Konnyaku's own shortcuts (e.g. "⌘C") the shortcut acts as
    /// on the current layout. The recorder blocks those, so only a layout
    /// switch gets here; the shortcut stays, and Settings explains.
    @Published private(set) var konnyakuShortcutName: String?

    /// What the menu and the popup advertise. False while the recorder has
    /// the shortcut off. The pauses for Konnyaku's own shortcuts don't
    /// count: the shortcut still works everywhere else.
    var isRegistered: Bool {
        failure == nil && !isSuspended
    }

    private static let logger = Logger(subsystem: "io.github.yukinoda.konnyaku", category: "hotkey")
    private static let signature: OSType = 0x4B4E594B  // "KNYK"

    private let defaults = UserDefaults.standard
    private var hotKeyRef: EventHotKeyRef?
    private var isHandlerInstalled = false
    /// The translate panel, while it is the key window.
    private weak var keyWindow: NSWindow?
    /// Paused while the translate panel is key and the shortcut is one it
    /// uses (see HotKey.block).
    private var isShadowingInAppShortcut = false
    /// Paused while SelectionReader's ⌘C is the shortcut itself.
    private var isPostingCopy = false

    /// The hotkey stays unregistered while any of three pauses holds:
    /// - `isSuspended`: the shortcut recorder is listening. Set by
    ///   `suspend()` and `resume()`.
    /// - `isShadowingInAppShortcut`: the translate panel is key and the
    ///   shortcut is one of its own on the current layout. Set by
    ///   `updateInAppPause()` when the key window or the layout changes.
    /// - `isPostingCopy`: SelectionReader is posting a ⌘C that is the
    ///   shortcut itself. Set by `pauseForCopy(keyCode:)` and
    ///   `endCopyPause()`.
    /// Each of those flips one flag, then `applyPause()` registers or
    /// unregisters to match. `start()` and `change(to:)` register directly,
    /// ignoring the pauses, then `reapplyPauses()` puts back the ones that
    /// hold for the new shortcut.
    private var isPaused: Bool {
        isSuspended || isShadowingInAppShortcut || isPostingCopy
    }

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
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowBecameKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    @objc private func keyboardLayoutChanged() {
        refreshNames()
        // The hotkey is bound to the key's position, so the new layout can
        // turn it into one of Konnyaku's own shortcuts.
        updateInAppPause()
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        let window = notification.object as? NSWindow
        // Only the translate panel (popup and editor) has Konnyaku's own
        // shortcuts; in Settings or About the hotkey keeps working.
        if window?.identifier != TranslatePanelController.panelIdentifier {
            return
        }
        keyWindow = window
        updateInAppPause()
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === keyWindow {
            keyWindow = nil
        }
        updateInAppPause()
    }

    /// Publishes only what changed, so a Kana/Eisu toggle doesn't re-render
    /// every view that shows a name.
    private func refreshNames() {
        update(\.name, to: hotKey.displayString)
        update(\.defaultName, to: HotKey.default.displayString)
        update(\.unavailableName, to: unavailableAtLaunch?.displayString)
        update(\.konnyakuShortcutName, to: hotKey.konnyakuShortcutName)
    }

    private func update<Value: Equatable>(_ path: ReferenceWritableKeyPath<GlobalHotKey, Value>, to value: Value) {
        if self[keyPath: path] != value {
            self[keyPath: path] = value
        }
    }

    /// True if the translate panel is key and needs the shortcut itself. The
    /// recorder blocks those, so only a layout switch gets here. Otherwise
    /// the shortcut keeps working in Konnyaku, e.g. to hide the popup.
    private var shadowsInAppShortcut: Bool {
        if keyWindow == nil {
            return false
        }
        // Cached, and equivalent to `hotKey.block == .konnyakuShortcut`:
        // every one of Konnyaku's shortcuts uses ⌘.
        return konnyakuShortcutName != nil
    }

    private func updateInAppPause() {
        let shadows = shadowsInAppShortcut
        if shadows == isShadowingInAppShortcut {
            return
        }
        isShadowingInAppShortcut = shadows
        applyPause()
    }

    /// Unregisters while any pause holds, and registers again once none
    /// does.
    private func applyPause() {
        if isPaused {
            unregister()
            return
        }
        if hotKeyRef != nil {
            return
        }
        // Exactly the shortcut that was paused. If another app took it
        // meanwhile, `failure` makes Settings say so and the menu and the
        // popup stop advertising it.
        failure = register(hotKey)
    }

    /// After registering directly, which ignores the pauses, puts back the
    /// ones that hold for the shortcut now in effect.
    private func reapplyPauses() {
        isShadowingInAppShortcut = shadowsInAppShortcut
        if isPaused {
            unregister()
        }
    }

    func start() {
        let saved = HotKey.loadStored(from: defaults) ?? .default
        // Shown even if it fails: with no handler, Settings explains it and
        // a later retry should register the user's choice, not ⌃⌥T.
        hotKey = saved
        failure = register(saved)
        defer {
            reapplyPauses()
        }
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
        isSuspended = false
        defer {
            reapplyPauses()
        }
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
        isSuspended = true
        applyPause()
    }

    func resume() {
        isSuspended = false
        applyPause()
    }

    /// SelectionReader's ⌘C would fire this hotkey instead of copying if
    /// the shortcut is that same key with ⌘ (a layout switch can make it
    /// so). Pauses it until `endCopyPause()`.
    func pauseForCopy(keyCode: CGKeyCode) {
        let copy = HotKey(keyCode: UInt32(keyCode), carbonModifiers: UInt32(cmdKey))
        if hotKey != copy {
            return
        }
        isPostingCopy = true
        applyPause()
    }

    func endCopyPause() {
        if !isPostingCopy {
            return
        }
        isPostingCopy = false
        applyPause()
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
        unregister()
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
            let name = candidate.displayString
            Self.logger.error("Could not register \(name, privacy: .public) (OSStatus \(registerStatus))")
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
