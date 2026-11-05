import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: TranslationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $model.sourceText)
                .font(.body)
                .frame(height: 110)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Picker("To", selection: $model.targetCode) {
                    Text("Auto").tag(TranslationViewModel.autoCode)
                    ForEach(TargetLanguage.choices, id: \.code) { choice in
                        Text(choice.name).tag(choice.code)
                    }
                }
                .frame(maxWidth: 170)

                Spacer()

                Picker("Model", selection: $model.modelSize) {
                    ForEach(ModelSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
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
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.output, forType: .string)
                }
                .disabled(model.output.isEmpty)
                Button("Quit") {
                    model.quit()
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
