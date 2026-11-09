import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The Settings rows for the translate shortcut. Click the field (or focus
/// it and press Space or Return), then type the new shortcut. Esc, a click
/// or leaving the window cancels.
struct ShortcutRecorder: View {
    @ObservedObject private var hotKeys = GlobalHotKey.shared
    @State private var isRecording = false
    @State private var monitors: [Any] = []
    @State private var feedback: Feedback?
    /// The key window when recording started (Settings).
    @State private var recordingWindow: NSWindow?

    private enum Feedback {
        case saved(String)
        case problem(String)
    }

    private static let defaultName = HotKey.default.displayString

    var body: some View {
        LabeledContent("Translate selection") {
            HStack(spacing: 6) {
                field
                if showsReset {
                    resetButton
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            // Only the Settings window: another window closing mustn't cancel.
            if notification.object as? NSWindow === recordingWindow {
                stopRecording()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
        .onDisappear {
            stopRecording()
        }

        caption
    }

    private var field: some View {
        Text(isRecording ? "Type shortcut…" : hotKeys.hotKey.displayString)
            .foregroundStyle(isRecording ? .secondary : .primary)
            .frame(minWidth: 110)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.5))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                startRecording()
            }
            .focusable()
            .onKeyPress(keys: [.space, .return]) { _ in
                startRecording()
                return .handled
            }
            .help("Click, then type a new shortcut")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Translate selection shortcut")
            .accessibilityValue(isRecording ? "Type shortcut" : hotKeys.hotKey.displayString)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                startRecording()
            }
    }

    /// Also offered after a launch-time fallback, to accept ⌃⌥T for good.
    private var showsReset: Bool {
        hotKeys.hotKey != .default || hotKeys.unavailableAtLaunch != nil
    }

    private var resetButton: some View {
        Button {
            stopRecording()
            apply(.default)
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .help("Reset to \(Self.defaultName)")
        .accessibilityLabel("Reset to \(Self.defaultName)")
    }

    @ViewBuilder
    private var caption: some View {
        if let feedback {
            switch feedback {
            case .saved(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .problem(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else if !hotKeys.isRegistered {
            // Checked first: after a failed fallback, ⌃⌥T isn't working either.
            Text(
                "\(hotKeys.hotKey.displayString) is already in use, so it does nothing. "
                    + "Choose a different shortcut."
            )
            .font(.caption)
            .foregroundStyle(.red)
        } else if let saved = hotKeys.unavailableAtLaunch {
            Text(
                "\(saved.displayString) was already in use when Konnyaku started, "
                    + "so \(hotKeys.hotKey.displayString) is used instead. "
                    + "Choose a different shortcut, or reset to keep \(Self.defaultName)."
            )
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    private func startRecording() {
        if isRecording {
            return
        }
        // Started by assistive technology while another app is active, no
        // key or focus change would end recording, and the shortcut would
        // stay switched off.
        if !NSApp.isActive {
            return
        }
        feedback = nil
        isRecording = true
        recordingWindow = NSApp.keyWindow
        hotKeys.suspend()
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Holding the Space or Return that started recording repeats it.
            if !event.isARepeat {
                record(event)
            }
            return nil
        }
        // Swallowed so the click only cancels; a click on the field would
        // otherwise start recording again.
        let mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { _ in
            stopRecording()
            return nil
        }
        monitors = [keyMonitor, mouseMonitor].compactMap { $0 }
    }

    private func stopRecording() {
        if !isRecording {
            return
        }
        removeMonitors()
        hotKeys.resume()
    }

    private func removeMonitors() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        isRecording = false
        recordingWindow = nil
    }

    private func record(_ event: NSEvent) {
        // change(to:) registers the new shortcut itself, so the old one is
        // resumed only when nothing changes.
        removeMonitors()
        if event.keyCode == UInt16(kVK_Escape) {
            hotKeys.resume()
            return
        }
        guard let candidate = HotKey(event: event) else {
            reject("That key can't be used. Try a different key.")
            return
        }
        if let problem = candidate.problem {
            reject(problem)
            return
        }
        if GlobalHotKey.isSystemShortcut(candidate) {
            reject("\(candidate.displayString) is a macOS shortcut. Try a different shortcut.")
            return
        }
        apply(candidate)
    }

    private func reject(_ message: String) {
        hotKeys.resume()
        feedback = .problem(message)
    }

    private func apply(_ candidate: HotKey) {
        let name = candidate.displayString
        if hotKeys.change(to: candidate) {
            // Other apps' shortcuts can't always be detected, so invite a test.
            feedback = .saved(
                "Saved. Try it now: select text in any app and press \(name). "
                    + "If nothing happens, another app may be using it."
            )
        } else {
            feedback = .problem("\(name) is already in use. Try a different shortcut.")
        }
    }
}
