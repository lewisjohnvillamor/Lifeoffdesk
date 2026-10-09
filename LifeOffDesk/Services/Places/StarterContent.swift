import Foundation
import LifeOffDeskCore

/// Bundled offline starter area: region manifest, reviewed-or-not place catalog and road context.
struct StarterContent {
    let region: RegionManifest
    let catalog: PlaceCatalog
    let roads: RoadContext

    enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        var description: String {
            switch self {
            case let .missing(name): return "Bundled starter file \(name) is missing"
            }
        }
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> StarterContent {
        func data(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "StarterData") else {
                throw LoadError.missing("\(name).json")
            }
            return try Data(contentsOf: url)
        }
        let decoder = JSONDecoder()
        return StarterContent(region: try decoder.decode(RegionManifest.self, from: data("region")),
                              catalog: try PlaceCatalog.decode(data("places")),
                              roads: try decoder.decode(RoadContext.self, from: data("roads")))
    }
}
