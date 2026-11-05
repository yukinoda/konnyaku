import SwiftUI

@MainActor
final class TranslationViewModel: ObservableObject {
    /// Shared by the floating panel and Settings.
    static let shared = TranslationViewModel()
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
    /// True while a translation for the current text and target is pending,
    /// so `output` may still belong to the previous request.
    @Published private(set) var isBusy = false
    @Published private var downloadProgresses: [ModelSize: Double] = [:]

    /// True when the most recent translation ended in an error (not a
    /// progress message such as "Verifying...").
    private(set) var lastRunFailed = false

    /// The clipboard change count right after konjac's own Copy, so a later
    /// ⌃⌥T doesn't mistake it for newly copied text.
    private(set) var ownCopyChangeCount = -1

    /// Progress of the selected model's download, if one is running.
    var downloadProgress: Double? {
        downloadProgresses[modelSize]
    }

    func isDownloading(_ model: ModelSize) -> Bool {
        downloadTasks[model] != nil
    }

    private let translator = Translator.shared
    private var task: Task<Void, Never>?
    /// One long-lived download per model. Translation runs only await it, so
    /// cancelling a translation never cancels the download.
    private var downloadTasks: [ModelSize: Task<String, Error>] = [:]

    init() {
        let saved = UserDefaults.standard.string(forKey: "modelSize") ?? ""
        modelSize = ModelSize(rawValue: saved) ?? .small
    }

    /// The app delegate frees the model before the process exits.
    func quit() {
        task?.cancel()
        NSApplication.shared.terminate(nil)
    }

    func copyOutput() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        ownCopyChangeCount = pasteboard.changeCount
    }

    /// Translates the current text again, for example after an error.
    func retranslate() {
        scheduleTranslation()
    }

    private func scheduleTranslation() {
        task?.cancel()
        lastRunFailed = false
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            output = ""
            status = nil
            isBusy = false
            return
        }
        isBusy = true
        // Drop the previous run's error so it doesn't sit next to progress.
        status = nil
        task = Task {
            await run(text: text)
        }
    }

    private func run(text: String) async {
        try? await Task.sleep(for: Self.debounce)
        if Task.isCancelled {
            return
        }

        do {
            let modelPath = try await ensureModel()
            try Task.checkCancellation()
            let target = resolvedTarget(for: text)
            let segments = PFML3Prompt(text: text, target: target).segments()
            status = "Translating..."
            let result = try await translate(segments, modelPath: modelPath)
            if Task.isCancelled {
                return
            }
            output = result
            status = nil
            isBusy = false
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled {
                return
            }
            output = ""
            status = error.localizedDescription
            lastRunFailed = true
            isBusy = false
        }
    }

    /// A model file the GGUF loader rejects is corrupt, so delete it and let
    /// the next attempt download it again. Context failures such as low memory
    /// keep the verified file.
    private func translate(_ segments: [PromptSegment], modelPath: String) async throws -> String {
        do {
            return try await translator.translate(segments, modelPath: modelPath)
        } catch TranslatorError.modelFileInvalid {
            try? FileManager.default.removeItem(atPath: modelPath)
            throw TranslatorError.modelFileInvalid
        } catch TranslatorError.modelMissing {
            // The model was deleted while this request waited: download it
            // again and retry once. Not if the request was dropped meanwhile.
            try Task.checkCancellation()
            let newPath = try await ensureModel()
            try Task.checkCancellation()
            status = "Translating..."
            return try await translator.translate(segments, modelPath: newPath)
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

        downloadProgresses[model] = 0
        let newTask = Task {
            defer { finishDownload(of: model) }
            let url = try await ModelStore.download(
                model,
                progress: { fraction in
                    Task { @MainActor in
                        self.reportProgress(fraction, for: model)
                    }
                },
                onVerifying: {
                    Task { @MainActor in
                        self.reportVerifying(model)
                    }
                }
            )
            return url.path
        }
        downloadTasks[model] = newTask
        return newTask
    }

    private func finishDownload(of model: ModelSize) {
        downloadTasks[model] = nil
        downloadProgresses[model] = nil
    }

    /// Only the selected model's download owns the status line.
    private func reportVerifying(_ model: ModelSize) {
        if downloadTasks[model] == nil || model != modelSize {
            return
        }
        let hasInput = !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasInput {
            status = "Verifying..."
        }
    }

    /// Ignores updates that arrive after the download finished.
    private func reportProgress(_ fraction: Double, for model: ModelSize) {
        if downloadTasks[model] == nil {
            return
        }
        downloadProgresses[model] = fraction
    }
}
