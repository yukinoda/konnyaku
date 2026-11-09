import AppKit
import SwiftUI

/// The Settings rows for the translate shortcut. Click the field (or Tab to
/// it and press Space or Return), then type the new shortcut. Esc, a click
/// elsewhere or leaving the window cancels.
struct ShortcutRecorder: View {
    @ObservedObject private var hotKeys = GlobalHotKey.shared
    @State private var isRecording = false
    @State private var feedback: Feedback?

    /// Messages are built when the event happens, not on every render.
    private enum Feedback {
        case saved(String)
        /// Saved, but the user loses something with it.
        case warning(String)
        case problem(String)
    }

    var body: some View {
        // An HStack rather than LabeledContent: LabeledContent aligns by
        // text baseline, which the AppKit field doesn't have, so it sat low.
        HStack(spacing: 6) {
            Text("Translate selection")
            Spacer()
            RecorderField(
                name: hotKeys.name,
                onStart: startRecording,
                onCancel: cancelRecording,
                onRecord: record
            )
            .fixedSize()
            resetButton
                // Kept in the layout (just hidden) so the row doesn't shift
                // when it comes and goes.
                .opacity(showsReset ? 1 : 0)
                .disabled(!showsReset)
                .accessibilityHidden(!showsReset)
        }

        statusLine
    }

    /// Also offered after a launch-time fallback, to accept ⌃⌥T for good,
    /// and while the shortcut fails: a ⌃⌥T held by another app can't be
    /// recorded (that app gets the keystroke), so reset is how to retry it.
    private var showsReset: Bool {
        if isRecording {
            return false
        }
        let isCustom = hotKeys.hotKey != .default
        let fellBack = hotKeys.skipped != nil
        let isFailing = hotKeys.failure != nil
        return isCustom || fellBack || isFailing
    }

    private var resetButton: some View {
        Button {
            apply(.default)
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .help("Reset to \(hotKeys.defaultName)")
        .accessibilityLabel("Reset to \(hotKeys.defaultName)")
    }

    /// Always present and at least two lines tall, so Settings doesn't
    /// resize as messages come and go.
    private var statusLine: some View {
        ZStack(alignment: .topLeading) {
            Text(" \n ")
                .hidden()
            statusText
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: Text {
        if isRecording {
            // A combination another app already holds never reaches us, so
            // say how to get out of a field that seems stuck.
            return secondary("Press the new shortcut, or Esc to cancel.")
        }
        // Several can apply: why the last attempt failed, that the saved
        // shortcut was skipped at launch, and that the current one fails.
        var parts: [Text] = []
        var shownProblem: String?
        switch feedback {
        case .saved(let message):
            parts.append(saved(message))
        case .warning(let message):
            parts.append(warning(message))
        case .problem(let message):
            parts.append(error(message))
            shownProblem = message
        case nil:
            break
        }
        if let launchMessage = launchFallbackMessage {
            parts.append(error(launchMessage))
        }
        if let failure = hotKeys.failure {
            let message = failure.message(for: hotKeys.name)
            // e.g. re-recording a shortcut that is already failing.
            if message != shownProblem {
                parts.append(error(message))
            }
        }
        guard var combined = parts.first else {
            return secondary("Click the shortcut to change it.")
        }
        for part in parts.dropFirst() {
            combined = combined + Text(" ") + part
        }
        return combined
    }

    private var launchFallbackMessage: String? {
        guard let skippedName = hotKeys.skippedName else {
            return nil
        }
        let skipped: String
        switch hotKeys.skipReason {
        case .notRegisteredAtLaunch:
            skipped = "\(skippedName) couldn't be turned on when Konnyaku started"
        case .keyboardLayout:
            skipped = "\(skippedName) can't be used with this keyboard layout"
        }
        // If the fallback failed too, the failure message says so.
        if hotKeys.failure != nil {
            return skipped + "."
        }
        return skipped + ", so \(hotKeys.name) is used. Pick another, or reset to keep it."
    }

    private func secondary(_ message: String) -> Text {
        Text(message)
            .foregroundColor(.secondary)
    }

    private func error(_ message: String) -> Text {
        Text(message)
            .foregroundColor(.red)
    }

    private func saved(_ message: String) -> Text {
        Text("\(Image(systemName: "checkmark.circle.fill")) \(message)")
            .foregroundColor(.green)
    }

    private func warning(_ message: String) -> Text {
        Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(message)")
            .foregroundColor(.orange)
    }

    // MARK: Recording

    private func startRecording() {
        feedback = nil
        isRecording = true
        // The current shortcut must reach the field instead of opening the
        // popup.
        hotKeys.suspend()
    }

    private func cancelRecording() {
        isRecording = false
        hotKeys.resume()
    }

    private func record(_ event: NSEvent) {
        isRecording = false
        guard let candidate = HotKey(event: event) else {
            reject("That key can't be used. Try a different key.")
            return
        }
        apply(candidate)
    }

    private func reject(_ message: String) {
        hotKeys.resume()
        feedback = .problem(message)
    }

    /// For a recorded shortcut and for ↺ alike, so ⌃⌥T also gets the
    /// macOS-shortcut warning.
    private func apply(_ candidate: HotKey) {
        // Lazy: macOS's shortcut list is only read if the shortcut isn't
        // blocked anyway.
        let verdict = candidate.verdict(isSystemShortcut: GlobalHotKey.isSystemShortcut(candidate))
        if case .blocked(let message) = verdict {
            reject(message)
            return
        }
        let name = candidate.displayString
        // change(to:) registers the new shortcut itself, so the old one is
        // resumed only when nothing changes.
        if let failure = hotKeys.change(to: candidate) {
            feedback = .problem(failure.message(for: name))
            return
        }
        if case .warning(let message) = verdict {
            feedback = .warning("Saved. " + message)
            return
        }
        // Other apps' shortcuts can't always be detected, so invite a test.
        feedback = .saved("Saved. Try \(name) in any app now. If nothing happens, another app may be using it.")
    }
}
