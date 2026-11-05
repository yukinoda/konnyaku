import AppKit
import SwiftUI

/// The full editor: the source text on top, the translation below.
struct ContentView: View {
    @ObservedObject var model: TranslationViewModel
    @FocusState private var isSourceFocused: Bool
    /// True for a moment after Copy, to confirm it.
    @State private var didCopy = false

    private static let paneShape = RoundedRectangle(cornerRadius: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourcePane
            directionBar
            outputPane
            hints
        }
        .padding(12)
        .frame(width: 480)
        .onAppear {
            isSourceFocused = true
        }
        .task(id: didCopy) {
            if !didCopy {
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }

    // MARK: - Source

    private var sourcePane: some View {
        TextEditor(text: $model.sourceText)
            .font(.title3)
            .scrollContentBackground(.hidden)
            .focused($isSourceFocused)
            .padding(.leading, 4)
            // Keeps the text clear of the Clear button.
            .padding(.trailing, 28)
            .padding(.vertical, 8)
            .frame(height: 130)
            .background(alignment: .topLeading) {
                if model.sourceText.isEmpty {
                    sourcePlaceholder
                }
            }
            .overlay(alignment: .topTrailing) {
                if hasSource {
                    clearButton
                }
            }
            .background(Color(nsColor: .textBackgroundColor), in: Self.paneShape)
            .overlay {
                Self.paneShape.strokeBorder(.separator)
            }
            .accessibilityLabel("Text to translate")
    }

    private var sourcePlaceholder: some View {
        Text("Type or paste text to translate")
            .font(.title3)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }

    private var clearButton: some View {
        Button {
            model.sourceText = ""
            isSourceFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .padding(8)
        .help("Clear")
        .accessibilityLabel("Clear text")
    }

    // MARK: - Direction

    /// The target language, where Auto is going, and Swap.
    private var directionBar: some View {
        HStack(spacing: 8) {
            Picker("Translate to", selection: $model.targetCode) {
                Text("Auto (ja ↔ en)").tag(TranslationViewModel.autoCode)
                ForEach(TargetLanguage.choices, id: \.code) { choice in
                    Text(choice.name).tag(choice.code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Translate to")

            if let autoTargetName {
                Text("→ \(autoTargetName)")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: swapDirection) {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!hasFreshOutput)
            .help("Translate the result back (⇧⌘R)")
            .accessibilityLabel("Swap direction")
        }
    }

    // MARK: - Output

    private var outputPane: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                Text(model.output)
                    .font(.title3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.top, 8)
                    // Room for the footer row.
                    .padding(.bottom, 36)
            }
            // While busy, the output still belongs to the previous request.
            .opacity(model.isBusy ? 0.35 : 1)
            .accessibilityLabel("Translation")

            if model.output.isEmpty && !model.isBusy {
                outputPlaceholder
            }
        }
        .overlay(alignment: .bottom) {
            outputFooter
        }
        .frame(height: 150)
        .background(.fill.quaternary, in: Self.paneShape)
        .animation(.easeOut(duration: 0.15), value: model.isBusy)
    }

    /// "Translation", or the error from the last run.
    private var outputPlaceholder: some View {
        Text(model.status ?? "Translation")
            .font(.title3)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
    }

    private var outputFooter: some View {
        HStack(spacing: 8) {
            progressView
            Spacer()
            copyButton
        }
        .padding(8)
    }

    @ViewBuilder
    private var progressView: some View {
        if let progress = model.downloadProgress {
            ProgressView(value: progress)
                .frame(width: 120)
        } else if model.isBusy {
            ProgressView()
                .controlSize(.small)
        }
        if model.isBusy {
            Text(model.status ?? "Translating...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var copyButton: some View {
        Button(action: copy) {
            Label(
                didCopy ? "Copied" : "Copy",
                systemImage: didCopy ? "checkmark" : "doc.on.doc"
            )
        }
        .controlSize(.small)
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .disabled(!hasFreshOutput)
        .help("Copy the translation (⇧⌘C)")
        .accessibilityLabel(didCopy ? "Copied" : "Copy translation")
    }

    private var hints: some View {
        Text("⇧⌘C copy · ⇧⌘R swap · esc close")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Helpers

    private var hasSource: Bool {
        let text = model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty
    }

    /// Output that belongs to the current text and target.
    private var hasFreshOutput: Bool {
        if model.isBusy {
            return false
        }
        return !model.output.isEmpty
    }

    /// In Auto, the language the current text goes to.
    private var autoTargetName: String? {
        if model.targetCode != TranslationViewModel.autoCode {
            return nil
        }
        if !hasSource {
            return nil
        }
        let code = TargetLanguage.auto(for: model.sourceText)
        let choice = TargetLanguage.choices.first { $0.code == code }
        return choice?.name
    }

    private func copy() {
        model.copyOutput()
        didCopy = true
    }

    /// Translates the result back. Auto picks the direction from the
    /// result's script, so a non-Japanese result goes to Japanese.
    private func swapDirection() {
        let translation = model.output
        model.targetCode = TranslationViewModel.autoCode
        model.sourceText = translation
        isSourceFocused = true
    }
}
