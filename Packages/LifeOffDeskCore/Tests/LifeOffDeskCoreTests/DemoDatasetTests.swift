import XCTest
@testable import LifeOffDeskCore

final class DemoDatasetTests: XCTestCase {
    private func bundled() throws -> DemoDataset {
        let url = Fixture.repoRoot.appendingPathComponent("LifeOffDesk/Resources/StarterData/demo/sample-walks.json")
        return try DemoDataset.decode(Data(contentsOf: url))
    }

    func testBundledDemoWalksAreLabelledFinishedAndInsideRegions() throws {
        let demo = try bundled()
        XCTAssertTrue(demo.label.contains("SYNTHETIC"))
        XCTAssertTrue(demo.label.contains("not real GPS"))
        XCTAssertGreaterThanOrEqual(demo.walks.count, 20)
        let base = Fixture.repoRoot.appendingPathComponent("LifeOffDesk/Resources/StarterData")
        let regions = try ["makati-cbd-starter", "muntinlupa"].map {
            try JSONDecoder().decode(RegionManifest.self, from: Data(contentsOf: base.appendingPathComponent("\($0)/region.json")))
        }
        for walk in demo.walks {
            XCTAssertEqual(walk.state, .finished)
            XCTAssertGreaterThan(walk.distanceMeters, 300)
            XCTAssertTrue(regions.contains { $0.bounds.contains(walk.segments[0][0].coordinate) })
            // Timestamps strictly increase, so the same filter used for real walks would accept the pace.
            for (a, b) in zip(walk.segments[0], walk.segments[0].dropFirst()) {
                XCTAssertLessThan(a.timestamp, b.timestamp)
                XCTAssertLessThanOrEqual(Geo.distanceMeters(a.coordinate, b.coordinate) / b.timestamp.timeIntervalSince(a.timestamp), 4)
            }
        }
        XCTAssertEqual(Set(demo.walks.map(\.id)).count, demo.walks.count)
    }

    func testDemoExplorationIsSubstantialAndRecapsCompute() throws {
        let demo = try bundled()
        let exploration = demo.exploration
        XCTAssertEqual(exploration.sourceSessionIDs.count, demo.walks.count)
        let grid = ExplorationGrid(origin: Coordinate(latitude: 14.5566, longitude: 121.0244))
        let area = grid.areaSquareMeters(grid.cells(for: exploration))
        XCTAssertGreaterThan(area, 500_000, "A demo map should look well explored")
        let recap = WalkRecap.compute(session: demo.walks[0], exploration: exploration, grid: grid, now: Date())
        XCTAssertEqual(recap.distanceMeters, demo.walks[0].distanceMeters)
    }

    func testNeighbourhoodRecapMatchesFullRasterisation() throws {
        let demo = try bundled()
        let exploration = demo.exploration
        let grid = ExplorationGrid(origin: Coordinate(latitude: 14.5566, longitude: 121.0244))
        let walk = demo.walks[3]
        let fast = WalkRecap.compute(session: walk, exploration: exploration, grid: grid, now: Date())
        // Brute force over every other walk.
        let others = exploration.excluding(sessionID: walk.id)
        var with = others
        with.merge(walk)
        let before = grid.cells(for: others), after = grid.cells(for: with)
        XCTAssertEqual(fast.newlyRevealedSquareMeters, grid.areaSquareMeters(after.subtracting(before)))
    }

    func testReplayRevealsProgressivelyAndKeepsSegments() {
        var session = WalkSession(startedAt: Fixture.time(0))
        session.segments = [
            (0..<5).map { Fixture.sample(east: Double($0) * 10, north: 0, at: Double($0)) },
            (0..<3).map { Fixture.sample(east: 200 + Double($0) * 10, north: 0, at: 100 + Double($0)) },
        ]
        var replay = WalkReplay(source: session)
        XCTAssertEqual(replay.totalSamples, 8)
        XCTAssertTrue(replay.partialSession.segments.isEmpty)
        replay.advance(by: 6)
        XCTAssertEqual(replay.partialSession.segments.map(\.count), [5, 1])
        XCTAssertEqual(replay.partialSession.distanceMeters, 40, accuracy: 0.1)
        replay.advance(by: 100)
        XCTAssertTrue(replay.isFinished)
        XCTAssertEqual(replay.partialSession.segments, session.segments)
    }
}

final class WalkStatsTests: XCTestCase {
    private func walk(_ easts: [Double], startingAt seconds: Double) -> WalkSession {
        var s = WalkSession(startedAt: Fixture.time(seconds))
        s.segments = [easts.enumerated().map { Fixture.sample(east: $0.element, north: 0, at: seconds + Double($0.offset)) }]
        s.state = .finished
        s.endedAt = Fixture.time(seconds + 100)
        return s
    }

    func testNewDistanceIsMeasuredAgainstEarlierWalksOnly() {
        let grid = ExplorationGrid(origin: Fixture.origin)
        let first = walk([0, 100, 200], startingAt: 0)
        let second = walk([0, 100, 200, 300], startingAt: 1000) // repeats the first walk, then 100 m new
        let stats = WalkStats.compute(walks: [second, first], grid: grid, revealWidthMeters: 25)
        XCTAssertEqual(stats.recaps[first.id]!.newDistanceMeters, 200, accuracy: 1, "A later walk must not shrink an earlier one")
        XCTAssertEqual(stats.recaps[second.id]!.newDistanceMeters, 100, accuracy: 15)
        XCTAssertEqual(stats.totalDistanceMeters, 500, accuracy: 1)
        XCTAssertEqual(stats.walkCount, 2)
        XCTAssertEqual(stats.firstWalkAt, first.startedAt)
        // Summed newly revealed areas equal the union area.
        var all = Exploration(revealWidthMeters: 25)
        all.merge(first); all.merge(second)
        XCTAssertEqual(stats.exploredSquareMeters, grid.areaSquareMeters(grid.cells(for: all)), accuracy: 0.001)
    }
}
