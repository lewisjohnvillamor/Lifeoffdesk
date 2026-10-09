import Foundation

/// Numbers shown after Finish. Every value is computed from accepted samples.
public struct WalkRecap: Hashable, Sendable {
    public var sessionID: UUID
    public var distanceMeters: Double
    public var activeDuration: TimeInterval
    public var acceptedSamples: Int
    public var segmentCount: Int
    /// Area newly revealed by this walk compared with all other walks; revisits add nothing.
    public var newlyRevealedSquareMeters: Double
    /// Distance walked outside every other walk's explored corridor ("new streets").
    public var newDistanceMeters: Double
    public var destinationName: String?
    public var wasRecovered: Bool

    public static func compute(session: WalkSession, exploration: Exploration, grid: ExplorationGrid,
                               now: Date) -> WalkRecap {
        let others = exploration.excluding(sessionID: session.id)
        var withThis = others
        withThis.merge(session)
        let before = grid.cells(for: others)
        let after = grid.cells(for: withThis)
        var newDistance = 0.0
        for segment in session.segments {
            for (a, b) in zip(segment, segment.dropFirst()) {
                // Judge short pieces so a long segment is not counted all-new or all-old.
                let length = Geo.distanceMeters(a.coordinate, b.coordinate)
                let pieces = max(1, Int((length / grid.cellSize).rounded(.up)))
                for i in 0..<pieces {
                    let t = (Double(i) + 0.5) / Double(pieces)
                    let mid = Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                         longitude: a.longitude + (b.longitude - a.longitude) * t)
                    if !before.contains(grid.cell(containing: mid)) { newDistance += length / Double(pieces) }
                }
            }
        }
        return WalkRecap(sessionID: session.id,
                         distanceMeters: session.distanceMeters,
                         activeDuration: session.activeDuration(at: now),
                         acceptedSamples: session.acceptedSampleCount,
                         segmentCount: session.segments.count,
                         newlyRevealedSquareMeters: grid.areaSquareMeters(after.subtracting(before)),
                         newDistanceMeters: newDistance,
                         destinationName: session.destinationName,
                         wasRecovered: session.wasRecovered)
    }
}

public enum Format {
    public static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.2f km", meters / 1000)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    public static func area(_ squareMeters: Double) -> String {
        if squareMeters < 10_000 { return "\(Int(squareMeters.rounded())) m²" }
        return String(format: "%.2f ha", squareMeters / 10_000)
    }
}
