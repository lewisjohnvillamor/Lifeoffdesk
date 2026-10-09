import Foundation

/// Places an adventure actually passed: catalogue records within `radius` metres of an accepted
/// trail point. Computed from GPS; it never claims the user went inside or that a place was open.
public enum Discovery {
    public static let defaultRadiusMeters: Double = 40

    public static func placesPassed(by session: WalkSession, in catalog: PlaceCatalog,
                                    radius: Double = defaultRadiusMeters) -> [Place] {
        let samples = session.segments.flatMap { $0 }
        guard !samples.isEmpty else { return [] }
        // Cheap bounding-box prefilter before exact distance checks.
        let lats = samples.map(\.latitude), lons = samples.map(\.longitude)
        let pad = radius / 111_000 * 1.5
        let box = BoundingBox(south: lats.min()! - pad, west: lons.min()! - pad * 1.1,
                              north: lats.max()! + pad, east: lons.max()! + pad * 1.1)
        return catalog.places.filter { place in
            guard box.contains(place.coordinate) else { return false }
            return samples.contains { Geo.distanceMeters($0.coordinate, place.coordinate) <= radius }
        }
    }
}

/// A suggested next adventure. Targets are real records or computed street frontiers; the copy
/// says which. Distances are straight-line unless `street` is filled in.
public struct AdventureIdea: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// A catalogue place the user has not passed yet.
        case undiscoveredPlace(Place)
        /// A cluster of street length the user has never walked.
        case frontier(unexploredMeters: Double, bearingDegrees: Double)
    }

    public var kind: Kind
    public var target: Coordinate
    public var straightLineMeters: Double
    /// Distance along bundled streets, filled in by the app when a walking graph is ready.
    public var street: StreetDistance? = nil

    public var id: String {
        switch kind {
        case let .undiscoveredPlace(place): return "place:\(place.id)"
        case .frontier: return "frontier:\(Int(target.latitude * 1e5)):\(Int(target.longitude * 1e5))"
        }
    }
}

public enum AdventureSuggester {
    /// Street frontiers: road segments within `searchRadius` whose midpoints are outside the
    /// explored cells, grouped by compass sector; returns the richest nearby sectors first.
    public static func frontiers(from origin: Coordinate, roads: [[Coordinate]], explored: Set<GridCell>,
                                 grid: ExplorationGrid, searchRadius: Double = 1500, minimumMeters: Double = 300,
                                 limit: Int = 2) -> [AdventureIdea] {
        struct Sector { var meters = 0.0; var sumLat = 0.0; var sumLon = 0.0; var weight = 0.0; var mids: [Coordinate] = [] }
        var sectors = [Int: Sector]()
        for road in roads {
            for (a, b) in zip(road, road.dropFirst()) {
                let mid = Coordinate(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
                let distance = Geo.distanceMeters(origin, mid)
                guard distance <= searchRadius, distance >= 60 else { continue }
                guard !explored.contains(grid.cell(containing: mid)) else { continue }
                let length = Geo.distanceMeters(a, b)
                let sectorIndex = Int(((bearing(from: origin, to: mid) + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
                var sector = sectors[sectorIndex] ?? Sector()
                sector.meters += length
                // Weight nearer segments more so the target sits at the near edge of the fog.
                let w = length / max(distance, 50)
                sector.sumLat += mid.latitude * w; sector.sumLon += mid.longitude * w; sector.weight += w
                sector.mids.append(mid)
                sectors[sectorIndex] = sector
            }
        }
        let ideas = sectors.values.filter { $0.meters >= minimumMeters && $0.weight > 0 }.map { sector -> AdventureIdea in
            let centroid = Coordinate(latitude: sector.sumLat / sector.weight, longitude: sector.sumLon / sector.weight)
            // The centroid can fall inside a block; the target is the unexplored street point nearest to it.
            let target = sector.mids.min { Geo.distanceMeters($0, centroid) < Geo.distanceMeters($1, centroid) } ?? centroid
            return AdventureIdea(kind: .frontier(unexploredMeters: sector.meters, bearingDegrees: bearing(from: origin, to: target)),
                                 target: target, straightLineMeters: Geo.distanceMeters(origin, target))
        }
        // More unexplored length per metre of approach first.
        return Array(ideas.sorted { score($0) > score($1) }.prefix(limit))
    }

    /// Undiscovered catalogue places, preferring the user's favourite categories, nearest first.
    public static func undiscoveredPlaces(from origin: Coordinate, catalog: PlaceCatalog, discoveredIDs: Set<String>,
                                          preferred: [PlaceCategory], radius: Double = 2000, limit: Int = 2) -> [AdventureIdea] {
        let candidates = catalog.places.filter { !discoveredIDs.contains($0.id) }
            .map { ($0, Geo.distanceMeters(origin, $0.coordinate)) }
            .filter { $0.1 <= radius }
        let ranked = candidates.sorted { a, b in
            let pa = preferred.firstIndex(of: a.0.category) ?? preferred.count
            let pb = preferred.firstIndex(of: b.0.category) ?? preferred.count
            if pa != pb { return pa < pb }
            if a.1 != b.1 { return a.1 < b.1 }
            return a.0.id < b.0.id
        }
        return ranked.prefix(limit).map {
            AdventureIdea(kind: .undiscoveredPlace($0.0), target: $0.0.coordinate, straightLineMeters: $0.1)
        }
    }

    /// Categories ordered by how often they appear among discovered or chosen places.
    public static func favouriteCategories(_ places: [Place]) -> [PlaceCategory] {
        var counts = [PlaceCategory: Int]()
        for place in places { counts[place.category, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }.map(\.key)
    }

    public static func compassWord(_ degrees: Double) -> String {
        ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][
            Int(((degrees + 22.5).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45) % 8]
    }

    private static func score(_ idea: AdventureIdea) -> Double {
        guard case let .frontier(meters, _) = idea.kind else { return 0 }
        return meters / max(idea.straightLineMeters, 100)
    }

    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension Place {
    /// A computed destination for a street frontier. Not a venue: no facts, clearly labelled.
    public static func frontierTarget(at coordinate: Coordinate, label: String) -> Place {
        Place(id: "frontier:\(Int(coordinate.latitude * 1e5)):\(Int(coordinate.longitude * 1e5))", name: label,
              latitude: coordinate.latitude, longitude: coordinate.longitude, category: .other, tags: [],
              sourceURL: "", retrievedAt: "", verificationStatus: "computed-frontier", positionMethod: "computed",
              budgetPHP: nil, quietness: nil, openingHours: nil, sourceOpeningHours: nil, sourceAccess: nil,
              sourceFee: nil, sourceLevel: nil, sourceCuisine: nil)
    }

    public var isFrontier: Bool { verificationStatus == "computed-frontier" }
}
