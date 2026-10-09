import Foundation

/// Lifetime and per-walk numbers, computed chronologically: each walk's "new" distance and
/// area are measured only against walks that started before it, so later walks never
/// shrink an earlier walk's numbers. Summing newly revealed areas gives the exact union area.
public struct WalkStats: Sendable {
    public var recaps: [UUID: WalkRecap]
    public var totalDistanceMeters: Double
    public var totalNewDistanceMeters: Double
    public var exploredSquareMeters: Double
    public var walkCount: Int
    public var firstWalkAt: Date?

    public static let empty = WalkStats(recaps: [:], totalDistanceMeters: 0, totalNewDistanceMeters: 0,
                                        exploredSquareMeters: 0, walkCount: 0, firstWalkAt: nil)

    public static func compute(walks: [WalkSession], grid: ExplorationGrid,
                               revealWidthMeters: Double = Exploration.defaultRevealWidthMeters) -> WalkStats {
        let ordered = walks.sorted { $0.startedAt < $1.startedAt }
        var earlier = Exploration(revealWidthMeters: revealWidthMeters)
        var stats = WalkStats.empty
        for walk in ordered {
            let recap = WalkRecap.compute(session: walk, exploration: earlier, grid: grid, now: walk.endedAt ?? walk.startedAt)
            stats.recaps[walk.id] = recap
            stats.totalDistanceMeters += recap.distanceMeters
            stats.totalNewDistanceMeters += recap.newDistanceMeters
            stats.exploredSquareMeters += recap.newlyRevealedSquareMeters
            earlier.merge(walk)
        }
        stats.walkCount = ordered.count
        stats.firstWalkAt = ordered.first?.startedAt
        return stats
    }

    /// Recaps of walks that started inside [start, end).
    public func recaps(in walks: [WalkSession], from start: Date, to end: Date) -> [WalkRecap] {
        walks.filter { $0.startedAt >= start && $0.startedAt < end }.compactMap { recaps[$0.id] }
    }
}
