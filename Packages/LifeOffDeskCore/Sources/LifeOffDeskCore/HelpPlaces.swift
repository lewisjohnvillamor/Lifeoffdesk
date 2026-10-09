import Foundation

/// Kinds of place someone may need in trouble, read from the OSM kind of bundled places.
public enum HelpKind: String, CaseIterable, Sendable {
    case police, hospital, fireStation

    public init?(sourceKind: String?) {
        switch sourceKind {
        case "police": self = .police
        case "hospital": self = .hospital
        case "fire_station": self = .fireStation
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .police: return "Police stations"
        case .hospital: return "Hospitals"
        case .fireStation: return "Fire stations"
        }
    }
}

/// One nearby help place with its distance (street distance when the graph reaches it).
public struct HelpPlace: Sendable, Identifiable {
    public var place: Place
    public var kind: HelpKind
    public var street: StreetDistance?
    public var straightLineMeters: Double
    public var id: String { place.id }

    /// Street metres when known, otherwise straight-line (always labelled which by `PlannerCopy.distanceText`).
    public var sortMeters: Double { street?.meters ?? straightLineMeters }
}

/// Deterministic "nearest help" lookup over the loaded offline catalog. No AI, no network.
/// The places are unreviewed OSM records: they may have moved or closed, so the app says so.
public enum HelpPlaces {
    /// Places farther than this in a straight line are not listed.
    public static let maxStraightMeters = 10_000.0

    public static func nearest(in catalog: PlaceCatalog, from origin: Coordinate, graph: WalkingGraph?,
                               perKind: Int = 3) -> [HelpKind: [HelpPlace]] {
        var candidates: [HelpKind: [HelpPlace]] = [:]
        for place in catalog.places {
            guard let kind = HelpKind(sourceKind: place.sourceKind) else { continue }
            let meters = Geo.distanceMeters(origin, place.coordinate)
            guard meters <= maxStraightMeters else { continue }
            candidates[kind, default: []].append(HelpPlace(place: place, kind: kind, street: nil, straightLineMeters: meters))
        }
        // Street distances for the closest few of each kind, in one search.
        var shortlist = candidates.mapValues { Array($0.sorted { ($0.straightLineMeters, $0.id) < ($1.straightLineMeters, $1.id) }.prefix(perKind * 3)) }
        if let graph {
            let all = HelpKind.allCases.flatMap { shortlist[$0] ?? [] }
            let streets = graph.distances(from: origin, to: all.map(\.place.coordinate), maxMeters: maxStraightMeters * 2)
            var byID: [String: StreetDistance] = [:]
            for (help, street) in zip(all, streets) { byID[help.id] = street }
            shortlist = shortlist.mapValues { list in list.map { var h = $0; h.street = byID[h.id]; return h } }
        }
        return shortlist.mapValues { list in
            Array(list.sorted { ($0.sortMeters, $0.id) < ($1.sortMeters, $1.id) }.prefix(perKind))
        }
    }

    /// A short spoken/written location for a dispatcher: coordinates plus the nearest named place.
    public static func locationDescription(_ position: Coordinate, accuracyMeters: Double?, catalog: PlaceCatalog) -> String {
        var text = String(format: "%.5f, %.5f", position.latitude, position.longitude)
        if let accuracyMeters { text += " (±\(Int(accuracyMeters.rounded())) m)" }
        let nearest = catalog.places
            .map { ($0, Geo.distanceMeters(position, $0.coordinate)) }
            .filter { $0.1 <= 200 }
            .min { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
        if let (place, meters) = nearest { text += " · about \(Int(meters.rounded())) m from \(place.name)" }
        return text
    }
}
