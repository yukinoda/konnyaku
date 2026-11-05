import AppKit
import SwiftUI

/// Esc closes the panel.
private final class FloatingPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// A small floating window hosting the same ContentView and view model as the
/// menu-bar popover.
@MainActor
final class TranslatePanelController {
    static let shared = TranslatePanelController()

    private let panel: FloatingPanel

    private init() {
        let style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
        panel = FloatingPanel(
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
    }

    /// Shows the panel. A nil or empty `text` keeps the current content; new
    /// text translates automatically.
    func show(text: String?) {
        let model = TranslationViewModel.shared
        if let text, !text.isEmpty, text != model.sourceText {
            model.sourceText = text
        }
        let size = panel.contentView?.fittingSize ?? .zero
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the visible panel unless the clipboard holds new text, otherwise
    /// shows it with the clipboard text.
    func toggleWithClipboard() {
        let clipboardText = NSPasteboard.general.string(forType: .string)
        if panel.isVisible {
            let hasNewText = clipboardText?.isEmpty == false
                && clipboardText != TranslationViewModel.shared.sourceText
            if !hasNewText {
                panel.close()
                return
            }
        }
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
