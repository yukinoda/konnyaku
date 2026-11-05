import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: TranslationViewModel
    /// The floating panel hides Quit so a stray click doesn't end the app.
    var showsQuit = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $model.sourceText)
                .font(.body)
                .frame(height: 110)
                .border(Color.secondary.opacity(0.3))
                .accessibilityLabel("Text to translate")

            HStack {
                Picker("To", selection: $model.targetCode) {
                    Text("Auto").tag(TranslationViewModel.autoCode)
                    ForEach(TargetLanguage.choices, id: \.code) { choice in
                        Text(choice.name).tag(choice.code)
                    }
                }
                .frame(maxWidth: 170)

                Spacer()

            }

            ScrollView {
                Text(model.output)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 110)
            .border(Color.secondary.opacity(0.3))

            HStack {
                statusView
                Spacer()
                Button("Copy") {
                    model.copyOutput()
                }
                .disabled(model.output.isEmpty)
                if showsQuit {
                    Button("Quit") {
                        model.quit()
                    }
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    @ViewBuilder
    private var statusView: some View {
        if let progress = model.downloadProgress {
            ProgressView(value: progress)
                .frame(width: 120)
        }
        if let status = model.status {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
