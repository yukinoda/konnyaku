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
                ContentView(model: model, showsQuit: false)
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
            .disabled(model.output.isEmpty)
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
        if model.output.isEmpty {
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

    private var hasSource: Bool {
        let text = model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty
    }

    /// Busy means a translation is pending: there is text and no error yet.
    private var isBusy: Bool {
        hasSource && !model.lastRunFailed
    }

    private var statusText: String {
        if !hasSource {
            return "Copy some text, then press ⌃⌥T"
        }
        return model.status ?? "Translating..."
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if let progress = model.downloadProgress {
                ProgressView(value: progress)
                    .frame(width: 120)
            } else if isBusy {
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
