import XCTest
@testable import LifeOffDeskCore

final class TrackFilterTests: XCTestCase {
    private func feed(_ filter: inout TrackFilter, _ sample: TrackSample, receivedLag: Double = 0.5) -> TrackDecision {
        filter.evaluate(sample, receivedAt: sample.timestamp.addingTimeInterval(receivedLag))
    }

    func testFirstValidFixStartsSegment() {
        var filter = TrackFilter()
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 0, north: 0, at: 0)), .accepted(startsSegment: true))
    }

    func testRejectsInvalidInaccurateStaleAndFutureFixes() {
        var filter = TrackFilter()
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 0, north: 0, at: 0, accuracy: -1)), .rejected(.invalidAccuracy))
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 0, north: 0, at: 0, accuracy: 31)), .rejected(.inaccurate))
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 0, north: 0, at: 0), receivedLag: 10.5), .rejected(.stale))
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 0, north: 0, at: 0), receivedLag: -2.5), .rejected(.futureTimestamp))
        XCTAssertNil(filter.anchor, "Nothing may reveal before a valid fix")
    }

    func testRejectsNonIncreasingTimestamps() {
        var filter = TrackFilter()
        _ = feed(&filter, Fixture.sample(east: 0, north: 0, at: 10))
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 10, north: 0, at: 10)), .rejected(.nonIncreasingTimestamp))
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 10, north: 0, at: 9)), .rejected(.nonIncreasingTimestamp))
    }

    func testNormalWalkingIsAccepted() {
        var filter = TrackFilter()
        var accepted = 0
        for second in 0..<60 {
            // ~1.4 m/s, a fix every 5 seconds
            if second % 5 == 0, case .accepted = feed(&filter, Fixture.sample(east: Double(second) * 1.4, north: 0, at: Double(second))) {
                accepted += 1
            }
        }
        XCTAssertEqual(accepted, 12)
    }

    func testTeleportJumpIsRejectedThenGapStartsNewSegment() {
        var filter = TrackFilter()
        _ = feed(&filter, Fixture.sample(east: 0, north: 0, at: 0))
        _ = feed(&filter, Fixture.sample(east: 7, north: 0, at: 5))
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 400, north: 0, at: 10)), .rejected(.implausibleJump))
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 410, north: 0, at: 14)), .rejected(.implausibleJump))
        // After a long gap since the last valid fix the new position starts a separate segment.
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 420, north: 0, at: 25)), .accepted(startsSegment: true))
    }

    func testLongUpdateGapBreaksSegment() {
        var filter = TrackFilter()
        _ = feed(&filter, Fixture.sample(east: 0, north: 0, at: 0))
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 30, north: 0, at: 16)), .accepted(startsSegment: true))
    }

    func testStationaryJitterDoesNotGrowTrail() {
        // Five minutes standing still: ±4 m scatter with 5–15 m reported accuracy.
        var filter = TrackFilter()
        var generator = SeededGenerator(seed: 42)
        var trail: [TrackSample] = []
        for second in 0..<300 {
            let sample = Fixture.sample(east: Double.random(in: -4...4, using: &generator),
                                        north: Double.random(in: -4...4, using: &generator),
                                        at: Double(second), accuracy: Double.random(in: 5...15, using: &generator))
            if case .accepted = feed(&filter, sample) { trail.append(sample) }
        }
        let drift = zip(trail, trail.dropFirst()).reduce(0) { $0 + Geo.distanceMeters($1.0.coordinate, $1.1.coordinate) }
        XCTAssertLessThanOrEqual(trail.count, 3, "Drift must not steadily add trail points")
        XCTAssertLessThan(drift, 20)
    }

    func testMeasuredZeroSpeedSuppressesSmallMoves() {
        var filter = TrackFilter()
        _ = feed(&filter, Fixture.sample(east: 0, north: 0, at: 0))
        var still = Fixture.sample(east: 7, north: 0, at: 1)
        still.speed = 0
        XCTAssertEqual(feed(&filter, still), .stationary)
        var moving = Fixture.sample(east: 7, north: 0, at: 2)
        moving.speed = 1.3
        XCTAssertEqual(feed(&filter, moving), .accepted(startsSegment: false))
    }

    func testStandingStillLongerThanGapDoesNotBreakSegment() {
        var filter = TrackFilter()
        _ = feed(&filter, Fixture.sample(east: 0, north: 0, at: 0))
        for second in stride(from: 1.0, through: 40, by: 1) {
            _ = feed(&filter, Fixture.sample(east: 1, north: 0, at: second))
        }
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 9, north: 0, at: 42)), .accepted(startsSegment: false))
    }

    func testBreakSegmentForcesNewSegment() {
        var filter = TrackFilter()
        _ = feed(&filter, Fixture.sample(east: 0, north: 0, at: 0))
        filter.breakSegment()
        XCTAssertEqual(feed(&filter, Fixture.sample(east: 8, north: 0, at: 5)), .accepted(startsSegment: true))
    }
}

/// Deterministic generator so jitter replays are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Adventures can be on foot or riding: driving is recorded and labelled, glitches still rejected.
final class TravelModeTests: XCTestCase {
    func testDrivingIsRecordedAndGlitchesAreStillRejected() {
        var filter = TrackFilter()
        let t0 = Fixture.t0
        // 15 m/s (54 km/h) car on an expressway, one fix every 5 s.
        for i in 0..<6 {
            let decision = filter.evaluate(Fixture.sample(east: Double(i) * 75, north: 0, at: Double(i) * 5),
                                           receivedAt: t0.addingTimeInterval(Double(i) * 5))
            guard case .accepted = decision else { return XCTFail("fix \(i) at driving speed was \(decision)") }
        }
        // A 600 m jump in 5 s (120 m/s) is a GPS glitch, not a car.
        let glitch = filter.evaluate(Fixture.sample(east: 975, north: 0, at: 30), receivedAt: t0.addingTimeInterval(30))
        XCTAssertEqual(glitch, .rejected(.implausibleJump))
    }

    func testSplitSeparatesWalkingFromRiding() {
        let walk = (0..<5).map { Fixture.sample(east: Double($0) * 7, north: 0, at: Double($0) * 5) }        // 1.4 m/s
        let ride = (0..<5).map { Fixture.sample(east: 1000 + Double($0) * 60, north: 0, at: 100 + Double($0) * 5) } // 12 m/s
        let split = TravelMode.split([walk, ride])
        XCTAssertEqual(split.onFoot, 28, accuracy: 1)
        XCTAssertEqual(split.riding, 240, accuracy: 1)
    }

    func testOSMeasuredSpeedWinsWhenAvailable() {
        let a = TrackSample(latitude: 14.5, longitude: 121.0, timestamp: Fixture.t0, horizontalAccuracy: 5, speed: 10)
        let b = TrackSample(latitude: 14.50001, longitude: 121.0, timestamp: Fixture.t0.addingTimeInterval(5),
                            horizontalAccuracy: 5, speed: 10)
        XCTAssertEqual(TravelMode.of(a, b), .riding)
    }
}
