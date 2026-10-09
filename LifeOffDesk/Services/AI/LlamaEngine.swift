import Foundation
import LifeOffDeskCore
#if !targetEnvironment(simulator)
import llama
#endif

// On-device inference through the pinned llama.cpp b11429 C API (llama.xcframework on iOS).
// The same file is compiled by Tools/PlannerEval on a development machine for diagnostics;
// those runs are never iPhone evidence.

enum LlamaEngineError: Error, CustomStringConvertible {
    case modelMissing(String)
    case loadFailed(String)
    case contextFailed
    case notChatML
    case tokenizeFailed
    case promptTooLong(tokens: Int, limit: Int)
    case grammarFailed
    case decodeFailed(Int32)
    case cancelled

    var description: String {
        switch self {
        case let .modelMissing(path): return "Model file not found at \(path)"
        case let .loadFailed(path): return "llama.cpp could not load \(path)"
        case .contextFailed: return "Could not create an inference context"
        case .notChatML: return "Model chat template is not ChatML; prompt format would be wrong"
        case .tokenizeFailed: return "Tokenization failed"
        case let .promptTooLong(tokens, limit): return "Prompt needs \(tokens) tokens; context allows \(limit)"
        case .grammarFailed: return "Output grammar failed to parse"
        case let .decodeFailed(code): return "llama_decode failed (\(code))"
        case .cancelled: return "Cancelled"
        }
    }
}

struct LlamaLoadInfo: Sendable {
    var modelPath: String
    var modelBytes: Int64
    var loadSeconds: Double
    var contextLength: Int
    var threads: Int
    var gpuLayers: Int
    var runtimeVersion: String
}

struct LlamaGenerationStats: Sendable {
    var promptTokens: Int
    /// Prompt tokens already in the KV cache from the previous request (same system prompt and examples).
    var reusedTokens: Int = 0
    var generatedTokens: Int
    var seconds: Double
}

#if targetEnvironment(simulator)
/// The pinned runtime has no simulator slice. Never substitute canned AI output.
actor LlamaEngine: IntentEngine {
    let info: LlamaLoadInfo

    private init(info: LlamaLoadInfo) { self.info = info }

    static func load(path: String, contextLength: Int = 2048, gpuLayers: Int? = nil) throws -> LlamaEngine {
        throw LlamaEngineError.loadFailed("AI is unavailable in Simulator. Run on a physical iPhone to use the pinned on-device runtime.")
    }

    func complete(prompt: String, grammar: String?, maxTokens: Int) async throws -> String {
        throw LlamaEngineError.contextFailed
    }
}
#else
actor LlamaEngine: IntentEngine {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let batchSize: Int
    let info: LlamaLoadInfo
    private(set) var lastStats: LlamaGenerationStats?
    /// Tokens currently held in the KV cache (prompt plus decoded output of the last request).
    /// A new prompt sharing a prefix (the long system prompt and few-shot examples) only decodes the rest.
    private var cached: [llama_token] = []

    private static let backendOnce: Void = { llama_backend_init() }()

    /// Loads synchronously; call from a background task, never the main thread.
    static func load(path: String, contextLength: Int = 2048, gpuLayers: Int? = nil) throws -> LlamaEngine {
        _ = backendOnce
        guard FileManager.default.fileExists(atPath: path) else { throw LlamaEngineError.modelMissing(path) }
        let start = Date()
        var modelParams = llama_model_default_params()
        if let gpuLayers { modelParams.n_gpu_layers = Int32(gpuLayers) }
        guard let model = llama_model_load_from_file(path, modelParams) else { throw LlamaEngineError.loadFailed(path) }

        guard let template = llama_model_chat_template(model, nil), String(cString: template).contains("<|im_start|>") else {
            llama_model_free(model)
            throw LlamaEngineError.notChatML
        }

        let threads = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        let batchSize = 512
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextLength)
        contextParams.n_batch = UInt32(batchSize)
        contextParams.n_ubatch = UInt32(batchSize)
        contextParams.n_threads = Int32(threads)
        contextParams.n_threads_batch = Int32(threads)
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LlamaEngineError.contextFailed
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let info = LlamaLoadInfo(modelPath: path,
                                 modelBytes: (attributes?[.size] as? NSNumber)?.int64Value ?? -1,
                                 loadSeconds: Date().timeIntervalSince(start),
                                 contextLength: Int(llama_n_ctx(context)),
                                 threads: threads,
                                 gpuLayers: Int(modelParams.n_gpu_layers),
                                 runtimeVersion: String(cString: llama_version()))
        return LlamaEngine(model: model, context: context, vocab: llama_model_get_vocab(model),
                           batchSize: batchSize, info: info)
    }

    private init(model: OpaquePointer, context: OpaquePointer, vocab: OpaquePointer, batchSize: Int, info: LlamaLoadInfo) {
        self.model = model
        self.context = context
        self.vocab = vocab
        self.batchSize = batchSize
        self.info = info
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    func complete(prompt: String, grammar: String?, maxTokens: Int) async throws -> String {
        let start = Date()
        let tokens = try tokenize(prompt)
        let limit = Int(llama_n_ctx(context))
        guard tokens.count + maxTokens <= limit else {
            throw LlamaEngineError.promptTooLong(tokens: tokens.count + maxTokens, limit: limit)
        }

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        if let grammar {
            guard let constrained = llama_sampler_init_grammar(vocab, grammar, "root") else {
                throw LlamaEngineError.grammarFailed
            }
            llama_sampler_chain_add(sampler, constrained)
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        // Reuse the shared prefix; at least the last prompt token is decoded so fresh logits exist.
        var reuse = zip(cached, tokens).prefix { $0 == $1 }.count
        reuse = min(reuse, tokens.count - 1)
        let memory = llama_get_memory(context)
        if reuse == 0 || !llama_memory_seq_rm(memory, 0, Int32(reuse), -1) {
            llama_memory_clear(memory, true)
            reuse = 0
        }
        cached = Array(tokens.prefix(reuse))
        var pending = Array(tokens.dropFirst(reuse))
        var offset = 0
        while offset < pending.count {
            let count = min(batchSize, pending.count - offset)
            let status = pending.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + offset, Int32(count)))
            }
            guard status == 0 else { cached = []; llama_memory_clear(memory, true); throw LlamaEngineError.decodeFailed(status) }
            offset += count
        }
        cached = tokens
        let reusedTokens = reuse

        var output: [UInt8] = []
        var generated = 0
        while generated < maxTokens {
            if Task.isCancelled { throw LlamaEngineError.cancelled }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            output += piece(token)
            generated += 1
            let status = llama_decode(context, llama_batch_get_one(&token, 1))
            guard status == 0 else { cached = []; llama_memory_clear(memory, true); throw LlamaEngineError.decodeFailed(status) }
            cached.append(token)
            await Task.yield()
        }
        lastStats = LlamaGenerationStats(promptTokens: tokens.count, reusedTokens: reusedTokens,
                                         generatedTokens: generated, seconds: Date().timeIntervalSince(start))
        return String(decoding: output, as: UTF8.self)
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 8)
        var count = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), true, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), true, true)
        }
        guard count >= 0 else { throw LlamaEngineError.tokenizeFailed }
        return Array(tokens.prefix(Int(count)))
    }

    private func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(0, length))).map { UInt8(bitPattern: $0) }
    }
}
#endif
