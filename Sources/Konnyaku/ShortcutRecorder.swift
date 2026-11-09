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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
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
        } else if let saved = hotKeys.unavailableAtLaunch {
            Text(
                "\(saved.displayString) was already in use when Konnyaku started, "
                    + "so \(hotKeys.hotKey.displayString) is used instead. "
                    + "Choose a different shortcut, or reset to keep \(Self.defaultName)."
            )
            .font(.caption)
            .foregroundStyle(.red)
        } else if !hotKeys.isRegistered {
            Text(
                "\(hotKeys.hotKey.displayString) is already in use, so it does nothing. "
                    + "Choose a different shortcut."
            )
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    private func startRecording() {
        if isRecording {
            return
        }
        feedback = nil
        isRecording = true
        hotKeys.suspend()
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
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
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        isRecording = false
        hotKeys.resume()
    }

    private func record(_ event: NSEvent) {
        stopRecording()
        if event.keyCode == UInt16(kVK_Escape) {
            return
        }
        guard let candidate = HotKey(event: event) else {
            feedback = .problem("That key can't be used. Try a different key.")
            return
        }
        if let problem = candidate.problem {
            feedback = .problem(problem)
            return
        }
        apply(candidate)
    }

    private func apply(_ candidate: HotKey) {
        let name = candidate.displayString
        if hotKeys.change(to: candidate) {
            feedback = .saved("Saved. Select text in any app and press \(name).")
        } else {
            feedback = .problem("\(name) is already in use. Try a different shortcut.")
        }
    }
}
