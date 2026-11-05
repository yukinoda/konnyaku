import AppKit
import SwiftUI

/// Borderless panels refuse key status by default, which would stop the text
/// editor from receiving typing. Esc closes the panel.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

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
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ContentView(model: TranslationViewModel.shared))
    }

    /// Shows the panel with `text`, which translates automatically.
    func show(text: String) {
        TranslationViewModel.shared.sourceText = text
        let size = panel.contentView?.fittingSize ?? .zero
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the panel if it is visible, otherwise shows it with the clipboard text.
    func toggleWithClipboard() {
        if panel.isVisible {
            panel.close()
            return
        }
        let clipboardText = NSPasteboard.general.string(forType: .string)
        show(text: clipboardText ?? "")
    }

    /// Near the mouse cursor, kept inside the screen under it.
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            return mouse
        }
        let maxX = visible.maxX - size.width
        let minY = visible.minY
        let x = min(max(mouse.x, visible.minX), maxX)
        let y = max(mouse.y - size.height, minY)
        return NSPoint(x: x, y: y)
    }
}
