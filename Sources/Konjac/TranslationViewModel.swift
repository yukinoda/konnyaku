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
    /// One long-lived download per model. Translation runs only await it, so
    /// cancelling a translation never cancels the download.
    private var downloadTasks: [ModelSize: Task<String, Error>] = [:]

    init() {
        let saved = UserDefaults.standard.string(forKey: "modelSize") ?? ""
        modelSize = ModelSize(rawValue: saved) ?? .small
    }

    /// Frees the model first: ggml's Metal teardown asserts if the process
    /// exits while a model is still loaded.
    func quit() {
        task?.cancel()
        Task {
            await translator.shutDown()
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
            let segments = PFML3Prompt(text: text, target: target).segments()
            status = "Translating..."
            let result = try await translator.translate(segments, modelPath: modelPath)
            if Task.isCancelled {
                return
            }
            output = result
            status = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled {
                return
            }
            output = ""
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
        return try await download(model).value
    }

    private func download(_ model: ModelSize) -> Task<String, Error> {
        if let existing = downloadTasks[model] {
            return existing
        }

        downloadProgress = 0
        let newTask = Task {
            defer { finishDownload(of: model) }
            let url = try await ModelStore.download(model) { fraction in
                Task { @MainActor in
                    self.reportProgress(fraction, for: model)
                }
            }
            return url.path
        }
        downloadTasks[model] = newTask
        return newTask
    }

    private func finishDownload(of model: ModelSize) {
        downloadTasks[model] = nil
        downloadProgress = nil
    }

    /// Ignores updates that arrive after the download finished.
    private func reportProgress(_ fraction: Double, for model: ModelSize) {
        if downloadTasks[model] == nil {
            return
        }
        downloadProgress = fraction
    }
}
