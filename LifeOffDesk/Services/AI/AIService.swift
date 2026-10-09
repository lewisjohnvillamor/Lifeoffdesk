import CryptoKit
import Foundation
import LifeOffDeskCore
import UIKit

/// Owns the on-device model through one `InferenceCoordinator`: single-flight loading, one
/// generation at a time, cancellation, and an epoch that unload/erase bump so late results are
/// dropped. Loads on demand; unloads when a walk starts or memory runs low.
@MainActor
final class AIService: ObservableObject {
    static let modelFileName = "Qwen3-1.7B-Q4_K_M.gguf"
    /// Founder-selected model, from config/materials-lock.json (group model-large).
    static let expectedSHA256 = "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"

    enum State: Equatable {
        case notLoaded, loading, ready, missing, failed(String)
    }

    @Published private(set) var state: State = .notLoaded
    @Published private(set) var loadInfo: LlamaLoadInfo?
    @Published private(set) var hashResult: String?
    private var coordinator: InferenceCoordinator!
    private var memoryObserver: NSObjectProtocol?

    private struct ModelMissing: Error, CustomStringConvertible { var description: String { "model missing" } }

    init() {
        coordinator = InferenceCoordinator(loader: {
            #if targetEnvironment(simulator)
            throw InferenceError.loadFailed("AI is unavailable in Simulator. Run on a physical iPhone to use on-device AI.")
            #else
            guard let url = await AIService.modelURL() else { throw ModelMissing() }
            return try await Task.detached(priority: .userInitiated) { try LlamaEngine.load(path: url.path) }.value
            #endif
        }, onEvent: { [weak self] event in
            await self?.apply(event)
        })
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unload() }
        }
    }

    private func apply(_ event: InferenceCoordinator.LoadEvent) {
        switch event {
        case .loading: state = .loading
        case let .loaded(engine):
            state = .ready
            #if !targetEnvironment(simulator)
            if let llama = engine as? LlamaEngine { loadInfo = llama.info }
            #endif
        case let .failed(message): state = message == "model missing" ? .missing : .failed(message)
        case .unloaded: state = .notLoaded
        }
    }

    /// Documents first, then the app bundle. Both must be the exact selected file.
    static func modelURL() -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(modelFileName)
        if let documents, FileManager.default.fileExists(atPath: documents.path) { return documents }
        return Bundle.main.url(forResource: "Qwen3-1.7B-Q4_K_M", withExtension: "gguf")
    }

    /// Runs one inference task after any earlier ones, loading the model if needed.
    /// Throws `InferenceError.stale` if the model was unloaded or data erased meanwhile.
    func run<T: Sendable>(_ work: @escaping @Sendable (any IntentEngine) async throws -> T) async throws -> T {
        try await coordinator.perform(work)
    }

    /// Loads the model without generating (diagnostics: check file, memory and load time).
    func preload() async {
        _ = try? await coordinator.perform { _ in true }
    }

    /// Cancels pending AI work and releases the model once native work stops (walk start,
    /// memory warning, erase). Never blocks the caller.
    func unload() {
        let coordinator = self.coordinator!
        Task { await coordinator.unload() }
        if state == .loading { state = .notLoaded }
    }

    func verifyModelHash() async {
        guard let url = Self.modelURL() else { hashResult = "Model file not found"; return }
        hashResult = "Hashing…"
        let expected = Self.expectedSHA256
        let result = await Task.detached(priority: .utility) { () -> String in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return "Could not open model file" }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return hex == expected ? "SHA-256 matches pinned artifact (\(hex.prefix(12))…)"
                                                     : "SHA-256 MISMATCH: \(hex)"
        }.value
        hashResult = result
    }
}
