import Foundation
import llama

enum TranslatorError: LocalizedError {
    case loadFailed
    case modelFileInvalid
    case modelMissing
    case inputTooLong
    case decodeFailed
    case outputTruncated

    var errorDescription: String? {
        switch self {
        case .loadFailed: return "Could not load the model."
        case .modelFileInvalid: return "The model file is unreadable and was deleted. Try again to download it."
        case .modelMissing: return "The model was deleted. Try again to download it."
        case .inputTooLong: return "The text is too long."
        case .decodeFailed: return "Translation failed."
        case .outputTruncated: return "The translation was too long and was cut off."
        }
    }
}

/// Owns the llama.cpp model. Loads lazily, stays warm, unloads when idle.
actor Translator {
    /// One translator for the process, so app termination can free its model.
    static let shared = Translator()

    /// Initialised once per process, on first access.
    private static let backend: Void = llama_backend_init()

    private static let idleTimeout: Duration = .seconds(300)
    private static let contextSize: UInt32 = 4096
    private static let maxNewTokens = 1024
    private static let maxInputBytes = 4 * Int(contextSize)

    private var loadedPath: String?
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var stopTokens: Set<llama_token> = []
    private var idleTask: Task<Void, Never>?
    private var shuttingDown = false

    func translate(_ segments: [PromptSegment], modelPath: String) throws -> String {
        try Task.checkCancellation()
        if shuttingDown {
            throw CancellationError()
        }
        idleTask?.cancel()
        defer { scheduleUnload() }

        try loadIfNeeded(path: modelPath)
        return try generate(segments: segments)
    }

    /// Unloads the model and refuses further work, for app quit.
    func shutDown() {
        shuttingDown = true
        idleTask?.cancel()
        unload()
    }

    /// Deletes a model file, freeing it first if it is loaded. Both happen
    /// on the actor, so no translation can reload the file in between.
    /// Unlike shutDown, the translator keeps accepting work.
    func deleteModel(at path: String) throws {
        if loadedPath == path {
            unload()
        }
        try FileManager.default.removeItem(atPath: path)
    }

    private func scheduleUnload() {
        idleTask = Task {
            try? await Task.sleep(for: Self.idleTimeout)
            if Task.isCancelled {
                return
            }
            unload()
        }
    }

    private func loadIfNeeded(path: String) throws {
        if loadedPath == path {
            return
        }
        unload()

        // Deleted from Settings after this request got its path.
        if !FileManager.default.fileExists(atPath: path) {
            throw TranslatorError.modelMissing
        }
        Self.backend
        let modelParams = llama_model_default_params()
        guard let newModel = llama_model_load_from_file(path, modelParams) else {
            throw TranslatorError.modelFileInvalid
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = Self.contextSize
        contextParams.n_batch = Self.contextSize
        guard let newContext = llama_init_from_model(newModel, contextParams) else {
            llama_model_free(newModel)
            throw TranslatorError.loadFailed
        }

        let chainParams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(chainParams)
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())

        model = newModel
        context = newContext
        sampler = chain
        loadedPath = path

        let vocab = llama_model_get_vocab(newModel)
        stopTokens = Self.specialTokens(["<|plamo:tag|>", "<|plamo:bos|>"], vocab: vocab)
    }

    private func unload() {
        if let sampler {
            llama_sampler_free(sampler)
        }
        if let context {
            llama_free(context)
        }
        if let model {
            llama_model_free(model)
        }
        sampler = nil
        context = nil
        model = nil
        loadedPath = nil
    }

    private func generate(segments: [PromptSegment]) throws -> String {
        guard let model, let context, let sampler else {
            throw TranslatorError.loadFailed
        }
        let vocab = llama_model_get_vocab(model)

        let totalBytes = segments.reduce(0) { $0 + $1.text.utf8.count }
        if totalBytes > Self.maxInputBytes {
            throw TranslatorError.inputTooLong
        }

        var tokens = Self.tokenize(segments, vocab: vocab)
        if tokens.count + Self.maxNewTokens > Self.contextSize {
            throw TranslatorError.inputTooLong
        }

        llama_memory_clear(llama_get_memory(context), true)
        llama_sampler_reset(sampler)

        var output: [UInt8] = []
        var finished = false
        for _ in 0..<Self.maxNewTokens {
            if Task.isCancelled {
                throw CancellationError()
            }

            let decodeStatus = tokens.withUnsafeMutableBufferPointer { buffer in
                let batch = llama_batch_get_one(buffer.baseAddress, Int32(buffer.count))
                return llama_decode(context, batch)
            }
            guard decodeStatus == 0 else {
                throw TranslatorError.decodeFailed
            }

            let next = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, next) || stopTokens.contains(next) {
                finished = true
                break
            }
            output += Self.pieceBytes(for: next, vocab: vocab)
            tokens = [next]
        }

        if !finished {
            throw TranslatorError.outputTruncated
        }

        let text = String(decoding: output, as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Template pieces parse special tokens, user pieces never do. Only the
    /// first piece asks for the BOS token, so it is added exactly once.
    private static func tokenize(
        _ segments: [PromptSegment],
        vocab: OpaquePointer?
    ) -> [llama_token] {
        var tokens: [llama_token] = []
        for (index, segment) in segments.enumerated() {
            tokens += tokenize(
                segment.text,
                vocab: vocab,
                addSpecial: index == 0,
                parseSpecial: segment.isTemplate
            )
        }
        return tokens
    }

    private static func tokenize(
        _ text: String,
        vocab: OpaquePointer?,
        addSpecial: Bool,
        parseSpecial: Bool
    ) -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 16)
        var count = llama_tokenize(
            vocab,
            text,
            utf8Count,
            &tokens,
            Int32(tokens.count),
            addSpecial,
            parseSpecial
        )
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(
                vocab,
                text,
                utf8Count,
                &tokens,
                Int32(tokens.count),
                addSpecial,
                parseSpecial
            )
        }
        return Array(tokens.prefix(max(Int(count), 0)))
    }

    private static func specialTokens(
        _ names: [String],
        vocab: OpaquePointer?
    ) -> Set<llama_token> {
        var result: Set<llama_token> = []
        for name in names {
            let tokens = tokenize(name, vocab: vocab, addSpecial: false, parseSpecial: true)
            if tokens.count == 1 {
                result.insert(tokens[0])
            }
        }
        return result
    }

    private static func pieceBytes(for token: llama_token, vocab: OpaquePointer?) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 256)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        guard length > 0 else {
            return []
        }
        return buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
    }
}
