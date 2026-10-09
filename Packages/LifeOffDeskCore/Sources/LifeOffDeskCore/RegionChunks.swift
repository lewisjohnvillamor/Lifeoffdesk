import Foundation

/// Decides which city packs ("chunks") should be in memory, like a game streaming the world
/// around the player. Pure and deterministic; the app does the actual loading off the main thread.
public enum RegionChunks {
    /// What the app needs right now, all in coordinates.
    public struct Demand: Sendable {
        /// Visible map area, if the map is on screen.
        public var viewport: BoundingBox?
        /// GPS position, planner origin, destination: points that need streets and places around them.
        public var points: [Coordinate]
        /// Extra reach around `points` in metres (planner search radius, walking-distance reach).
        public var reachMeters: Double
        /// Regions that must stay loaded for correct history totals (adventures that passed through).
        public var pinned: Set<String>

        public init(viewport: BoundingBox? = nil, points: [Coordinate] = [], reachMeters: Double = 2000,
                    pinned: Set<String> = []) {
            self.viewport = viewport; self.points = points; self.reachMeters = reachMeters; self.pinned = pinned
        }
    }

    /// Margin around the viewport so neighbouring cities are ready before they scroll into view.
    public static let viewportMarginMeters = 1500.0
    /// Upper bound on detailed cities kept loaded beyond what is strictly demanded (recently used).
    public static let maxWarmRegions = 2

    /// Regions whose bounds come near the demand: pinned, intersecting the padded viewport, or
    /// within `reachMeters` of any point. Sorted for stable results.
    public static func desired(_ regions: [(id: String, bounds: BoundingBox)], demand: Demand) -> [String] {
        let padded = demand.viewport.map { expand($0, meters: viewportMarginMeters) }
        return regions.filter { region in
            if demand.pinned.contains(region.id) { return true }
            if let padded, intersects(padded, region.bounds) { return true }
            return demand.points.contains { point in
                intersects(expand(BoundingBox(south: point.latitude, west: point.longitude,
                                              north: point.latitude, east: point.longitude),
                                  meters: demand.reachMeters), region.bounds)
            }
        }.map(\.id).sorted()
    }

    /// Which loaded regions to free: everything not desired except the `maxWarmRegions` most
    /// recently used, so scrolling back and forth does not reload constantly.
    public static func evictions(loaded: [String: Date], desired: Set<String>,
                                 maxWarm: Int = maxWarmRegions) -> Set<String> {
        let idle = loaded.filter { !desired.contains($0.key) }.sorted { $0.value > $1.value }
        return Set(idle.dropFirst(maxWarm).map(\.key))
    }

    /// Regions that adventures passed through (any accepted sample inside the bounds).
    public static func touched(by walks: [WalkSession], regions: [(id: String, bounds: BoundingBox)]) -> Set<String> {
        var ids = Set<String>()
        for walk in walks {
            for sample in walk.segments.flatMap({ $0 }) {
                for region in regions where !ids.contains(region.id) && region.bounds.contains(sample.coordinate) {
                    ids.insert(region.id)
                }
                if ids.count == regions.count { return ids }
            }
        }
        return ids
    }

    public static func expand(_ box: BoundingBox, meters: Double) -> BoundingBox {
        let dLat = meters / 111_000
        let dLon = meters / (111_000 * max(0.2, cos((box.south + box.north) / 2 * .pi / 180)))
        return BoundingBox(south: box.south - dLat, west: box.west - dLon, north: box.north + dLat, east: box.east + dLon)
    }

    public static func intersects(_ a: BoundingBox, _ b: BoundingBox) -> Bool {
        a.south <= b.north && b.south <= a.north && a.west <= b.east && b.west <= a.east
    }
}
