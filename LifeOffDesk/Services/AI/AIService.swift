import CryptoKit
import Foundation
import LifeOffDeskCore
import UIKit

/// Owns the on-device model. Loads on demand for a planner request, unloads when a walk
/// starts or memory runs low, so inference never competes with tracking.
@MainActor
final class AIService: ObservableObject {
    static let modelFileName = "Qwen3-0.6B-Q4_0.gguf"
    /// From config/materials-lock.json (ggml-org/Qwen3-0.6B-GGUF @ a41486f).
    static let expectedSHA256 = "da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4"

    enum State: Equatable {
        case notLoaded, loading, ready, missing, failed(String)
    }

    @Published private(set) var state: State = .notLoaded
    @Published private(set) var loadInfo: LlamaLoadInfo?
    @Published private(set) var hashResult: String?
    private(set) var engine: LlamaEngine?
    private var memoryObserver: NSObjectProtocol?

    init() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unload() }
        }
    }

    /// Documents (copied via Finder file sharing) first, then the app bundle.
    static func modelURL() -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(modelFileName)
        if let documents, FileManager.default.fileExists(atPath: documents.path) { return documents }
        return Bundle.main.url(forResource: "Qwen3-0.6B-Q4_0", withExtension: "gguf")
    }

    func ensureLoaded() async -> LlamaEngine? {
        if let engine { return engine }
        guard let url = Self.modelURL() else {
            state = .missing
            return nil
        }
        state = .loading
        do {
            let engine = try await Task.detached(priority: .userInitiated) {
                try LlamaEngine.load(path: url.path)
            }.value
            self.engine = engine
            loadInfo = engine.info
            state = .ready
            return engine
        } catch {
            state = .failed("\(error)")
            return nil
        }
    }

    func unload() {
        engine = nil
        if state == .ready || state == .loading { state = .notLoaded }
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
