import AppKit
import SwiftUI

/// A small floating window hosting the same ContentView and view model as the
/// menu-bar popover.
@MainActor
final class TranslatePanelController {
    static let shared = TranslatePanelController()

    private static let escapeKeyCode: UInt16 = 53

    private let panel: NSPanel
    /// The clipboard change count when the panel was last shown. A different
    /// count means the user copied something new since then. Starts at -1
    /// (nothing seen yet) so the first ⌃⌥T reads the clipboard.
    private var seenChangeCount = -1

    private init() {
        let style: NSWindow.StyleMask = [.titled, .closable, .nonactivatingPanel]
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
        let content = ContentView(model: TranslationViewModel.shared, showsQuit: false)
        let hosting = NSHostingController(rootView: content)
        // Grows the panel when a status or progress row appears.
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        installEscapeMonitor()
    }

    /// The focused text view consumes Esc before the panel sees it, so close
    /// from a key monitor instead.
    private func installEscapeMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else {
                return event
            }
            if event.keyCode != Self.escapeKeyCode {
                return event
            }
            // Esc that cancels an IME composition must not close the panel.
            let inputClient = self.panel.firstResponder as? NSTextInputClient
            if inputClient?.hasMarkedText() == true {
                return event
            }
            self.panel.close()
            return nil
        }
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
            let size = panel.contentView?.fittingSize ?? .zero
            panel.setContentSize(size)
            panel.setFrameOrigin(origin(for: size))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// ⌃⌥T: translates newly copied text (showing the panel if needed).
    /// With nothing new on the clipboard, it hides the panel if it is open on
    /// this Space, or shows it with the current content.
    func toggleWithClipboard() {
        let newText = newlyCopiedText()
        if newText == nil && isVisibleHere {
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
