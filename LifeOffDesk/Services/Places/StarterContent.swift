import Foundation
import LifeOffDeskCore

/// One bundled region: manifest, road context and (for full-detail regions) a place catalog.
struct RegionPack: Sendable {
    let region: RegionManifest
    let roads: RoadContext
    let catalog: PlaceCatalog?
    /// Reviewed access facts; missing on older packs means no evidence (unknown).
    var evidence: EvidenceSidecar? = nil
}

/// Every bundled region. Only the small manifests stay in memory; a city's streets and places
/// are decoded when the app needs them (see `RegionChunks`) and can be freed again.
final class RegionLibrary: @unchecked Sendable {
    let manifests: [RegionManifest]
    /// First indexed region: map origin and fallback distance origin (never unloaded).
    var primary: RegionManifest { manifests[0] }
    var detailed: [RegionManifest] { manifests.filter(\.hasFullDetail) }
    /// Context packs (Metro Manila main roads) stay loaded so recording works anywhere.
    var contextIDs: [String] { manifests.filter { !$0.hasFullDetail }.map(\.id) }

    private let bundle: Bundle

    enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        case empty
        var description: String {
            switch self {
            case let .missing(name): return "Bundled starter file \(name) is missing"
            case .empty: return "No bundled regions"
            }
        }
    }

    private init(bundle: Bundle, manifests: [RegionManifest]) {
        self.bundle = bundle
        self.manifests = manifests
    }

    /// Reads the region index and each manifest only (a few KB).
    static func open(_ bundle: Bundle = .main) throws -> RegionLibrary {
        let decoder = JSONDecoder()
        let index = try decoder.decode(RegionIndex.self, from: Data(contentsOf: url(bundle, "regions", in: "StarterData")))
        let manifests = try index.regions.map { entry in
            try decoder.decode(RegionManifest.self,
                               from: Data(contentsOf: url(bundle, "region", in: "StarterData/\(entry.id)")))
        }
        guard !manifests.isEmpty else { throw LoadError.empty }
        return RegionLibrary(bundle: bundle, manifests: manifests)
    }

    private static func url(_ bundle: Bundle, _ name: String, in directory: String) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: directory) else {
            throw LoadError.missing("\(directory)/\(name).json")
        }
        return url
    }

    /// Decodes one region's streets, places and evidence. Call off the main thread.
    func loadPack(_ id: String) throws -> (pack: RegionPack, issues: [String]) {
        guard let region = manifests.first(where: { $0.id == id }) else { throw LoadError.missing(id) }
        let directory = "StarterData/\(id)"
        let decoder = JSONDecoder()
        let roads = try decoder.decode(RoadContext.self, from: Data(contentsOf: Self.url(bundle, "roads", in: directory)))
        let catalog = region.hasFullDetail
            ? try PlaceCatalog.decode(Data(contentsOf: Self.url(bundle, "places", in: directory))) : nil
        var evidence: EvidenceSidecar?
        var issues: [String] = []
        if let url = bundle.url(forResource: "place-facts", withExtension: "json", subdirectory: directory) {
            do { evidence = try EvidenceSidecar.decode(Data(contentsOf: url)) } catch {
                // Fails closed (no evidence = hard access requirements match nothing) but visibly.
                issues.append("\(id)/place-facts.json unreadable: \(error)")
            }
        }
        return (RegionPack(region: region, roads: roads, catalog: catalog, evidence: evidence), issues)
    }

    /// Coverage from manifests, so it is right even for cities not loaded yet.
    func coverage(at coordinate: Coordinate) -> StarterContent.Coverage {
        if let region = manifests.first(where: { $0.hasFullDetail && $0.bounds.contains(coordinate) }) {
            return .detailed(region.name)
        }
        if let region = manifests.first(where: { $0.bounds.contains(coordinate) }) {
            return .mainRoadsOnly(region.name)
        }
        return .outside
    }
}

/// The regions currently in memory: what the map draws, what street matching and the planner use.
struct StarterContent: Sendable {
    let library: RegionLibrary
    let packs: [RegionPack]
    /// Union of the loaded regions' places; search filters by distance from the user.
    let catalog: PlaceCatalog
    /// Optional files that exist but could not be read (shown in diagnostics, never ignored silently).
    var issues: [String] = []

    var loadedIDs: Set<String> { Set(packs.map(\.region.id)) }

    /// Every loaded access fact (empty until reviewed facts are added).
    var evidence: [EvidenceFactV1] { packs.flatMap { $0.evidence?.facts ?? [] } }

    /// Map origin and fallback distance origin; fixed even when the primary city is not loaded.
    var region: RegionManifest { library.primary }

    /// Roads for street matching: detailed packs, plus context roads outside every detailed area
    /// (context packs repeat detailed roads; the detailed copy wins). Uses all detailed manifests
    /// so an unloaded city's main roads are not matched twice once it loads.
    var matchingRoads: [RoadContext.Road] {
        let loadedDetailed = packs.filter { $0.region.hasFullDetail }.map(\.region.bounds)
        // Overlapping city boxes (e.g. Makati CBD inside Makati) carry the same OSM ways; keep each
        // once or "new streets" would count a street twice.
        var seen = Set<[Double]>()
        return packs.flatMap { pack -> [RoadContext.Road] in
            let roads = pack.roads.roads.filter { seen.insert($0.c).inserted }
            guard !pack.region.hasFullDetail else { return roads }
            return roads.filter { road in
                let c = road.coordinates
                guard let mid = c.dropFirst(c.count / 2).first else { return false }
                return !loadedDetailed.contains { $0.contains(mid) }
            }
        }
    }

    enum Coverage: Equatable {
        case detailed(String)
        case mainRoadsOnly(String)
        case outside
    }

    func coverage(at coordinate: Coordinate) -> Coverage { library.coverage(at: coordinate) }

    init(library: RegionLibrary, packs: [RegionPack], issues: [String]) {
        self.library = library
        // Keep index order so the primary region and context packs behave as before.
        let order = Dictionary(uniqueKeysWithValues: library.manifests.enumerated().map { ($1.id, $0) })
        self.packs = packs.sorted { (order[$0.region.id] ?? .max) < (order[$1.region.id] ?? .max) }
        catalog = PlaceCatalog.merged(self.packs.compactMap(\.catalog)) ?? PlaceCatalog.empty
        self.issues = issues
    }
}

extension PlaceCatalog {
    /// No city with places loaded yet.
    static var empty: PlaceCatalog {
        PlaceCatalog(schemaVersion: 1, regionID: "none", attribution: "© OpenStreetMap contributors",
                     licenseURL: "https://www.openstreetmap.org/copyright", retrievedAt: "", sourceTimestamp: nil,
                     selectionRule: "No region loaded yet", places: [])
    }
}
