import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The shortcut field in Settings, an AppKit view so it can take first
/// responder: it records while focused, gets ⌘ combinations through
/// performKeyEquivalent, and stops when focus moves elsewhere. A SwiftUI
/// view needs app-wide event monitors for all of that.
struct RecorderField: NSViewRepresentable {
    /// The current shortcut, shown while not recording.
    var name: String
    var onStart: () -> Void
    var onCancel: () -> Void
    /// A key-down to turn into the new shortcut (Esc and Tab already
    /// handled).
    var onRecord: (NSEvent) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        update(view)
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        update(view)
    }

    /// Leaving Settings mid-recording must give the shortcut back.
    static func dismantleNSView(_ view: RecorderView, coordinator: ()) {
        view.cancel()
    }

    private func update(_ view: RecorderView) {
        view.name = name
        view.onStart = onStart
        view.onCancel = onCancel
        view.onRecord = onRecord
    }
}

final class RecorderView: NSView {
    var name = "" {
        didSet {
            refresh()
        }
    }
    var onStart: () -> Void = {}
    var onCancel: () -> Void = {}
    var onRecord: (NSEvent) -> Void = { _ in }

    private(set) var isRecording = false
    /// Modifiers held while recording, shown live ("⌃⌥…").
    private var heldModifiers: UInt32 = 0
    private var mouseMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

    private static let placeholder = "Type shortcut…"
    private static let cornerRadius: CGFloat = 6

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Click, then type a new shortcut"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: Focus

    override var acceptsFirstResponder: Bool {
        true
    }

    /// In the Tab loop even when Full Keyboard Access is off, so keyboard
    /// users can always reach it.
    override var canBecomeKeyView: Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        // Clicking another control moves focus there: cancel, and that
        // control still gets its click.
        cancel()
        return super.resignFirstResponder()
    }

    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func drawFocusRingMask() {
        roundedPath().fill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
        resignKeyObserver = nil
        guard let window else {
            return
        }
        // Switching apps or windows keeps first responder, so watch the
        // window itself.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancel()
            }
        }
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            handleWhileRecording(event)
            return
        }
        let modifiers = HotKey.carbonModifiers(from: event.modifierFlags)
        let isSpace = event.keyCode == UInt16(kVK_Space)
        let isReturn = event.keyCode == UInt16(kVK_Return)
        if modifiers == 0 && (isSpace || isReturn) {
            startRecording()
            return
        }
        // Tab and everything else go on to the window as usual.
        super.keyDown(with: event)
    }

    /// ⌘ combinations arrive here, before keyDown and before the menus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isFocused = window?.firstResponder === self
        if isRecording && isFocused {
            handleWhileRecording(event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if isRecording {
            heldModifiers = HotKey.carbonModifiers(from: event.modifierFlags)
            refresh()
        }
        super.flagsChanged(with: event)
    }

    private func handleWhileRecording(_ event: NSEvent) {
        // Holding the Space or Return that started recording repeats it.
        if event.isARepeat {
            return
        }
        let modifiers = HotKey.carbonModifiers(from: event.modifierFlags)
        // Plain Esc cancels; with modifiers it can be a shortcut.
        if event.keyCode == UInt16(kVK_Escape) && modifiers == 0 {
            cancel()
            return
        }
        // Plain Tab (or ⇧Tab) moves focus on as usual.
        let isTab = event.keyCode == UInt16(kVK_Tab)
        let isPlainTab = modifiers & ~UInt32(shiftKey) == 0
        if isTab && isPlainTab {
            cancel()
            super.keyDown(with: event)
            return
        }
        endRecording()
        onRecord(event)
    }

    // MARK: Recording

    func startRecording() {
        if isRecording {
            return
        }
        // Started by VoiceOver while another app or window is active, no
        // key or focus change would ever end recording.
        guard let window, window.isKeyWindow else {
            return
        }
        window.makeFirstResponder(self)
        isRecording = true
        heldModifiers = HotKey.carbonModifiers(from: NSEvent.modifierFlags)
        // Clicks on things that don't take focus (the title bar, plain
        // text) must cancel too. The click always goes through.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.cancelIfOutside(event)
            return event
        }
        onStart()
        refresh()
    }

    func cancel() {
        if !isRecording {
            return
        }
        endRecording()
        onCancel()
    }

    private func endRecording() {
        isRecording = false
        heldModifiers = 0
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        refresh()
    }

    private func cancelIfOutside(_ event: NSEvent) {
        let isSameWindow = event.window === window
        let point = convert(event.locationInWindow, from: nil)
        let isOnField = isSameWindow && bounds.contains(point)
        if !isOnField {
            cancel()
        }
    }

    // MARK: Drawing

    private var displayedText: String {
        if !isRecording {
            return name
        }
        if heldModifiers != 0 {
            return HotKey.modifierSymbols(heldModifiers) + "…"
        }
        return Self.placeholder
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let color = isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        return [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: color,
        ]
    }

    /// Wide enough for the name and the placeholder, so the field doesn't
    /// change size when recording starts.
    override var intrinsicContentSize: NSSize {
        let nameWidth = (name as NSString).size(withAttributes: textAttributes).width
        let placeholderWidth = (Self.placeholder as NSString).size(withAttributes: textAttributes).width
        let textWidth = max(nameWidth, placeholderWidth)
        return NSSize(width: max(110, textWidth + 24), height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = roundedPath()
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        if isRecording {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        let text = displayedText as NSString
        let size = text.size(withAttributes: textAttributes)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        text.draw(at: origin, withAttributes: textAttributes)
    }

    private func roundedPath() -> NSBezierPath {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        return NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
    }

    private func refresh() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityLabel() -> String? {
        "Translate selection shortcut"
    }

    override func accessibilityValue() -> Any? {
        displayedText
    }

    override func accessibilityPerformPress() -> Bool {
        startRecording()
        return isRecording
    }
}
