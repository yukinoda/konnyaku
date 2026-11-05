import AppKit
import SwiftUI

/// A small floating popup showing the translation, which ⌘E expands into the
/// same editor as the menu-bar popover (same view model).
@MainActor
final class TranslatePanelController {
    static let shared = TranslatePanelController()

    private static let escapeKeyCode: UInt16 = 53
    private static let returnKeyCode: UInt16 = 36

    private let panel: NSPanel
    private let mode = PanelMode()
    /// Where the panel's top edge should stay while its content resizes.
    private var anchoredTop: CGFloat?
    /// The clipboard change count when the panel was last shown. A different
    /// count means the user copied something new since then. Starts at -1
    /// (nothing seen yet) so the first ⌃⌥T reads the clipboard.
    private var seenChangeCount = -1

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

    /// The focused text view consumes Esc and Return before the panel sees
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

    /// Esc closes; in the compact popup, Return copies and ⌘E opens the
    /// editor. Returns true if the event was handled.
    private func handle(_ event: NSEvent) -> Bool {
        // Keys that confirm or cancel an IME composition belong to it.
        let inputClient = panel.firstResponder as? NSTextInputClient
        if inputClient?.hasMarkedText() == true {
            return false
        }
        // Only these modifiers change a shortcut; Caps Lock and Fn don't.
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let modifiers = event.modifierFlags.intersection(shortcutModifiers)
        if event.keyCode == Self.escapeKeyCode {
            panel.close()
            return true
        }
        if mode.isExpanded {
            return false
        }
        if event.keyCode == Self.returnKeyCode && modifiers.isEmpty {
            copyAndClose()
            return true
        }
        // By character, not key code, so ⌘E works on any keyboard layout.
        let character = event.charactersIgnoringModifiers?.lowercased()
        if character == "e" && modifiers == .command {
            expand()
            return true
        }
        return false
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
        if model.output.isEmpty || model.isBusy {
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

    private func trimmed(_ text: String?) -> String? {
        let result = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if result?.isEmpty == true {
            return nil
        }
        return result
    }

    /// Shows the panel. A nil or blank `text` keeps the current content; new
    /// text translates automatically.
    func show(text: String?) {
        let model = TranslationViewModel.shared
        // Whatever is on the clipboard now is not "new" for the next ⌃⌥T,
        // whether the panel was opened by the hotkey or by the Service.
        seenChangeCount = NSPasteboard.general.changeCount
        // Trim only to compare; keep the text as given (e.g. indentation).
        if let text, let newText = trimmed(text) {
            let currentText = trimmed(model.sourceText)
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
        var result = frame
        let maxX = visible.maxX - frame.width
        let maxY = visible.maxY - frame.height
        result.origin.x = min(max(frame.minX, visible.minX), maxX)
        result.origin.y = min(max(frame.minY, visible.minY), maxY)
        return result
    }

    /// ⌃⌥T: translates newly copied text (showing the panel if needed).
    /// With nothing new on the clipboard, it hides the panel if it is focused
    /// on this Space, or shows and focuses it with the current content.
    func toggleWithClipboard() {
        let newText = newlyCopiedText()
        // Visible but unfocused (user clicked another app): bring it back
        // instead of hiding it.
        let isFocusedHere = isVisibleHere && panel.isKeyWindow
        if newText == nil && isFocusedHere {
            panel.close()
            return
        }
        show(text: newText)
    }

    /// The clipboard text if the user copied something since the panel was
    /// last shown, excluding konjac's own text and concealed data such as
    /// passwords from a password manager.
    private func newlyCopiedText() -> String? {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        if changeCount == seenChangeCount {
            return nil
        }
        if changeCount == TranslationViewModel.shared.ownCopyChangeCount {
            return nil
        }
        if isConcealed(pasteboard) {
            return nil
        }
        let text = pasteboard.string(forType: .string)
        if trimmed(text) == nil {
            return nil
        }
        if isOwnText(text) {
            return nil
        }
        return text
    }

    /// Password managers mark secrets with these nspasteboard.org types.
    private func isConcealed(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let generated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
        let isConcealed = types.contains(concealed)
        let isTransient = types.contains(transient)
        let isGenerated = types.contains(generated)
        return isConcealed || isTransient || isGenerated
    }

    /// Text the user copied out of konjac itself (⌘C on the source or
    /// translation) is not a new request.
    private func isOwnText(_ text: String?) -> Bool {
        let model = TranslationViewModel.shared
        let candidate = trimmed(text)
        // After a failed run, re-copying the source is a retry, not own text.
        let matchesSource = candidate == trimmed(model.sourceText)
        let isSource = matchesSource && !model.lastRunFailed
        let isOutput = candidate == trimmed(model.output)
        return isSource || isOutput
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
        let maxX = visible.maxX - size.width
        let minY = visible.minY
        let x = min(max(mouse.x, visible.minX), maxX)
        let maxY = visible.maxY - size.height
        let y = min(max(mouse.y - size.height, minY), maxY)
        return NSPoint(x: x, y: y)
    }
}
