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
            ShortcutRecorder()
            accessibilityRow
            Text(
                "Translates the selected text in a floating popup. Without "
                    + "Accessibility access, copy the text with ⌘C first. You "
                    + "can also right-click selected text and choose "
                    + "Services → Translate with Konnyaku."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Re-checked every few seconds: macOS doesn't announce the change.
    private var accessibilityRow: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if SelectionReader.isTrusted {
                LabeledContent("Accessibility") {
                    Text("Allowed")
                        .foregroundStyle(.secondary)
                }
            } else {
                notAllowedRow
            }
        }
    }

    private var notAllowedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Accessibility") {
                HStack {
                    Text("Not allowed")
                        .foregroundStyle(.secondary)
                    Button("Open System Settings") {
                        SelectionReader.openAccessibilitySettings()
                    }
                }
            }
            // After an update, System Settings can still show Konnyaku
            // switched on: the ad-hoc signature changed, so macOS sees a
            // different app. Only removing and re-adding it fixes that.
            Text(
                "Konnyaku can't read selected text. In System Settings → "
                    + "Privacy & Security → Accessibility, allow Konnyaku. If "
                    + "it's already on, remove it with − and add it again."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
            // "Built with PLaMo" attribution in the spirit of Article 4 of the PLaMo
            // Community License (Konnyaku does not redistribute the model).
            Text("Built with PLaMo")
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
