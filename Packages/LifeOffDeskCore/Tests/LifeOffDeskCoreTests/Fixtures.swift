import Foundation
@testable import LifeOffDeskCore

/// Synthetic replay helpers. Coordinates are generated offsets, not anyone's real route.
enum Fixture {
    static let origin = Coordinate(latitude: 14.5566, longitude: 121.0244)
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let projection = LocalProjection(origin: origin)

    static func sample(east: Double, north: Double, at seconds: Double, accuracy: Double = 5) -> TrackSample {
        let c = projection.unproject(MeterPoint(x: east, y: north))
        return TrackSample(latitude: c.latitude, longitude: c.longitude,
                           timestamp: t0.addingTimeInterval(seconds), horizontalAccuracy: accuracy)
    }

    static func time(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func place(_ id: String, _ category: PlaceCategory, east: Double, north: Double,
                      price: Int? = nil, tags: [MoodTag] = [], reviewed: Bool = false) -> Place {
        let c = projection.unproject(MeterPoint(x: east, y: north))
        return Place(id: id, name: "Synthetic \(id)", latitude: c.latitude, longitude: c.longitude,
                     category: category, tags: tags, sourceURL: "fixture", retrievedAt: "fixture",
                     verificationStatus: reviewed ? "reviewed" : "source-only-unreviewed", positionMethod: "node",
                     budgetPHP: price, quietness: nil, openingHours: nil, sourceOpeningHours: nil,
                     sourceAccess: nil, sourceFee: nil, sourceLevel: nil)
    }

    static func catalog(_ places: [Place]) -> PlaceCatalog {
        PlaceCatalog(schemaVersion: 1, regionID: "fixture", attribution: "fixture", licenseURL: "fixture",
                     retrievedAt: "fixture", sourceTimestamp: nil, selectionRule: "fixture", places: places)
    }

    static func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lod-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
