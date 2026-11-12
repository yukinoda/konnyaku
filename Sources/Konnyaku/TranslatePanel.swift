import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A small floating popup showing the translation, which ⌘E expands into the
/// full editor.
@MainActor
final class TranslatePanelController {
    static let shared = TranslatePanelController()

    /// Lets HotKeyRegistrar tell the panel from Settings and About without
    /// creating it.
    static let panelIdentifier = NSUserInterfaceItemIdentifier("translatePanel")

    private let panel: NSPanel
    private let mode = PanelMode()
    /// Where the panel's top edge should stay while its content resizes.
    private var anchoredTop: CGFloat?
    /// The clipboard change count when the panel was last shown. A different
    /// count means the user copied something new since then. Starts at -1
    /// (nothing seen yet) so the first hotkey press reads the clipboard.
    private var seenChangeCount = -1
    /// A selection read is waiting on the frontmost app; ignore repeats so
    /// two reads don't mix up each other's clipboard restore.
    private var isReadingSelection = false

    private init() {
        let style: NSWindow.StyleMask = [
            .titled,
            .closable,
            .fullSizeContentView,
            .nonactivatingPanel,
        ]
        panel = NSPanel(
            contentRect: .zero,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.panelIdentifier
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Esc and clicking elsewhere close it, so no traffic lights.
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        let content = PanelRootView(
            model: TranslationViewModel.shared,
            mode: mode,
            onCopy: { [weak self] in self?.copyAndClose() },
            onExpand: { [weak self] in self?.expand() }
        )
        let hosting = NSHostingController(rootView: content)
        // Resizes the panel as the translation or the mode changes.
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        installKeyMonitor()
        closeCompactPopupWhenUnfocused()
        keepTopEdgeWhenResized()
        resetToCompactOnClose()
    }

    /// Each fresh open starts as the compact popup. Reset on close, not on
    /// open: SwiftUI resizes later, and show() must measure the compact size.
    private func resetToCompactOnClose() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mode.isExpanded = false
            }
        }
    }

    /// AppKit keeps the bottom edge when the content grows, which would move
    /// the popup up over the text under the pointer. Keep the top edge
    /// instead, and stay on screen. A drag by the user sets a new top.
    private func keepTopEdgeWhenResized() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reanchor()
            }
        }
        center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.anchoredTop = self.panel.frame.maxY
            }
        }
    }

    private func reanchor() {
        guard let top = anchoredTop else {
            return
        }
        var frame = panel.frame
        frame.origin.y = top - frame.height
        let target = clamped(frame)
        if target != panel.frame {
            panel.setFrame(target, display: true)
        }
    }

    /// The focused text view consumes Esc, Return and keypad Enter before the panel sees
    /// them, so handle the panel's keys from a monitor instead.
    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else {
                return event
            }
            if self.handle(event) {
                return nil
            }
            return event
        }
    }

    /// What a key press in the panel does.
    enum KeyAction: Equatable {
        case close
        case copyAndClose
        case expand
    }

    /// Returns true if the event was handled.
    private func handle(_ event: NSEvent) -> Bool {
        let action = Self.keyAction(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            isComposing: panel.isComposingText,
            isExpanded: mode.isExpanded
        )
        switch action {
        case .close:
            panel.close()
        case .copyAndClose:
            copyAndClose()
        case .expand:
            expand()
        case nil:
            return false
        }
        return true
    }

    /// Esc closes; in the compact popup, Return (or keypad Enter) copies and
    /// ⌘E opens the editor. Nil means the key isn't the panel's.
    nonisolated static func keyAction(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?,
        isComposing: Bool,
        isExpanded: Bool
    ) -> KeyAction? {
        // Keys that confirm or cancel an IME composition belong to it.
        if isComposing {
            return nil
        }
        // Only these modifiers change a shortcut; Caps Lock and Fn don't.
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let modifiers = modifierFlags.intersection(shortcutModifiers)
        if keyCode == UInt16(kVK_Escape) {
            return .close
        }
        if isExpanded {
            return nil
        }
        // The keypad's Enter is the same key as Return to the user.
        let isReturn = keyCode == UInt16(kVK_Return)
        let isKeypadEnter = keyCode == UInt16(kVK_ANSI_KeypadEnter)
        let isEnter = isReturn || isKeypadEnter
        let hasNoModifiers = modifiers.isEmpty
        if isEnter && hasNoModifiers {
            return .copyAndClose
        }
        // By character, not key code, so ⌘E works on any keyboard layout.
        // Keep HotKey.konnyakuShortcuts in step: it reserves this shortcut
        // (PopupKeyActionTests checks this).
        let character = charactersIgnoringModifiers?.lowercased()
        if character == "e" && modifiers == .command {
            return .expand
        }
        return nil
    }

    /// The compact popup is a glance: clicking another window dismisses it.
    /// The editor stays open, since the user may come back to it.
    private func closeCompactPopupWhenUnfocused() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.mode.isExpanded else {
                    return
                }
                self.panel.close()
            }
        }
    }

    private func copyAndClose() {
        let model = TranslationViewModel.shared
        // Nothing to copy yet, or the output belongs to the previous request.
        if !model.hasFreshOutput {
            return
        }
        model.copyOutput()
        panel.close()
    }

    /// Switches to the editor; the resize keeps the top edge in place.
    private func expand() {
        mode.isExpanded = true
    }

    /// Visible here means on screen on the current Space; a panel left open
    /// on another Space does not count.
    private var isVisibleHere: Bool {
        panel.isVisible && panel.isOnActiveSpace
    }

    /// The panel itself is the key window on this Space, which is narrower
    /// than Konnyaku being the active app.
    private var isFocusedHere: Bool {
        isVisibleHere && panel.isKeyWindow
    }

    /// Shows the full editor (menu: Open Translator). Like the hotkey, it
    /// loads newly copied text, so that text isn't left for a later hotkey
    /// press to overwrite whatever the user types. If the panel was hidden,
    /// the resize re-anchors its top edge.
    func showEditor() {
        mode.isExpanded = true
        show(text: newlyCopiedText())
    }

    /// Shows the panel. A nil or blank `text` keeps the current content; new
    /// text translates automatically.
    func show(text: String?) {
        let model = TranslationViewModel.shared
        // Whatever is on the clipboard now is not "new" for the next hotkey
        // press, whether the panel was opened by the hotkey, the menu or the
        // Service.
        seenChangeCount = NSPasteboard.general.changeCount
        // Trim only to compare; keep the text as given (e.g. indentation).
        if let text, let newText = ClipboardRules.trimmed(text) {
            let currentText = ClipboardRules.trimmed(model.sourceText)
            if newText != currentText {
                model.sourceText = text
            } else if model.lastRunFailed {
                model.retranslate()
            }
        }
        if !isVisibleHere {
            let contentSize = panel.contentView?.fittingSize ?? .zero
            panel.setContentSize(contentSize)
            // Clamp the whole window, title bar included.
            let frameSize = panel.frame.size
            panel.setFrameOrigin(origin(for: frameSize))
            anchoredTop = panel.frame.maxY
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Keeps a frame inside the visible area of the screen it is mostly on.
    private func clamped(_ frame: NSRect) -> NSRect {
        let screen = panel.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            return frame
        }
        return Self.clamp(frame, to: visible)
    }

    /// Pulls `frame` inside `visible`. A frame larger than `visible` keeps
    /// its top edge (the title bar) inside and hangs off the bottom; it also
    /// keeps its right edge, only because the upper bound is applied last.
    static func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var result = frame
        let maxX = visible.maxX - frame.width
        let maxY = visible.maxY - frame.height
        result.origin.x = min(max(frame.minX, visible.minX), maxX)
        result.origin.y = min(max(frame.minY, visible.minY), maxY)
        return result
    }

    /// The hotkey: translates the text selected in the frontmost app when
    /// Konnyaku has the Accessibility permission. Otherwise, or with nothing
    /// selected, it behaves like Translate Clipboard.
    func translateSelectionOrClipboard() {
        // In Konnyaku itself, the hotkey keeps toggling the panel.
        if isFocusedHere {
            toggleWithClipboard()
            return
        }
        // Querying ourselves would block on our own main thread, and ⌘C
        // would go to our own window.
        if NSApp.isActive {
            toggleWithClipboard()
            return
        }
        if !SelectionReader.isTrusted {
            SelectionReader.requestAccessOnce()
            toggleWithClipboard()
            return
        }
        if isReadingSelection {
            return
        }
        isReadingSelection = true
        Task {
            let selection = await SelectionReader.selectedText()
            isReadingSelection = false
            if selection.text == nil {
                seenChangeCount = ClipboardRules.seenChangeCountAfterFallback(
                    seenChangeCount,
                    countBeforeCopy: selection.countBeforeCopy,
                    restoredChangeCount: selection.restoredChangeCount
                )
                toggleWithClipboard()
                return
            }
            show(text: selection.text)
        }
    }

    /// Translate Clipboard: translates newly copied text (showing the panel if needed).
    /// With nothing new on the clipboard, it hides the panel if it is focused
    /// on this Space, or shows and focuses it with the current content.
    func toggleWithClipboard() {
        let newText = newlyCopiedText()
        // Visible but unfocused (user clicked another app): bring it back
        // instead of hiding it.
        if newText == nil && isFocusedHere {
            panel.close()
            return
        }
        show(text: newText)
    }

    /// The clipboard text if the user copied a new request since the panel
    /// was last shown.
    private func newlyCopiedText() -> String? {
        let pasteboard = NSPasteboard.general
        let model = TranslationViewModel.shared
        let isNewCopy = ClipboardRules.isNewCopy(
            changeCount: pasteboard.changeCount,
            seenChangeCount: seenChangeCount,
            ownCopyChangeCount: model.ownCopyChangeCount,
            types: {
                pasteboard.types ?? []
            }
        )
        // Read the text only for a new copy, so a password manager's
        // secret is never read.
        if !isNewCopy {
            return nil
        }
        let text = pasteboard.string(forType: .string)
        let isNewRequest = ClipboardRules.isNewRequest(
            text,
            sourceText: model.sourceText,
            output: model.output,
            lastRunFailed: model.lastRunFailed
        )
        if !isNewRequest {
            return nil
        }
        return text
    }

    /// Near the mouse cursor, kept inside the screen under it.
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screenUnderMouse = NSScreen.screens.first { candidate in
            NSMouseInRect(mouse, candidate.frame, false)
        }
        let screen = screenUnderMouse ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            return mouse
        }
        return Self.origin(mouse: mouse, size: size, visible: visible)
    }

    /// Just below `mouse`, pulled inside `visible`.
    static func origin(mouse: NSPoint, size: NSSize, visible: NSRect) -> NSPoint {
        let belowMouse = NSPoint(x: mouse.x, y: mouse.y - size.height)
        let frame = NSRect(origin: belowMouse, size: size)
        return clamp(frame, to: visible).origin
    }
}
