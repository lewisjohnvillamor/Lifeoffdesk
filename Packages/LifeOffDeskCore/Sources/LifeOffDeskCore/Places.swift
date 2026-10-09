import Foundation

public enum PlaceCategory: String, Codable, CaseIterable, Sendable {
    case park, cafe, food, museum, library, scenic, other
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
    /// OSM cuisine tag, e.g. "pizza;italian" (source claim, unreviewed).
    public var sourceCuisine: String?

    /// Lower-cased words a keyword can match: the name plus OSM cuisine values.
    public var searchableTerms: [String] {
        var terms = [name.lowercased()]
        if let cuisine = sourceCuisine {
            terms += cuisine.lowercased().split(whereSeparator: { $0 == ";" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: " ") }
        }
        return terms
    }

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
    /// "full" (streets, footpaths, places) or "major-roads" (recording area with main-road context).
    public var detail: String?
    public var coverageStatus: String
    public var bounds: BoundingBox
    public var center: Coordinate
    public var source: String
    public var attribution: String
    public var licenseURL: String
    public var builtAt: String
    public var files: [FileEntry]
}

/// Index of bundled region packs; the first entry is the primary region (map origin).
public struct RegionIndex: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var id: String
        public var detail: String
    }
    public var schemaVersion: Int
    public var regions: [Entry]
}

extension RegionManifest {
    public var hasFullDetail: Bool { (detail ?? "full") == "full" }
}

extension PlaceCatalog {
    /// Union of several region catalogs, first occurrence of an ID wins.
    public static func merged(_ catalogs: [PlaceCatalog]) -> PlaceCatalog? {
        guard var first = catalogs.first else { return nil }
        var seen = Set(first.places.map(\.id))
        for catalog in catalogs.dropFirst() {
            for place in catalog.places where seen.insert(place.id).inserted { first.places.append(place) }
        }
        first.regionID = catalogs.map(\.regionID).joined(separator: "+")
        return first
    }
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
