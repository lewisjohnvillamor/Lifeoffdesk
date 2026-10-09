import XCTest
@testable import LifeOffDeskCore

/// Synthetic street layouts (metre offsets from the fixture origin), not real routes.
final class StreetRoutingTests: XCTestCase {
    private func road(_ points: [(Double, Double)], _ highway: String = "residential",
                      restricted: Bool = false) -> RoadContext.Road {
        let coords = points.map { Fixture.projection.unproject(MeterPoint(x: $0.0, y: $0.1)) }
        return RoadContext.Road(h: highway, r: restricted, c: coords.flatMap { [$0.longitude, $0.latitude] })
    }

    private func at(_ east: Double, _ north: Double) -> Coordinate {
        Fixture.projection.unproject(MeterPoint(x: east, y: north))
    }

    /// Two homes 200 m apart either side of a river, joined only by a bridge 1 km north.
    private var detourStreets: [RoadContext.Road] {
        [road([(0, 0), (0, 1000)]), road([(0, 1000), (200, 1000)]), road([(200, 1000), (200, 0)])]
    }

    func testDistanceFollowsStreetsNotStraightLine() throws {
        let graph = WalkingGraph(roads: detourStreets)
        let d = try XCTUnwrap(graph.distance(from: at(0, 0), to: at(200, 0)))
        XCTAssertEqual(d.meters, 2200, accuracy: 5)
        XCTAssertFalse(d.throughRestricted)
        XCTAssertEqual(d.walkingMinutes, 29)
    }

    func testOffStreetPointsHaveNoStreetDistance() {
        let graph = WalkingGraph(roads: detourStreets)
        XCTAssertNil(graph.distance(from: at(0, 0), to: at(5000, 5000)))
        XCTAssertNil(graph.distance(from: at(-3000, 0), to: at(200, 0)))
    }

    func testDisconnectedStreetsHaveNoStreetDistance() {
        let graph = WalkingGraph(roads: [road([(0, 0), (0, 100)]), road([(150, 0), (150, 100)])])
        XCTAssertNil(graph.distance(from: at(0, 0), to: at(150, 0)))
    }

    func testMotorwaysAreNotWalkable() {
        let graph = WalkingGraph(roads: detourStreets + [road([(0, 0), (200, 0)], "motorway")])
        XCTAssertEqual(graph.distance(from: at(0, 0), to: at(200, 0))?.meters ?? 0, 2200, accuracy: 5)
    }

    func testShortPrivateShortcutIsAvoidedWhenPublicDetourIsReasonable() throws {
        // Public way 300 m vs private 200 m: penalised private (400) loses.
        let graph = WalkingGraph(roads: [
            road([(0, 0), (0, 50), (200, 50), (200, 0)]),
            road([(0, 0), (200, 0)], restricted: true),
        ])
        let d = try XCTUnwrap(graph.distance(from: at(0, 0), to: at(200, 0)))
        XCTAssertEqual(d.meters, 300, accuracy: 5)
        XCTAssertFalse(d.throughRestricted)
    }

    func testPrivateRouteIsFlaggedWhenItIsTheOnlyReasonableWay() throws {
        let graph = WalkingGraph(roads: detourStreets + [road([(0, 0), (200, 0)], restricted: true)])
        let d = try XCTUnwrap(graph.distance(from: at(0, 0), to: at(200, 0)))
        XCTAssertEqual(d.meters, 200, accuracy: 5)
        XCTAssertTrue(d.throughRestricted)
    }

    func testOneSearchAnswersSeveralTargets() {
        let graph = WalkingGraph(roads: detourStreets)
        let results = graph.distances(from: at(0, 0), to: [at(0, 500), at(200, 0), at(9000, 0)])
        XCTAssertEqual(results[0]?.meters ?? 0, 500, accuracy: 5)
        XCTAssertEqual(results[1]?.meters ?? 0, 2200, accuracy: 5)
        XCTAssertNil(results[2])
    }

    func testSearchRanksAndLabelsByStreetDistance() throws {
        // "across" is nearer in a straight line but needs the long bridge detour.
        let across = Fixture.place("across", .park, east: 200, north: 0)
        let upstream = Fixture.place("upstream", .park, east: 0, north: 600)
        let catalog = Fixture.catalog([across, upstream])
        let graph = WalkingGraph(roads: detourStreets)
        let response = Planner.respond(OutingPreferences(categories: [.park]), catalog: catalog,
                                       origin: .currentLocation(at(0, 0)), options: SearchOptions(), graph: graph)
        guard case let .suggestions(_, intro, results) = response else { return XCTFail("expected suggestions") }
        XCTAssertEqual(results.map(\.place.id), ["upstream", "across"])
        XCTAssertTrue(intro.contains("by streets"), intro)
        XCTAssertTrue(PlannerCopy.reason(results[1]).contains("2.20 km lakad"), PlannerCopy.reason(results[1]))

        let plain = PlaceSearch.suggest(OutingPreferences(categories: [.park]), catalog: catalog, origin: .currentLocation(at(0, 0)))
        XCTAssertEqual(plain.map(\.place.id), ["across", "upstream"])
        XCTAssertTrue(PlannerCopy.reason(plain[0]).contains("straight-line"))
    }

    func testTimeLimitUsesStreetDistance() {
        // 20 minutes ≈ 750 m one way along streets: the 2.2 km detour does not fit.
        let across = Fixture.place("across", .park, east: 200, north: 0)
        let results = PlaceSearch.suggest(OutingPreferences(durationMinutes: 20, categories: [.park]),
                                          catalog: Fixture.catalog([across]), origin: .currentLocation(at(0, 0)),
                                          graph: WalkingGraph(roads: detourStreets))
        XCTAssertTrue(results[0].uncertainties.contains(.mayExceedTime(minutes: 20)))
    }
}
