import Foundation
import LifeOffDeskCore

/// One bundled region: manifest, road context and (for full-detail regions) a place catalog.
struct RegionPack {
    let region: RegionManifest
    let roads: RoadContext
    let catalog: PlaceCatalog?
}

/// Bundled offline starter regions (Makati CBD, Muntinlupa, Metro Manila main roads).
struct StarterContent {
    let packs: [RegionPack]
    /// Union of every region's places; search filters by distance from the user.
    let catalog: PlaceCatalog

    /// First indexed region: map origin and fallback distance origin.
    var region: RegionManifest { packs[0].region }

    enum Coverage: Equatable {
        case detailed(String)
        case mainRoadsOnly(String)
        case outside
    }

    func coverage(at coordinate: Coordinate) -> Coverage {
        if let pack = packs.first(where: { $0.region.hasFullDetail && $0.region.bounds.contains(coordinate) }) {
            return .detailed(pack.region.name)
        }
        if let pack = packs.first(where: { $0.region.bounds.contains(coordinate) }) {
            return .mainRoadsOnly(pack.region.name)
        }
        return .outside
    }

    enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        case noCatalog
        var description: String {
            switch self {
            case let .missing(name): return "Bundled starter file \(name) is missing"
            case .noCatalog: return "No bundled region has a place catalog"
            }
        }
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> StarterContent {
        let decoder = JSONDecoder()
        func url(_ name: String, in directory: String) throws -> URL {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: directory) else {
                throw LoadError.missing("\(directory)/\(name).json")
            }
            return url
        }
        let index = try decoder.decode(RegionIndex.self, from: Data(contentsOf: url("regions", in: "StarterData")))
        var packs: [RegionPack] = []
        for entry in index.regions {
            let directory = "StarterData/\(entry.id)"
            let region = try decoder.decode(RegionManifest.self, from: Data(contentsOf: url("region", in: directory)))
            let roads = try decoder.decode(RoadContext.self, from: Data(contentsOf: url("roads", in: directory)))
            let catalog = region.hasFullDetail
                ? try PlaceCatalog.decode(Data(contentsOf: url("places", in: directory))) : nil
            packs.append(RegionPack(region: region, roads: roads, catalog: catalog))
        }
        guard !packs.isEmpty, let catalog = PlaceCatalog.merged(packs.compactMap(\.catalog)) else {
            throw LoadError.noCatalog
        }
        return StarterContent(packs: packs, catalog: catalog)
    }
}
