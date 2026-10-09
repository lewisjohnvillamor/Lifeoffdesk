import Foundation

public enum PlaceCategory: String, Codable, CaseIterable, Sendable {
    case park, cafe, museum, library, scenic, other
}

public enum MoodTag: String, Codable, CaseIterable, Sendable {
    case quiet, nature, curious, relax, active
}

/// A bundled place. Only `budgetPHP`, `quietness`, `openingHours` and `tags` count as facts
/// usable for matching, and they stay nil/empty until a person reviews them. `source*` fields
/// repeat what the source says and are always displayed as unverified.
public struct Place: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var category: PlaceCategory
    public var tags: [MoodTag]
    public var sourceURL: String
    public var retrievedAt: String
    public var verificationStatus: String
    public var positionMethod: String?
    public var budgetPHP: Int?
    public var quietness: String?
    public var openingHours: String?
    public var sourceOpeningHours: String?
    public var sourceAccess: String?
    public var sourceFee: String?
    public var sourceLevel: String?

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    public var isReviewed: Bool { verificationStatus == "reviewed" }
}

public struct PlaceCatalog: Codable, Sendable {
    public var schemaVersion: Int
    public var regionID: String
    public var attribution: String
    public var licenseURL: String
    public var retrievedAt: String
    public var sourceTimestamp: String?
    public var selectionRule: String
    public var places: [Place]

    public func place(id: String) -> Place? { places.first { $0.id == id } }

    public static func decode(_ data: Data) throws -> PlaceCatalog {
        try JSONDecoder().decode(PlaceCatalog.self, from: data)
    }
}

public struct RegionManifest: Codable, Sendable {
    public struct FileEntry: Codable, Sendable {
        public var name: String
        public var bytes: Int
        public var sha256: String
    }

    public var schemaVersion: Int
    public var id: String
    public var version: Int
    public var name: String
    public var coverageStatus: String
    public var bounds: BoundingBox
    public var center: Coordinate
    public var source: String
    public var attribution: String
    public var licenseURL: String
    public var builtAt: String
    public var files: [FileEntry]
}

/// Compact road context: visual only, never a routing graph.
public struct RoadContext: Codable, Sendable {
    public struct Road: Codable, Sendable {
        /// OSM highway class.
        public var h: String
        /// Restricted according to source access tags.
        public var r: Bool
        /// Flattened lon,lat pairs.
        public var c: [Double]

        public var coordinates: [Coordinate] {
            stride(from: 0, to: c.count - 1, by: 2).map { Coordinate(latitude: c[$0 + 1], longitude: c[$0]) }
        }
    }

    public var schemaVersion: Int
    public var attribution: String
    public var roads: [Road]
}
