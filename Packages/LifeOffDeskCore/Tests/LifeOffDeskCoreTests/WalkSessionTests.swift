import XCTest
@testable import LifeOffDeskCore

final class WalkSessionTests: XCTestCase {
    private func ingest(_ recorder: inout WalkRecorder, east: Double, at seconds: Double) {
        let sample = Fixture.sample(east: east, north: 0, at: seconds)
        recorder.ingest(sample, receivedAt: sample.timestamp.addingTimeInterval(0.5))
    }

    func testPausedMovementAddsNoTrailAndResumeStartsNewSegment() throws {
        var recorder = WalkRecorder.start(at: Fixture.time(0))
        ingest(&recorder, east: 0, at: 1)
        ingest(&recorder, east: 10, at: 8)
        try recorder.pause(at: Fixture.time(10))
        ingest(&recorder, east: 200, at: 60)
        XCTAssertEqual(recorder.session.acceptedSampleCount, 2)
        try recorder.resume(at: Fixture.time(100))
        ingest(&recorder, east: 300, at: 101)
        ingest(&recorder, east: 310, at: 108)
        XCTAssertEqual(recorder.session.segments.count, 2)
        // Distance counts both segments but not the 290 m jump between them.
        XCTAssertEqual(recorder.session.distanceMeters, 20, accuracy: 0.05)
    }

    func testActiveDurationExcludesPause() throws {
        var recorder = WalkRecorder.start(at: Fixture.time(0))
        try recorder.pause(at: Fixture.time(300))
        try recorder.resume(at: Fixture.time(900))
        recorder.finish(at: Fixture.time(1000))
        XCTAssertEqual(recorder.session.activeDuration(at: Fixture.time(5000)), 400, accuracy: 0.001)
    }

    func testFinishIsIdempotent() {
        var recorder = WalkRecorder.start(at: Fixture.time(0))
        recorder.finish(at: Fixture.time(100))
        let first = recorder.session
        recorder.finish(at: Fixture.time(500))
        XCTAssertEqual(recorder.session, first)
        XCTAssertThrowsError(try recorder.pause(at: Fixture.time(600)))
        XCTAssertThrowsError(try recorder.resume(at: Fixture.time(600)))
    }

    func testInvalidTransitionsThrow() throws {
        var recorder = WalkRecorder.start(at: Fixture.time(0))
        XCTAssertThrowsError(try recorder.resume(at: Fixture.time(1))) { XCTAssertEqual($0 as? WalkCommandError, .notPaused) }
        try recorder.pause(at: Fixture.time(2))
        XCTAssertThrowsError(try recorder.pause(at: Fixture.time(3))) { XCTAssertEqual($0 as? WalkCommandError, .notWalking) }
    }

    func testInterruptedSessionRecoversPausedWithoutCountingDeadTime() {
        var recorder = WalkRecorder.start(at: Fixture.time(0))
        ingest(&recorder, east: 0, at: 1)
        ingest(&recorder, east: 10, at: 60)
        recorder.checkpoint(at: Fixture.time(65))
        // App killed; relaunched an hour later.
        let recovered = WalkRecorder.recover(recorder.session)
        XCTAssertEqual(recovered.state, .paused)
        XCTAssertTrue(recovered.wasRecovered)
        XCTAssertNil(recovered.activeSince)
        XCTAssertEqual(recovered.activeDuration(at: Fixture.time(3600)), 65, accuracy: 0.001)
        // Recovery of a paused or finished session changes nothing.
        XCTAssertEqual(WalkRecorder.recover(recovered), recovered)
    }

    func testRecoveredRecorderDoesNotJoinAcrossRelaunch() throws {
        var recorder = WalkRecorder.start(at: Fixture.time(0))
        ingest(&recorder, east: 0, at: 1)
        ingest(&recorder, east: 10, at: 6)
        var restored = WalkRecorder(session: WalkRecorder.recover(recorder.session))
        try restored.resume(at: Fixture.time(20))
        ingest(&restored, east: 18, at: 21)
        XCTAssertEqual(restored.session.segments.count, 2)
    }

    func testRecapComputesFromAcceptedSamples() {
        var recorder = WalkRecorder.start(at: Fixture.time(0))
        for step in 0..<10 { ingest(&recorder, east: Double(step) * 7, at: Double(step) * 5 + 1) }
        recorder.finish(at: Fixture.time(60))
        let grid = ExplorationGrid(origin: Fixture.origin)
        let recap = WalkRecap.compute(session: recorder.session, exploration: Exploration(revealWidthMeters: 25), grid: grid, now: Fixture.time(60))
        XCTAssertEqual(recap.distanceMeters, 63, accuracy: 0.1)
        XCTAssertEqual(recap.activeDuration, 60, accuracy: 0.001)
        XCTAssertEqual(recap.acceptedSamples, 10)
        // 63 m x 25 m corridor plus round ends ≈ 2066 m²; allow raster error.
        XCTAssertEqual(recap.newlyRevealedSquareMeters, 63 * 25 + .pi * 12.5 * 12.5, accuracy: 250)
    }
}
