import XCTest
@testable import LifeOffDeskCore

/// Synthetic city boxes along a north-south line (~5.5 km apart), not real boundaries.
final class RegionChunksTests: XCTestCase {
    private let regions: [(id: String, bounds: BoundingBox)] = [
        ("south", BoundingBox(south: 14.40, west: 121.00, north: 14.44, east: 121.05)),
        ("middle", BoundingBox(south: 14.45, west: 121.00, north: 14.49, east: 121.05)),
        ("north", BoundingBox(south: 14.50, west: 121.00, north: 14.54, east: 121.05)),
        ("far", BoundingBox(south: 14.70, west: 121.00, north: 14.74, east: 121.05)),
    ]

    func testPositionLoadsOnlyItsCityAndNeighboursWithinReach() {
        let here = Coordinate(latitude: 14.47, longitude: 121.02) // inside "middle"
        XCTAssertEqual(RegionChunks.desired(regions, demand: .init(points: [here], reachMeters: 500)), ["middle"])
        // Neighbours start ~3.3 km away: a 3.5 km reach includes both, never the far city.
        XCTAssertEqual(RegionChunks.desired(regions, demand: .init(points: [here], reachMeters: 3500)),
                       ["middle", "north", "south"])
    }

    func testViewportStreamsCitiesBeforeTheyScrollIn() {
        let view = BoundingBox(south: 14.515, west: 121.01, north: 14.53, east: 121.04) // inside "north"
        let desired = RegionChunks.desired(regions, demand: .init(viewport: view))
        XCTAssertEqual(desired, ["north"])
        let nearEdge = BoundingBox(south: 14.501, west: 121.01, north: 14.51, east: 121.04)
        XCTAssertEqual(RegionChunks.desired(regions, demand: .init(viewport: nearEdge)), ["middle", "north"],
                       "the margin preloads the city just below the visible edge")
    }

    func testPinnedHistoryRegionsStayLoaded() {
        XCTAssertEqual(RegionChunks.desired(regions, demand: .init(pinned: ["far"])), ["far"])
    }

    func testEvictionKeepsDesiredAndTheMostRecentWarmCities() {
        let now = Date()
        let loaded: [String: Date] = ["a": now, "b": now.addingTimeInterval(-10), "c": now.addingTimeInterval(-20),
                                      "d": now.addingTimeInterval(-30)]
        XCTAssertEqual(RegionChunks.evictions(loaded: loaded, desired: ["a"], maxWarm: 2), ["d"])
        XCTAssertEqual(RegionChunks.evictions(loaded: loaded, desired: ["a", "b", "c", "d"]), [])
    }

    func testTouchedRegionsComeFromAcceptedSamples() {
        var walk = WalkSession(startedAt: Fixture.t0)
        walk.segments = [[TrackSample(latitude: 14.42, longitude: 121.02, timestamp: Fixture.t0, horizontalAccuracy: 5),
                          TrackSample(latitude: 14.47, longitude: 121.02, timestamp: Fixture.t0.addingTimeInterval(600),
                                      horizontalAccuracy: 5)]]
        XCTAssertEqual(RegionChunks.touched(by: [walk], regions: regions), ["south", "middle"])
    }
}
