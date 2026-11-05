import AppKit
import SwiftUI

/// A small floating window hosting the same ContentView and view model as the
/// menu-bar popover.
@MainActor
final class TranslatePanelController {
    static let shared = TranslatePanelController()

    private static let escapeKeyCode: UInt16 = 53

    private let panel: NSPanel
    /// The clipboard change count when the panel last took text from it or
    /// wrote to it. A different count means the user copied something new.
    private var seenChangeCount = NSPasteboard.general.changeCount

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
        panel.contentView = NSHostingView(rootView: ContentView(model: TranslationViewModel.shared))
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
            self.panel.close()
            return nil
        }
    }

    /// Call after the app itself writes to the clipboard, so that write does
    /// not count as new text.
    func recordClipboard() {
        seenChangeCount = NSPasteboard.general.changeCount
    }

    /// Shows the panel. A nil or empty `text` keeps the current content; new
    /// text translates automatically.
    func show(text: String?) {
        let model = TranslationViewModel.shared
        if let text, !text.isEmpty {
            if text != model.sourceText {
                model.sourceText = text
            } else if model.output.isEmpty {
                model.retranslate()
            }
        }
        if !panel.isVisible {
            let size = panel.contentView?.fittingSize ?? .zero
            panel.setContentSize(size)
            panel.setFrameOrigin(origin(for: size))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the visible panel unless the clipboard changed since the panel
    /// last saw it, otherwise shows it with the clipboard text.
    func toggleWithClipboard() {
        let pasteboard = NSPasteboard.general
        let clipboardChanged = pasteboard.changeCount != seenChangeCount
        let clipboardText = pasteboard.string(forType: .string)
        let hasNewText = clipboardChanged && clipboardText?.isEmpty == false
        if panel.isVisible && !hasNewText {
            panel.close()
            return
        }
        recordClipboard()
        show(text: clipboardText)
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
