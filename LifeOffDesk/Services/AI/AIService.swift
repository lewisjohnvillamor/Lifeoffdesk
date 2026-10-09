import CryptoKit
import os
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
    /// Exact size from the materials lock: a cheap check on every load (the hash takes ~seconds).
    static let expectedBytes: Int64 = 1_282_439_264
    /// Weights + KV cache (2048 ctx) + compute buffers need headroom beyond the file size.
    static let loadHeadroomBytes: UInt64 = 700 * 1024 * 1024

    enum State: Equatable {
        case notLoaded, loading, ready, missing, failed(String)
    }

    @Published private(set) var state: State = .notLoaded
    @Published private(set) var loadInfo: LlamaLoadInfo?
    @Published private(set) var hashResult: String?
    /// Why the last AI request did not produce a result, shown instead of failing silently.
    @Published private(set) var lastProblem: String?
    /// Set when running work was cancelled (walk start, low memory, erase); cleared on the next run.
    @Published private(set) var lastInterruption: String?
    private var coordinator: InferenceCoordinator!
    private var memoryObserver: NSObjectProtocol?

    private struct ModelMissing: Error, CustomStringConvertible { var description: String { "model missing" } }

    init() {
        coordinator = InferenceCoordinator(loader: {
            #if targetEnvironment(simulator)
            throw InferenceError.loadFailed("AI is unavailable in Simulator. Run on a physical iPhone to use on-device AI.")
            #else
            guard let url = await AIService.modelURL() else { throw ModelMissing() }
            try AIService.preflight(url)
            return try await Task.detached(priority: .userInitiated) { try LlamaEngine.load(path: url.path) }.value
            #endif
        }, onEvent: { [weak self] event in
            await self?.apply(event)
        })
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unload(reason: "low memory warning") }
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
        case let .failed(message):
            state = message == "model missing" ? .missing : .failed(message)
            lastProblem = message == "model missing" ? "Model file not found in the app or Documents." : message
        case .unloaded: state = .notLoaded
        }
    }

    /// Refuses a wrong/incomplete model file or a load likely to exceed this app's memory limit,
    /// with a readable reason, instead of loading the wrong artifact or being killed by iOS.
    nonisolated static func preflight(_ url: URL) throws {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? -1
        guard size == expectedBytes else {
            throw InferenceError.loadFailed("Model file is \(size) bytes, expected \(expectedBytes) (wrong or incomplete copy at \(url.lastPathComponent)). Remove it from Documents or rebuild.")
        }
        #if !targetEnvironment(simulator)
        let available = os_proc_available_memory()
        let needed = UInt64(expectedBytes) + loadHeadroomBytes
        if available > 0 && UInt64(available) < needed {
            throw InferenceError.loadFailed("Not enough free memory to load the model (\(available / 1_048_576) MB available, about \(needed / 1_048_576) MB needed). Close other apps and try again.")
        }
        #endif
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
        lastInterruption = nil
        do {
            return try await coordinator.perform(work)
        } catch InferenceError.stale {
            throw InferenceError.stale
        } catch InferenceError.cancelled {
            throw InferenceError.cancelled
        } catch {
            lastProblem = "\(error)"
            throw error
        }
    }

    /// Readable reason for an interrupted request.
    var interruptionMessage: String {
        "Na-interrupt ang AI (\(lastInterruption ?? "na-unload ang model")). Subukan ulit."
    }

    /// Loads the model without generating (diagnostics: check file, memory and load time).
    func preload() async {
        _ = try? await coordinator.perform { _ in true }
    }

    /// Cancels pending AI work and releases the model once native work stops (walk start,
    /// memory warning, erase). Never blocks the caller.
    func unload(reason: String = "na-unload ang model") {
        lastInterruption = reason
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
