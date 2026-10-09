import XCTest
@testable import LifeOffDeskCore

/// Fake engine: records overlap and can be slow, so serialization and cancellation are observable.
private actor Probe {
    var loads = 0
    var active = 0
    var maxActive = 0
    func load() { loads += 1 }
    func enter() { active += 1; maxActive = max(maxActive, active) }
    func leave() { active -= 1 }
}

private struct SlowEngine: IntentEngine {
    let probe: Probe
    let steps: Int
    func complete(prompt: String, grammar: String?, maxTokens: Int) async throws -> String {
        await probe.enter()
        defer { Task { await probe.leave() } }
        for _ in 0..<steps {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        return prompt
    }
}

final class InferenceCoordinatorTests: XCTestCase {
    private func coordinator(_ probe: Probe, steps: Int = 5, loadDelay: UInt64 = 20_000_000) -> InferenceCoordinator {
        InferenceCoordinator(loader: {
            await probe.load()
            try await Task.sleep(nanoseconds: loadDelay)
            return SlowEngine(probe: probe, steps: steps)
        })
    }

    func testConcurrentRequestsLoadOnceAndNeverOverlap() async throws {
        let probe = Probe()
        let ai = coordinator(probe)
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<6 {
                group.addTask { try await ai.perform { try await $0.complete(prompt: "p\(i)", grammar: nil, maxTokens: 1) } }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }
        XCTAssertEqual(Set(results), Set((0..<6).map { "p\($0)" }))
        let loads = await probe.loads
        let maxActive = await probe.maxActive
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(maxActive, 1)
    }

    func testUnloadDuringGenerationDiscardsTheLateResult() async throws {
        let probe = Probe()
        let ai = coordinator(probe, steps: 200)
        let request = Task { try await ai.perform { try await $0.complete(prompt: "late", grammar: nil, maxTokens: 1) } }
        try await Task.sleep(nanoseconds: 60_000_000)
        await ai.unload()
        do {
            _ = try await request.value
            XCTFail("a superseded generation must not return a result")
        } catch let error as InferenceError {
            XCTAssertTrue([.stale, .cancelled].contains(error), "\(error)")
        }
        let loaded = await ai.isLoaded
        XCTAssertFalse(loaded)
    }

    func testUnloadDuringLoadNeverInstallsTheStaleEngine() async throws {
        let probe = Probe()
        let ai = coordinator(probe, loadDelay: 80_000_000)
        let request = Task { try await ai.perform { try await $0.complete(prompt: "x", grammar: nil, maxTokens: 1) } }
        try await Task.sleep(nanoseconds: 20_000_000)
        await ai.unload()
        _ = try? await request.value
        let loaded = await ai.isLoaded
        XCTAssertFalse(loaded)
        // A new request after unload loads again and succeeds.
        let fresh = try await ai.perform { try await $0.complete(prompt: "fresh", grammar: nil, maxTokens: 1) }
        XCTAssertEqual(fresh, "fresh")
    }

    func testCallerCancellationStopsOnlyThatTask() async throws {
        let probe = Probe()
        let ai = coordinator(probe, steps: 100)
        let cancelled = Task { try await ai.perform { try await $0.complete(prompt: "a", grammar: nil, maxTokens: 1) } }
        let kept = Task { try await ai.perform { try await $0.complete(prompt: "b", grammar: nil, maxTokens: 1) } }
        try await Task.sleep(nanoseconds: 40_000_000)
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("expected cancellation") } catch {}
        let b = try await kept.value
        XCTAssertEqual(b, "b")
        let active = await ai.activeTaskCount
        XCTAssertEqual(active, 0)
    }

    func testLoadFailureIsReportedAndRetryable() async {
        let attempts = Probe()
        let ai = InferenceCoordinator(loader: {
            await attempts.load()
            throw InferenceError.loadFailed("missing model")
        })
        do {
            _ = try await ai.perform { try await $0.complete(prompt: "", grammar: nil, maxTokens: 1) }
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? InferenceError, .loadFailed("missing model"))
        }
        _ = try? await ai.perform { try await $0.complete(prompt: "", grammar: nil, maxTokens: 1) }
        let loads = await attempts.loads
        XCTAssertEqual(loads, 2)
    }
}
