import SwiftUI

/// Whether the floating panel shows the compact popup or the full editor.
@MainActor
final class PanelMode: ObservableObject {
    @Published var isExpanded = false
}

/// The floating panel's root: the compact popup, or the full editor after ⌘E.
struct PanelRootView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject var mode: PanelMode
    var onCopy: () -> Void
    var onExpand: () -> Void

    var body: some View {
        Group {
            if mode.isExpanded {
                ContentView(model: model)
            } else {
                TranslatePopupView(model: model, onCopy: onCopy, onExpand: onExpand)
            }
        }
        // The title bar is hidden, so use its space too.
        .ignoresSafeArea()
    }
}

/// Just the translation, with the target language, Copy and Edit.
struct TranslatePopupView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject private var hotKeys = GlobalHotKey.shared
    var onCopy: () -> Void
    var onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            result
            hints
        }
        .padding(12)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("To", selection: $model.targetCode) {
                Text("Auto (ja ↔ en)").tag(TranslationViewModel.autoCode)
                ForEach(TargetLanguage.choices, id: \.code) { choice in
                    Text(choice.name).tag(choice.code)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Spacer()

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(!model.hasFreshOutput)
            .help("Copy and close (⏎)")
            .accessibilityLabel("Copy translation")

            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help("Edit the text (⌘E)")
            .accessibilityLabel("Open editor")
        }
    }

    @ViewBuilder
    private var result: some View {
        // A pending result would show the previous request's output.
        if !model.hasFreshOutput {
            statusRow
        } else {
            ScrollView {
                Text(model.output)
                    .font(.title3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        if !model.hasSource {
            return emptyHint
        }
        if let status = model.status {
            return status
        }
        if model.isBusy {
            return "Translating..."
        }
        return "No translation."
    }

    private var emptyHint: String {
        guard let failure = hotKeys.failure else {
            return "Select or copy text, then press \(hotKeys.hotKey.displayString)"
        }
        let menuHint = "Copy text, then choose Translate Clipboard in the menu bar. "
        // Without a handler, no other shortcut would work either.
        if failure == .noHandler {
            return menuHint + "Quit and reopen Konnyaku to fix the shortcut."
        }
        return menuHint + "The shortcut isn't working; change it in Settings."
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if let progress = model.downloadProgress {
                ProgressView(value: progress)
                    .frame(width: 120)
            } else if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private var hints: some View {
        Text("⏎ copy · esc close · ⌘E edit")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
