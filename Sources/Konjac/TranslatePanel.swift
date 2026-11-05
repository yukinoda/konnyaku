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
        let style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
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
        let hosting = NSHostingController(rootView: ContentView(model: TranslationViewModel.shared))
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
            let lastRunFailed = model.status != nil && !model.isTranslating
            if newText != currentText {
                model.sourceText = text
            } else if lastRunFailed {
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

    /// ⌃⌥T: hides the panel if it is open on this Space. Otherwise shows it,
    /// with the clipboard text if the user copied something since the panel
    /// was last shown, or with the current content if not.
    func toggleWithClipboard() {
        if isVisibleHere {
            panel.close()
            return
        }
        let pasteboard = NSPasteboard.general
        let copiedSinceLastShow = pasteboard.changeCount != seenChangeCount
        let clipboardText = pasteboard.string(forType: .string)
        var newText: String?
        if copiedSinceLastShow && !isOwnText(clipboardText) {
            newText = clipboardText
        }
        show(text: newText)
    }

    /// Text the user copied out of konjac itself (Copy button or ⌘C on the
    /// source or translation) is not a new request.
    private func isOwnText(_ text: String?) -> Bool {
        let model = TranslationViewModel.shared
        let candidate = trimmed(text)
        if candidate == nil {
            return false
        }
        let isSource = candidate == trimmed(model.sourceText)
        let isOutput = candidate == trimmed(model.output)
        return isSource || isOutput
    }

    /// Near the mouse cursor, kept inside the screen under it.
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
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
