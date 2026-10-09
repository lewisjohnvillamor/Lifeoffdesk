import Foundation

public struct ExploredPath: Codable, Hashable, Sendable {
    public var sessionID: UUID
    public var points: [Coordinate]

    public init(sessionID: UUID, points: [Coordinate]) {
        self.sessionID = sessionID
        self.points = points
    }
}

/// Cumulative explored corridor, stored as accepted geographic paths so it does not
/// depend on any basemap version. Render caches are rebuilt from these paths.
public struct Exploration: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Total corridor width; half of it is revealed on each side of the path.
    public var revealWidthMeters: Double
    public var paths: [ExploredPath]

    public init(revealWidthMeters: Double = 25, paths: [ExploredPath] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.revealWidthMeters = revealWidthMeters
        self.paths = paths
    }

    public var sourceSessionIDs: Set<UUID> { Set(paths.map(\.sessionID)) }

    /// Replaces this session's contribution; calling it repeatedly is idempotent.
    public mutating func merge(_ session: WalkSession) {
        paths.removeAll { $0.sessionID == session.id }
        paths += session.segments.filter { !$0.isEmpty }.map {
            ExploredPath(sessionID: session.id, points: $0.map(\.coordinate))
        }
    }

    public func excluding(sessionID: UUID) -> Exploration {
        var copy = self
        copy.paths.removeAll { $0.sessionID == sessionID }
        return copy
    }
}

public struct GridCell: Hashable, Sendable {
    public var x: Int
    public var y: Int
}

/// Rasterises the explored corridor into fixed-size cells so revisits never count twice.
public struct ExplorationGrid: Sendable {
    public let projection: LocalProjection
    public let cellSize: Double

    public init(origin: Coordinate, cellSize: Double = 2.5) {
        projection = LocalProjection(origin: origin)
        self.cellSize = cellSize
    }

    public func cells(for exploration: Exploration) -> Set<GridCell> {
        let radius = exploration.revealWidthMeters / 2
        var cells = Set<GridCell>()
        for path in exploration.paths {
            let points = path.points.map(projection.project)
            guard let first = points.first else { continue }
            stamp(first, radius: radius, into: &cells)
            for (a, b) in zip(points, points.dropFirst()) {
                let length = hypot(b.x - a.x, b.y - a.y)
                let steps = max(1, Int((length / (cellSize / 2)).rounded(.up)))
                for step in 1...steps {
                    let t = Double(step) / Double(steps)
                    stamp(MeterPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), radius: radius, into: &cells)
                }
            }
        }
        return cells
    }

    public func areaSquareMeters(_ cells: Set<GridCell>) -> Double {
        Double(cells.count) * cellSize * cellSize
    }

    private func stamp(_ center: MeterPoint, radius: Double, into cells: inout Set<GridCell>) {
        let minX = Int(((center.x - radius) / cellSize).rounded(.down))
        let maxX = Int(((center.x + radius) / cellSize).rounded(.down))
        let minY = Int(((center.y - radius) / cellSize).rounded(.down))
        let maxY = Int(((center.y + radius) / cellSize).rounded(.down))
        for x in minX...maxX {
            for y in minY...maxY {
                let cx = (Double(x) + 0.5) * cellSize, cy = (Double(y) + 0.5) * cellSize
                if hypot(cx - center.x, cy - center.y) <= radius {
                    cells.insert(GridCell(x: x, y: y))
                }
            }
        }
    }
}
