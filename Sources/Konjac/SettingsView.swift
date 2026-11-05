import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: TranslationViewModel
    @State private var modelPendingDelete: ModelSize?
    @State private var deleteError: String?

    private static let licenseURL = URL(
        string: "https://plamo.preferredai.jp/info/plamo-community-license-en"
    )!

    var body: some View {
        SwiftUI.Form {
            shortcutSection
            modelSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Delete this model?",
            isPresented: isConfirmingDelete,
            presenting: modelPendingDelete
        ) { size in
            Button("Delete", role: .destructive) {
                delete(size)
            }
        } message: { size in
            Text("\(size.label) will be downloaded again the next time you translate with it.")
        }
    }

    private var shortcutSection: some View {
        Section("Shortcut") {
            LabeledContent("Translate clipboard", value: "⌃⌥T")
            Text(
                "Translates the text you copied, in a floating popup. "
                    + "You can also right-click selected text and choose "
                    + "Services → Translate with konjac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        Section("Model") {
            Picker("Model", selection: $model.modelSize) {
                ForEach(ModelSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }

            ForEach(ModelSize.allCases) { size in
                modelRow(size)
            }

            if let deleteError {
                Text(deleteError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Show in Finder") {
                showModelsFolder()
            }
        }
    }

    private func modelRow(_ size: ModelSize) -> some View {
        LabeledContent(size.rawValue.uppercased()) {
            HStack {
                Text(diskStatus(of: size))
                    .foregroundStyle(.secondary)
                if ModelStore.isDownloaded(size) {
                    Button("Delete", role: .destructive) {
                        deleteError = nil
                        modelPendingDelete = size
                    }
                    .disabled(model.isDownloading(size))
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            Link("PLaMo Community License", destination: Self.licenseURL)
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { modelPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    modelPendingDelete = nil
                }
            }
        )
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "development build"
    }

    private func diskStatus(of size: ModelSize) -> String {
        if model.isDownloading(size) {
            return "Downloading..."
        }
        if !ModelStore.isDownloaded(size) {
            return "Not downloaded"
        }
        let path = ModelStore.localURL(for: size).path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let bytes = attributes?[.size] as? Int64 ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func delete(_ size: ModelSize) {
        let path = ModelStore.localURL(for: size).path
        Task {
            do {
                try await Translator.shared.deleteModel(at: path)
                deleteError = nil
            } catch {
                deleteError = "Could not delete: \(error.localizedDescription)"
            }
            // The disk state is not observable, so nudge the view to re-read it.
            model.objectWillChange.send()
        }
    }

    private func showModelsFolder() {
        let folder = ModelStore.directory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
