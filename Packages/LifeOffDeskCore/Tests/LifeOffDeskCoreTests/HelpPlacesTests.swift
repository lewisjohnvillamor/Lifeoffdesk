import XCTest
@testable import LifeOffDeskCore

/// Synthetic help places along the fixture streets; not real stations.
final class HelpPlacesTests: XCTestCase {
    private func help(_ id: String, _ kind: String, east: Double, north: Double) -> Place {
        var place = Fixture.place(id, .other, east: east, north: north)
        place.sourceKind = kind
        return place
    }

    private func road(_ points: [(Double, Double)]) -> RoadContext.Road {
        let coords = points.map { Fixture.projection.unproject(MeterPoint(x: $0.0, y: $0.1)) }
        return RoadContext.Road(h: "residential", r: false, c: coords.flatMap { [$0.longitude, $0.latitude] })
    }

    func testNearestHelpIsGroupedAndRankedByStreetDistance() throws {
        // "across" is closest in a straight line but only reachable over a bridge 1 km north.
        let roads = [road([(0, 0), (0, 1000)]), road([(0, 1000), (200, 1000)]), road([(200, 1000), (200, 0)])]
        let catalog = Fixture.catalog([
            help("across", "police", east: 200, north: 0),
            help("upstream", "police", east: 0, north: 600),
            help("er", "hospital", east: 0, north: 300),
            Fixture.place("cafe", .cafe, east: 0, north: 10),
            help("far", "fire_station", east: 20_000, north: 0),
        ])
        let origin = Fixture.projection.unproject(MeterPoint(x: 0, y: 0))
        let result = HelpPlaces.nearest(in: catalog, from: origin, graph: WalkingGraph(roads: roads))
        XCTAssertEqual(result[.police]?.map(\.id), ["upstream", "across"])
        XCTAssertEqual(result[.police]?[1].street?.meters ?? 0, 2200, accuracy: 5)
        XCTAssertEqual(result[.hospital]?.map(\.id), ["er"])
        XCTAssertNil(result[.fireStation], "beyond 10 km is not listed")

        // Without a street graph the order is straight-line and no street distance is claimed.
        let plain = HelpPlaces.nearest(in: catalog, from: origin, graph: nil)
        XCTAssertEqual(plain[.police]?.map(\.id), ["across", "upstream"])
        XCTAssertNil(plain[.police]?[0].street)
    }

    func testLocationDescriptionNamesANearbyPlaceOnlyWhenClose() {
        let origin = Fixture.projection.unproject(MeterPoint(x: 0, y: 0))
        let near = Fixture.catalog([Fixture.place("kiosk", .cafe, east: 50, north: 0)])
        XCTAssertTrue(HelpPlaces.locationDescription(origin, accuracyMeters: 8, catalog: near)
            .hasSuffix("(±8 m) · about 50 m from Synthetic kiosk"))
        let far = Fixture.catalog([Fixture.place("kiosk", .cafe, east: 900, north: 0)])
        XCTAssertFalse(HelpPlaces.locationDescription(origin, accuracyMeters: nil, catalog: far).contains("from"))
    }

    func testTaglishWordsFindHelpPlaces() {
        XCTAssertTrue(help("p", "police", east: 0, north: 0).searchableTerms.contains("pulis"))
        XCTAssertTrue(help("f", "fire_station", east: 0, north: 0).searchableTerms.contains("bumbero"))
    }
}
