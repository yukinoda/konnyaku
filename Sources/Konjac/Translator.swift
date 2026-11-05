import Foundation
import llama

enum TranslatorError: LocalizedError {
    case loadFailed
    case inputTooLong
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed: return "Could not load the model."
        case .inputTooLong: return "The text is too long."
        case .decodeFailed: return "Translation failed."
        }
    }
}

/// Owns the llama.cpp model. Loads lazily, stays warm, unloads when idle.
actor Translator {
    private static let idleTimeout: Duration = .seconds(300)
    private static let contextSize: UInt32 = 4096
    private static let maxNewTokens = 1024

    private var loadedPath: String?
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var stopTokens: Set<llama_token> = []
    private var idleTask: Task<Void, Never>?

    func translate(_ prompt: String, modelPath: String) throws -> String {
        idleTask?.cancel()
        defer { scheduleUnload() }

        try loadIfNeeded(path: modelPath)
        return try generate(prompt: prompt)
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

        llama_backend_init()
        let modelParams = llama_model_default_params()
        guard let newModel = llama_model_load_from_file(path, modelParams) else {
            throw TranslatorError.loadFailed
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

    func unload() {
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

    private func generate(prompt: String) throws -> String {
        guard let model, let context, let sampler else {
            throw TranslatorError.loadFailed
        }
        let vocab = llama_model_get_vocab(model)

        var tokens = Self.tokenize(prompt, vocab: vocab, addSpecial: true)
        if tokens.count + Self.maxNewTokens > Self.contextSize {
            throw TranslatorError.inputTooLong
        }

        llama_memory_clear(llama_get_memory(context), true)
        llama_sampler_reset(sampler)

        var output: [UInt8] = []
        for _ in 0..<Self.maxNewTokens {
            if Task.isCancelled {
                throw CancellationError()
            }

            let batch = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_batch_get_one(buffer.baseAddress, Int32(buffer.count))
            }
            guard llama_decode(context, batch) == 0 else {
                throw TranslatorError.decodeFailed
            }

            let next = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, next) || stopTokens.contains(next) {
                break
            }
            output += Self.pieceBytes(for: next, vocab: vocab)
            tokens = [next]
        }

        let text = String(decoding: output, as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(
        _ text: String,
        vocab: OpaquePointer?,
        addSpecial: Bool
    ) -> [llama_token] {
        let utf8Count = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: utf8Count + 16)
        let count = llama_tokenize(
            vocab,
            text,
            Int32(utf8Count),
            &tokens,
            Int32(tokens.count),
            addSpecial,
            true
        )
        return Array(tokens.prefix(max(Int(count), 0)))
    }

    private static func specialTokens(
        _ names: [String],
        vocab: OpaquePointer?
    ) -> Set<llama_token> {
        var result: Set<llama_token> = []
        for name in names {
            let tokens = tokenize(name, vocab: vocab, addSpecial: false)
            if tokens.count == 1 {
                result.insert(tokens[0])
            }
        }
        return result
    }

    private static func pieceBytes(for token: llama_token, vocab: OpaquePointer?) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        guard length > 0 else {
            return []
        }
        return buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
    }
}
