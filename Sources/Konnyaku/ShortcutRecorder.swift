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

    /// Computed, so it follows keyboard layout changes.
    private var defaultName: String {
        HotKey.default.displayString
    }

    var body: some View {
        LabeledContent("Translate selection") {
            HStack(spacing: 6) {
                field
                // Hidden while recording: a click there would only cancel.
                if showsReset && !isRecording {
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
            apply(.default)
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .help("Reset to \(defaultName)")
        .accessibilityLabel("Reset to \(defaultName)")
    }

    @ViewBuilder
    private var caption: some View {
        if isRecording {
            // A combination another app already holds never reaches us, so
            // say how to get out of a field that seems stuck.
            Text("Press the new shortcut, or Esc to cancel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // Both can show: why the last attempt failed, and that the
            // current shortcut does nothing.
            feedbackCaption
            stateCaption
        }
    }

    @ViewBuilder
    private var feedbackCaption: some View {
        switch feedback {
        case .saved(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .problem(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var stateCaption: some View {
        if let failure = hotKeys.failure {
            Text(failure.message(for: hotKeys.hotKey))
                .font(.caption)
                .foregroundStyle(.red)
        } else if let saved = hotKeys.unavailableAtLaunch {
            Text(
                "\(saved.displayString) couldn't be turned on when Konnyaku started, "
                    + "so \(hotKeys.hotKey.displayString) is used instead. "
                    + "Choose a different shortcut, or reset to keep \(defaultName)."
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
        // Needed so the focus-loss cancel and the click check can tell the
        // Settings window apart.
        guard let keyWindow = NSApp.keyWindow else {
            return
        }
        feedback = nil
        isRecording = true
        recordingWindow = keyWindow
        hotKeys.suspend()
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Holding the Space or Return that started recording repeats it.
            if !event.isARepeat {
                record(event)
            }
            return nil
        }
        let mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { event in
            let isInSettings = event.window === recordingWindow
            stopRecording()
            // In Settings the click only cancels; on the field it would
            // otherwise start recording again. Elsewhere (the menu bar
            // icon, the popup) it goes through.
            if isInSettings {
                return nil
            }
            return event
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
        apply(candidate)
    }

    private func reject(_ message: String) {
        hotKeys.resume()
        feedback = .problem(message)
    }

    private func apply(_ candidate: HotKey) {
        let name = candidate.displayString
        if let failure = hotKeys.change(to: candidate) {
            feedback = .problem(failure.message(for: candidate))
        } else {
            // Other apps' shortcuts can't always be detected, so invite a test.
            feedback = .saved(
                "Saved. Try it now: select text in any app and press \(name). "
                    + "If nothing happens, another app may be using it."
            )
        }
    }
}
