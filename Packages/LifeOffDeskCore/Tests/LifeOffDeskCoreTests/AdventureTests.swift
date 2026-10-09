import XCTest
@testable import LifeOffDeskCore

final class AdventureTests: XCTestCase {
    private func walk(_ easts: [Double]) -> WalkSession {
        var s = WalkSession(startedAt: Fixture.time(0))
        s.segments = [easts.enumerated().map { Fixture.sample(east: $0.element, north: 0, at: Double($0.offset)) }]
        return s
    }

    func testPlacesPassedUsesDistanceFromAcceptedTrail() {
        let near = Fixture.place("near", .park, east: 100, north: 30)
        let far = Fixture.place("far", .cafe, east: 100, north: 80)
        let passed = Discovery.placesPassed(by: walk([0, 50, 100, 150]), in: Fixture.catalog([near, far]))
        XCTAssertEqual(passed.map(\.id), ["near"])
        XCTAssertTrue(Discovery.placesPassed(by: WalkSession(startedAt: Fixture.time(0)), in: Fixture.catalog([near])).isEmpty)
    }

    func testFrontiersPointAtUnexploredStreetsOnly() {
        let grid = ExplorationGrid(origin: Fixture.origin)
        func line(_ points: [(Double, Double)]) -> [Coordinate] {
            points.map { Fixture.projection.unproject(MeterPoint(x: $0.0, y: $0.1)) }
        }
        // Explored street to the east; unexplored streets to the north.
        let east = line([(0, 0), (200, 0), (400, 0), (600, 0)])
        let north = line([(0, 100), (0, 300), (0, 500), (0, 700)])
        var exploration = Exploration(revealWidthMeters: 50)
        var s = WalkSession(startedAt: Fixture.time(0))
        s.segments = [east.enumerated().map { TrackSample(latitude: $0.element.latitude, longitude: $0.element.longitude,
                                                          timestamp: Fixture.time(Double($0.offset)), horizontalAccuracy: 5) }]
        exploration.merge(s)
        let ideas = AdventureSuggester.frontiers(from: Fixture.origin, roads: [east, north],
                                                 explored: grid.cells(for: exploration), grid: grid)
        XCTAssertEqual(ideas.count, 1)
        guard case let .frontier(meters, bearing) = ideas[0].kind else { return XCTFail() }
        XCTAssertGreaterThan(meters, 500)
        XCTAssertEqual(AdventureSuggester.compassWord(bearing), "north")
    }

    func testUndiscoveredPlacesPreferFavouriteCategories() {
        let catalog = Fixture.catalog([
            Fixture.place("cafe-near", .cafe, east: 100, north: 0),
            Fixture.place("park-far", .park, east: 900, north: 0),
            Fixture.place("park-seen", .park, east: 50, north: 0),
        ])
        let ideas = AdventureSuggester.undiscoveredPlaces(from: Fixture.origin, catalog: catalog, discoveredIDs: ["park-seen"],
                                                          preferred: [.park])
        XCTAssertEqual(ideas.map(\.id), ["place:park-far", "place:cafe-near"])
        XCTAssertEqual(AdventureSuggester.favouriteCategories([catalog.places[1], catalog.places[2], catalog.places[0]]),
                       [.park, .cafe])
    }
}
