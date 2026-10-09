import Foundation

public enum InferenceError: Error, Equatable, CustomStringConvertible {
    /// The model was unloaded or erased after this request started; its result is discarded.
    case stale
    case cancelled
    case loadFailed(String)

    public var description: String {
        switch self {
        case .stale: return "The request was superseded (model unloaded or data erased)"
        case .cancelled: return "Cancelled"
        case let .loadFailed(message): return message
        }
    }
}

/// The single owner of on-device inference. Every task (planner, history search, recap
/// narration) goes through `perform`, which:
/// - loads the model once even if several requests arrive together (single-flight);
/// - runs one task at a time, so no two generations share the native context;
/// - tags each task with an ID and the current generation epoch. `unload()` (walk start,
///   memory warning) and erase bump the epoch, cancel running work and make any late result
///   throw `.stale` instead of updating state.
/// The native engine is released when the last running task drops its reference.
public actor InferenceCoordinator {
    public enum LoadEvent: Sendable {
        case loading
        case loaded(any IntentEngine)
        case failed(String)
        case unloaded
    }

    public typealias Loader = @Sendable () async throws -> any IntentEngine

    private let loader: Loader
    private let onEvent: @Sendable (LoadEvent) async -> Void
    private var engine: (any IntentEngine)?
    private var loading: (epoch: Int, task: Task<any IntentEngine, Error>)?
    private var tail: Task<Void, Never>?
    private var nextID = 0
    private var cancellers: [Int: @Sendable () -> Void] = [:]
    public private(set) var epoch = 0

    public init(loader: @escaping Loader, onEvent: @escaping @Sendable (LoadEvent) async -> Void = { _ in }) {
        self.loader = loader
        self.onEvent = onEvent
    }

    public var isLoaded: Bool { engine != nil }
    /// Tasks queued or running.
    public var activeTaskCount: Int { cancellers.count }

    /// Runs `work` with the loaded engine once every earlier task has finished.
    public func perform<T: Sendable>(_ work: @escaping @Sendable (any IntentEngine) async throws -> T) async throws -> T {
        let startEpoch = epoch
        nextID += 1
        let id = nextID
        let previous = tail
        let task = Task { () async throws -> T in
            await previous?.value
            try await self.check(startEpoch)
            let engine = try await self.loadedEngine(for: startEpoch)
            let result = try await work(engine)
            try await self.check(startEpoch)
            return result
        }
        tail = Task { _ = try? await task.value }
        cancellers[id] = { task.cancel() }
        defer { finish(id) }
        return try await withTaskCancellationHandler {
            do { return try await task.value } catch is CancellationError { throw InferenceError.cancelled }
        } onCancel: {
            task.cancel()
        }
    }

    private func finish(_ id: Int) {
        cancellers[id] = nil
    }

    private func check(_ startEpoch: Int) throws {
        if Task.isCancelled { throw InferenceError.cancelled }
        guard epoch == startEpoch else { throw InferenceError.stale }
    }

    private func loadedEngine(for startEpoch: Int) async throws -> any IntentEngine {
        if let engine { return engine }
        let task: Task<any IntentEngine, Error>
        if let loading, loading.epoch == startEpoch {
            task = loading.task
        } else {
            let loader = self.loader
            task = Task { try await loader() }
            loading = (startEpoch, task)
            await onEvent(.loading)
        }
        let loaded: any IntentEngine
        do {
            loaded = try await task.value
        } catch {
            // A failed load is never cached: the next request tries again.
            if loading?.epoch == startEpoch { loading = nil }
            guard epoch == startEpoch else { throw InferenceError.stale }
            let message = (error as? InferenceError).map { if case let .loadFailed(m) = $0 { return m }; return "\($0)" } ?? "\(error)"
            await onEvent(.failed(message))
            throw InferenceError.loadFailed(message)
        }
        if loading?.epoch == startEpoch { loading = nil }
        // An unload during loading invalidates this engine: never install it.
        guard epoch == startEpoch else { throw InferenceError.stale }
        if engine == nil {
            engine = loaded
            await onEvent(.loaded(loaded))
        }
        return engine ?? loaded
    }

    /// Cancels queued and running work, invalidates late results and drops the engine.
    /// Native memory is freed once the running generation (if any) stops at its next token.
    public func unload() async {
        epoch += 1
        for cancel in cancellers.values { cancel() }
        loading?.task.cancel()
        loading = nil
        let hadEngine = engine != nil
        engine = nil
        if hadEngine { await onEvent(.unloaded) }
    }
}
