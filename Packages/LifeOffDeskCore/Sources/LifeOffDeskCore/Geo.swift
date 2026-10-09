import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Geo {
    public static let earthRadiusMeters = 6_371_008.8

    /// Great-circle distance. This is straight-line distance, never a walking route.
    public static func distanceMeters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }
}

/// Local planar point in meters (x east, y north) around an origin.
public struct MeterPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Equirectangular projection; accurate enough for a few-kilometre starter area.
public struct LocalProjection: Sendable {
    public let origin: Coordinate
    private let metersPerDegreeLat: Double
    private let metersPerDegreeLon: Double

    public init(origin: Coordinate) {
        self.origin = origin
        metersPerDegreeLat = Geo.earthRadiusMeters * .pi / 180
        metersPerDegreeLon = metersPerDegreeLat * cos(origin.latitude * .pi / 180)
    }

    public func project(_ c: Coordinate) -> MeterPoint {
        MeterPoint(x: (c.longitude - origin.longitude) * metersPerDegreeLon,
                   y: (c.latitude - origin.latitude) * metersPerDegreeLat)
    }

    public func unproject(_ p: MeterPoint) -> Coordinate {
        Coordinate(latitude: origin.latitude + p.y / metersPerDegreeLat,
                   longitude: origin.longitude + p.x / metersPerDegreeLon)
    }
}

public struct BoundingBox: Codable, Hashable, Sendable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south; self.west = west; self.north = north; self.east = east
    }

    public func contains(_ c: Coordinate) -> Bool {
        c.latitude >= south && c.latitude <= north && c.longitude >= west && c.longitude <= east
    }

    public var center: Coordinate {
        Coordinate(latitude: (south + north) / 2, longitude: (west + east) / 2)
    }
}
