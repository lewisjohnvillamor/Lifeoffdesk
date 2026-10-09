import Foundation
import LifeOffDeskCore

/// What the help sheet shows: where you are and the nearest help places in the offline data.
struct HelpSnapshot: Sendable {
    var position: Coordinate?
    /// Coordinates plus the nearest named place, to read to a dispatcher or text to someone.
    var locationText: String?
    var places: [HelpKind: [HelpPlace]] = [:]
}

extension AppModel {
    /// Search radius used to stream city packs in before looking for help places.
    static let helpReachMeters = 5000.0

    /// Nearest police stations, hospitals and fire stations from the loaded OSM data. Deterministic,
    /// offline; distances along mapped streets when the street graph reaches them.
    func nearbyHelp() async -> HelpSnapshot {
        refreshIdleLocation()
        guard let position = currentPosition else { return HelpSnapshot() }
        await ensureChunks(around: [position], reach: Self.helpReachMeters)
        guard let catalog = content?.catalog else { return HelpSnapshot(position: position) }
        let graph = walkingGraph
        let accuracy = lastFix?.horizontalAccuracy
        return await Task.detached(priority: .userInitiated) {
            HelpSnapshot(position: position,
                         locationText: HelpPlaces.locationDescription(position, accuracyMeters: accuracy, catalog: catalog),
                         places: HelpPlaces.nearest(in: catalog, from: position, graph: graph))
        }.value
    }
}
