import SwiftUI

@MainActor
final class TranslationViewModel: ObservableObject {
    static let autoCode = "auto"
    private static let debounce: Duration = .milliseconds(300)

    @Published var sourceText = "" {
        didSet { scheduleTranslation() }
    }
    @Published var targetCode = TranslationViewModel.autoCode {
        didSet { scheduleTranslation() }
    }
    @Published var modelSize: ModelSize {
        didSet {
            UserDefaults.standard.set(modelSize.rawValue, forKey: "modelSize")
            scheduleTranslation()
        }
    }
    @Published var output = ""
    @Published var status: String?
    @Published var downloadProgress: Double?

    private let translator = Translator()
    private var task: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.string(forKey: "modelSize") ?? ""
        modelSize = ModelSize(rawValue: saved) ?? .small
    }

    /// Frees the model first: ggml's Metal teardown asserts if the process
    /// exits while a model is still loaded.
    func quit() {
        Task {
            await translator.unload()
            NSApplication.shared.terminate(nil)
        }
    }

    private func scheduleTranslation() {
        task?.cancel()
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            output = ""
            status = nil
            return
        }
        task = Task { await run(text: text) }
    }

    private func run(text: String) async {
        try? await Task.sleep(for: Self.debounce)
        if Task.isCancelled {
            return
        }

        do {
            let modelPath = try await ensureModel()
            let target = resolvedTarget(for: text)
            let prompt = PFML3Prompt(text: text, target: target).build()
            status = "Translating..."
            let result = try await translator.translate(prompt, modelPath: modelPath)
            if Task.isCancelled {
                return
            }
            output = result
            status = nil
        } catch is CancellationError {
            return
        } catch {
            status = error.localizedDescription
        }
    }

    private func resolvedTarget(for text: String) -> String {
        if targetCode == Self.autoCode {
            return TargetLanguage.auto(for: text)
        }
        return targetCode
    }

    private func ensureModel() async throws -> String {
        let model = modelSize
        if ModelStore.isDownloaded(model) {
            return ModelStore.localURL(for: model).path
        }

        status = "Downloading \(model.fileName)..."
        downloadProgress = 0
        defer { downloadProgress = nil }
        let url = try await ModelStore.download(model) { fraction in
            Task { @MainActor in
                self.downloadProgress = fraction
            }
        }
        return url.path
    }
}
