import XCTest
@testable import LifeOffDeskCore

/// Synthetic street grid: two east-west streets 100 m apart and one north-south street.
final class StreetMatchingTests: XCTestCase {
    private func road(_ points: [(Double, Double)], _ highway: String = "residential") -> RoadContext.Road {
        let coords = points.map { Fixture.projection.unproject(MeterPoint(x: $0.0, y: $0.1)) }
        return RoadContext.Road(h: highway, r: false, c: coords.flatMap { [$0.longitude, $0.latitude] })
    }

    private lazy var network = StreetNetwork(roads: [
        road([(0, 0), (300, 0)]),          // "A street"
        road([(0, 100), (300, 100)]),      // "B street"
        road([(150, -50), (150, 150)]),    // cross street
    ], origin: Fixture.origin)

    private func trail(_ points: [(Double, Double)], spacing seconds: Double = 5) -> [[TrackSample]] {
        [points.enumerated().map { Fixture.sample(east: $0.element.0, north: $0.element.1, at: Double($0.offset) * seconds) }]
    }

    func testDriftingTrailSnapsToTheStreetWalked() {
        // GPS wobbling 8–14 m north of A street.
        let result = StreetMatcher.match(trail([(10, 8), (60, 14), (110, 9), (160, 12), (210, 10)]), network: network)
        let covered = result.coverage.coveredMeters(in: network)
        XCTAssertEqual(covered, 200, accuracy: 15)
        XCTAssertTrue(result.unmatched.isEmpty)
        // Nothing on B street, 90 m away.
        let pieces = result.coverage.pieces(in: network)
        XCTAssertTrue(pieces.allSatisfy { $0.points.allSatisfy { abs($0.y) < 1 || abs($0.x - 150) < 1 } })
    }

    func testCrossingAStreetDoesNotPaintItsLength() {
        // Walk north along the cross street: A and B are crossed, not walked along.
        let result = StreetMatcher.match(trail([(152, -40), (151, 0), (149, 50), (150, 100), (151, 140)]), network: network)
        let byStreet = result.coverage.bins.keys.map { network.segments[$0] }
        XCTAssertTrue(byStreet.allSatisfy { abs($0.a.x - $0.b.x) < 1 }, "Only the north-south street counts")
        XCTAssertEqual(result.coverage.coveredMeters(in: network), 180, accuracy: 15)
    }

    func testCuttingThroughABlockIsUnmatchedNotPaintedAsStreets() {
        // Diagonal through the middle of the block between A and B (no street there).
        let result = StreetMatcher.match(trail([(40, 40), (70, 55), (100, 60)]), network: network)
        XCTAssertTrue(result.coverage.isEmpty)
        XCTAssertEqual(result.unmatched.count, 1)
    }

    func testNewStreetsAreCountedOnceAcrossAdventures() {
        let grid = ExplorationGrid(origin: Fixture.origin)
        func walk(_ pts: [(Double, Double)], at start: Double) -> WalkSession {
            var s = WalkSession(startedAt: Fixture.time(start))
            s.segments = [pts.enumerated().map { Fixture.sample(east: $0.element.0, north: $0.element.1, at: start + Double($0.offset) * 5) }]
            s.state = .finished; s.endedAt = Fixture.time(start + 100)
            return s
        }
        let first = walk([(0, 5), (50, 5), (100, 5), (150, 5)], at: 0)
        let second = walk([(0, 4), (50, 6), (100, 4), (150, 5), (200, 5), (250, 5)], at: 1000)
        let stats = WalkStats.compute(walks: [second, first], grid: grid, network: network)
        XCTAssertEqual(stats.recaps[first.id]!.newDistanceMeters, 150, accuracy: 12)
        XCTAssertEqual(stats.recaps[second.id]!.newDistanceMeters, 100, accuracy: 12, "Only the extension is new")
        XCTAssertEqual(stats.streetCoverage.coveredMeters(in: network), 250, accuracy: 12)
    }

    func testRevealAndTrailRunsFollowStreets() {
        let id = UUID()
        let result = StreetMatcher.match(trail([(10, 8), (60, 12), (110, 9)]), network: network)
        let exploration = StreetReveal.exploration(coverage: [id: result.coverage], unmatched: [id: result.unmatched], network: network)
        XCTAssertFalse(exploration.paths.isEmpty)
        let projected = exploration.paths.flatMap { $0.points }.map { Fixture.projection.project($0) }
        XCTAssertTrue(projected.allSatisfy { abs($0.y) < 1 }, "Island follows the street centreline, not the GPS wobble")
        let runs = StreetReveal.trailRuns(trail([(10, 8), (60, 12), (110, 9), (160, 10), (210, 9)]), prior: result.coverage, network: network)
        XCTAssertTrue(runs.contains { $0.isNew } && runs.contains { !$0.isNew })
    }

    func testStreetFrontiersSkipWalkedStreets() {
        // Walk all of A street and the cross street; only B street (to the north) stays unexplored.
        var walked = StreetMatcher.match(trail([(0, 4), (100, 5), (200, 4), (300, 5)]), network: network).coverage
        walked.merge(StreetMatcher.match(trail([(151, -50), (150, 0), (149, 50), (150, 100), (151, 150)]), network: network).coverage)
        let ideas = AdventureSuggester.frontiers(from: Fixture.origin, network: network, coverage: walked,
                                                 searchRadius: 400, minimumMeters: 50, limit: 3)
        XCTAssertFalse(ideas.isEmpty)
        for idea in ideas {
            guard case let .frontier(_, bearing) = idea.kind else { return XCTFail() }
            XCTAssertTrue(["north", "north-east"].contains(AdventureSuggester.compassWord(bearing)),
                          "Only unwalked B street remains, to the north")
        }
    }
}
