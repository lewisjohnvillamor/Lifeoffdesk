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
    /// Provisional total corridor width (25 m each side of the path); tune outdoors.
    public static let defaultRevealWidthMeters: Double = 50

    public var schemaVersion: Int
    /// Total corridor width; half of it is revealed on each side of the path.
    public var revealWidthMeters: Double
    public var paths: [ExploredPath]

    public init(revealWidthMeters: Double = Exploration.defaultRevealWidthMeters, paths: [ExploredPath] = []) {
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

/// Axis-aligned rectangle in local metres.
public struct MeterRect: Hashable, Sendable {
    public var minX: Double, minY: Double, maxX: Double, maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }

    public func padded(by d: Double) -> MeterRect {
        MeterRect(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d)
    }

    public func intersection(_ other: MeterRect) -> MeterRect? {
        let r = MeterRect(minX: max(minX, other.minX), minY: max(minY, other.minY),
                          maxX: min(maxX, other.maxX), maxY: min(maxY, other.maxY))
        return r.minX <= r.maxX && r.minY <= r.maxY ? r : nil
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

    /// Cells within half the corridor width of any accepted segment. With `region`, only
    /// segments touching that metre-space rectangle are rasterised (used for fast recaps).
    public func cells(for exploration: Exploration, region: MeterRect? = nil) -> Set<GridCell> {
        let radius = exploration.revealWidthMeters / 2
        var cells = Set<GridCell>()
        for path in exploration.paths {
            let points = path.points.map(projection.project)
            guard let first = points.first else { continue }
            if points.count == 1 {
                rasterize(first, first, radius: radius, region: region, into: &cells)
            }
            for (a, b) in zip(points, points.dropFirst()) {
                rasterize(a, b, radius: radius, region: region, into: &cells)
            }
        }
        return cells
    }

    /// Bounding rectangle (metres) of a session's accepted samples, padded.
    public func bounds(of session: WalkSession, padding: Double) -> MeterRect? {
        let points = session.segments.flatMap { $0 }.map { projection.project($0.coordinate) }
        guard let first = points.first else { return nil }
        var rect = MeterRect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in points {
            rect.minX = min(rect.minX, p.x); rect.maxX = max(rect.maxX, p.x)
            rect.minY = min(rect.minY, p.y); rect.maxY = max(rect.maxY, p.y)
        }
        return rect.padded(by: padding)
    }

    /// Marks cells whose centre lies within `radius` of segment ab (a capsule).
    private func rasterize(_ a: MeterPoint, _ b: MeterPoint, radius: Double, region: MeterRect?,
                           into cells: inout Set<GridCell>) {
        var box = MeterRect(minX: min(a.x, b.x), minY: min(a.y, b.y), maxX: max(a.x, b.x), maxY: max(a.y, b.y))
            .padded(by: radius)
        if let region {
            guard let clipped = box.intersection(region) else { return }
            box = clipped
        }
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let r2 = radius * radius
        let x0 = Int((box.minX / cellSize).rounded(.down)), x1 = Int((box.maxX / cellSize).rounded(.down))
        let y0 = Int((box.minY / cellSize).rounded(.down)), y1 = Int((box.maxY / cellSize).rounded(.down))
        guard x0 <= x1, y0 <= y1 else { return }
        for x in x0...x1 {
            let cx = (Double(x) + 0.5) * cellSize
            for y in y0...y1 {
                let cy = (Double(y) + 0.5) * cellSize
                var t = lengthSquared > 0 ? ((cx - a.x) * dx + (cy - a.y) * dy) / lengthSquared : 0
                t = min(1, max(0, t))
                let px = a.x + t * dx - cx, py = a.y + t * dy - cy
                if px * px + py * py <= r2 { cells.insert(GridCell(x: x, y: y)) }
            }
        }
    }

    public func cell(containing coordinate: Coordinate) -> GridCell {
        let p = projection.project(coordinate)
        return GridCell(x: Int((p.x / cellSize).rounded(.down)), y: Int((p.y / cellSize).rounded(.down)))
    }

    public func areaSquareMeters(_ cells: Set<GridCell>) -> Double {
        Double(cells.count) * cellSize * cellSize
    }

}
