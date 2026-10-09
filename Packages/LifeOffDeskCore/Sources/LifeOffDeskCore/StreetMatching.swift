import Foundation

/// One straight piece of a mapped street, in local metres.
public struct StreetSegment: Sendable {
    public var a: MeterPoint
    public var b: MeterPoint
    public var length: Double
    public var highway: String
}

/// Bundled road lines as segments with a coarse spatial index for nearest-street lookups.
/// Visual/matching context only, never a routing graph.
public final class StreetNetwork: @unchecked Sendable {
    public let projection: LocalProjection
    public let segments: [StreetSegment]
    private let index: [GridCell: [Int32]]
    private static let cellSize = 60.0

    public init(roads: [RoadContext.Road], origin: Coordinate) {
        projection = LocalProjection(origin: origin)
        var segments: [StreetSegment] = []
        var index: [GridCell: [Int32]] = [:]
        for road in roads where !road.r {
            let points = road.coordinates.map(projection.project)
            for (a, b) in zip(points, points.dropFirst()) {
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 0.5 else { continue }
                let id = Int32(segments.count)
                segments.append(StreetSegment(a: a, b: b, length: length, highway: road.h))
                let x0 = Int((min(a.x, b.x) / Self.cellSize).rounded(.down)), x1 = Int((max(a.x, b.x) / Self.cellSize).rounded(.down))
                let y0 = Int((min(a.y, b.y) / Self.cellSize).rounded(.down)), y1 = Int((max(a.y, b.y) / Self.cellSize).rounded(.down))
                for x in x0...x1 { for y in y0...y1 { index[GridCell(x: x, y: y), default: []].append(id) } }
            }
        }
        self.segments = segments
        self.index = index
    }

    /// Nearest segment within `tolerance` metres, optionally requiring a heading roughly parallel
    /// to the street (either direction). Returns the segment, position along it (0...1) and distance.
    public func nearest(to p: MeterPoint, heading: (dx: Double, dy: Double)?, tolerance: Double,
                        maxAngleDegrees: Double) -> (segment: Int, t: Double, distance: Double)? {
        let reach = Int((tolerance / Self.cellSize).rounded(.up))
        let cx = Int((p.x / Self.cellSize).rounded(.down)), cy = Int((p.y / Self.cellSize).rounded(.down))
        let minCos = cos(maxAngleDegrees * .pi / 180)
        var best: (Int, Double, Double)?
        var seen = Set<Int32>()
        for x in (cx - reach)...(cx + reach) {
            for y in (cy - reach)...(cy + reach) {
                for id in index[GridCell(x: x, y: y)] ?? [] where seen.insert(id).inserted {
                    let s = segments[Int(id)]
                    let dx = s.b.x - s.a.x, dy = s.b.y - s.a.y
                    let t = min(1, max(0, ((p.x - s.a.x) * dx + (p.y - s.a.y) * dy) / (s.length * s.length)))
                    let distance = hypot(s.a.x + t * dx - p.x, s.a.y + t * dy - p.y)
                    guard distance <= tolerance else { continue }
                    if let heading {
                        let hl = hypot(heading.dx, heading.dy)
                        if hl > 0 {
                            let cosine = abs((heading.dx * dx + heading.dy * dy) / (hl * s.length))
                            guard cosine >= minCos else { continue }
                        }
                    }
                    if best == nil || distance < best!.2 { best = (Int(id), t, distance) }
                }
            }
        }
        return best.map { (segment: $0.0, t: $0.1, distance: $0.2) }
    }

    public func point(on segment: Int, at meters: Double) -> MeterPoint {
        let s = segments[segment]
        let t = min(1, max(0, meters / s.length))
        return MeterPoint(x: s.a.x + (s.b.x - s.a.x) * t, y: s.a.y + (s.b.y - s.a.y) * t)
    }

    /// Segment indices with a point within `radius` of `center`.
    public func segments(near center: MeterPoint, radius: Double) -> [Int] {
        let reach = Int((radius / Self.cellSize).rounded(.up))
        let cx = Int((center.x / Self.cellSize).rounded(.down)), cy = Int((center.y / Self.cellSize).rounded(.down))
        var result = Set<Int32>()
        for x in (cx - reach)...(cx + reach) { for y in (cy - reach)...(cy + reach) {
            for id in index[GridCell(x: x, y: y)] ?? [] { result.insert(id) }
        } }
        return result.map(Int.init).filter { id in
            let s = segments[id]
            let mid = MeterPoint(x: (s.a.x + s.b.x) / 2, y: (s.a.y + s.b.y) / 2)
            return hypot(mid.x - center.x, mid.y - center.y) <= radius
        }
    }
}

/// Which 5 m pieces of which street segments have been walked. Derived from raw trails and the
/// current street data; never stored, so replacing map data only changes the matching.
public struct StreetCoverage: Sendable, Equatable {
    public static let binMeters = 5.0
    public var bins: [Int: Set<Int>] = [:]

    public init() {}

    public var isEmpty: Bool { bins.isEmpty }

    public mutating func merge(_ other: StreetCoverage) {
        for (segment, pieces) in other.bins { bins[segment, default: []].formUnion(pieces) }
    }

    public func coveredMeters(in network: StreetNetwork) -> Double {
        bins.reduce(0) { total, entry in total + meters(of: entry.value, segment: entry.key, network: network) }
    }

    /// Street length in this coverage that `prior` does not have.
    public func newMeters(comparedTo prior: StreetCoverage, network: StreetNetwork) -> Double {
        bins.reduce(0) { total, entry in
            total + meters(of: entry.value.subtracting(prior.bins[entry.key] ?? []), segment: entry.key, network: network)
        }
    }

    /// Covered stretches as polylines in local metres, split into new/old against `prior`.
    public func pieces(in network: StreetNetwork, prior: StreetCoverage? = nil) -> [(points: [MeterPoint], isNew: Bool)] {
        var result: [(points: [MeterPoint], isNew: Bool)] = []
        for (segment, covered) in bins {
            let seen = prior?.bins[segment] ?? []
            let length = network.segments[segment].length
            var runStart: Int?, runNew = true, last = -2
            func close(_ end: Int) {
                guard let start = runStart else { return }
                let from = Double(start) * Self.binMeters, to = min(length, Double(end + 1) * Self.binMeters)
                result.append(([network.point(on: segment, at: from), network.point(on: segment, at: to)], runNew))
            }
            for bin in covered.sorted() {
                let isNew = !seen.contains(bin)
                if bin != last + 1 || isNew != runNew { close(last); runStart = bin; runNew = isNew }
                last = bin
            }
            close(last)
        }
        return result
    }

    private func meters(of pieces: Set<Int>, segment: Int, network: StreetNetwork) -> Double {
        let length = network.segments[segment].length
        let full = Int((length / Self.binMeters).rounded(.down))
        return pieces.reduce(0) { $0 + ($1 < full ? Self.binMeters : max(0, length - Double(full) * Self.binMeters)) }
    }
}

/// Matches accepted GPS samples to nearby, roughly parallel streets.
public enum StreetMatcher {
    public static let toleranceMeters = 25.0
    public static let maxAngleDegrees = 40.0
    /// Off-street stretches shorter than this (intersections, GPS wobble) are dropped.
    public static let minimumUnmatchedMeters = 20.0
    private static let stepMeters = 4.0

    public struct Result: Sendable {
        public var coverage: StreetCoverage
        /// Accepted stretches with no street nearby (plazas, unmapped paths), in coordinates.
        public var unmatched: [[Coordinate]]
    }

    public static func match(_ segments: [[TrackSample]], network: StreetNetwork) -> Result {
        var coverage = StreetCoverage()
        var unmatched: [[Coordinate]] = []
        let projection = network.projection
        for segment in segments {
            let points = segment.map { projection.project($0.coordinate) }
            var previous: (segment: Int, bin: Int)?
            var offRun: [MeterPoint] = []
            func flushOff() {
                let length = zip(offRun, offRun.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                if offRun.count >= 2 && length >= minimumUnmatchedMeters {
                    unmatched.append(offRun.map(projection.unproject))
                }
                offRun = []
            }
            if points.count == 1, let only = points.first {
                if let hit = network.nearest(to: only, heading: nil, tolerance: toleranceMeters, maxAngleDegrees: 90) {
                    coverage.bins[hit.segment, default: []].insert(bin(hit, network))
                }
                continue
            }
            for (a, b) in zip(points, points.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let length = hypot(dx, dy)
                let steps = max(1, Int((length / stepMeters).rounded(.up)))
                let heading: (dx: Double, dy: Double)? = length >= 2 ? (dx, dy) : nil
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let p = MeterPoint(x: a.x + dx * t, y: a.y + dy * t)
                    if let hit = network.nearest(to: p, heading: heading, tolerance: toleranceMeters,
                                                 maxAngleDegrees: maxAngleDegrees) {
                        flushOff()
                        let current = bin(hit, network)
                        // Fill the bins between consecutive hits on the same segment so fast fixes leave no gaps.
                        if let previous, previous.segment == hit.segment {
                            for fill in min(previous.bin, current)...max(previous.bin, current) {
                                coverage.bins[hit.segment, default: []].insert(fill)
                            }
                        } else {
                            coverage.bins[hit.segment, default: []].insert(current)
                        }
                        previous = (hit.segment, current)
                    } else {
                        previous = nil
                        if offRun.last.map({ hypot($0.x - p.x, $0.y - p.y) > 0.1 }) ?? true { offRun.append(p) }
                    }
                }
            }
            flushOff()
        }
        return Result(coverage: coverage, unmatched: unmatched)
    }

    private static func bin(_ hit: (segment: Int, t: Double, distance: Double), _ network: StreetNetwork) -> Int {
        let length = network.segments[hit.segment].length
        let maxBin = max(0, Int(((length - 0.001) / StreetCoverage.binMeters).rounded(.down)))
        return min(maxBin, Int((hit.t * length / StreetCoverage.binMeters).rounded(.down)))
    }
}

/// Turns street matches into what the map draws.
public enum StreetReveal {
    /// Paper-island width along matched streets (metres, total).
    public static let ribbonWidthMeters = 40.0

    /// Matched street pieces plus unmatched raw stretches, tagged by adventure.
    public static func exploration(coverage: [UUID: StreetCoverage], unmatched: [UUID: [[Coordinate]]],
                                   network: StreetNetwork, include: Set<UUID>? = nil) -> Exploration {
        var exploration = Exploration(revealWidthMeters: ribbonWidthMeters)
        for (id, walkCoverage) in coverage where include?.contains(id) ?? true {
            for piece in walkCoverage.pieces(in: network) {
                exploration.paths.append(ExploredPath(sessionID: id, points: piece.points.map(network.projection.unproject)))
            }
        }
        for (id, runs) in unmatched where include?.contains(id) ?? true {
            for run in runs { exploration.paths.append(ExploredPath(sessionID: id, points: run)) }
        }
        return exploration
    }

    /// Live/replay trail: matched pieces split new (dotted) vs walked before (solid), plus raw
    /// off-street stretches drawn as new.
    public static func trailRuns(_ segments: [[TrackSample]], prior: StreetCoverage, network: StreetNetwork) -> [TrailRun] {
        let matched = StreetMatcher.match(segments, network: network)
        var runs = matched.coverage.pieces(in: network, prior: prior).map {
            TrailRun(points: $0.points.map(network.projection.unproject), isNew: $0.isNew)
        }
        runs += matched.unmatched.map { TrailRun(points: $0, isNew: true) }
        return runs
    }
}

extension AdventureSuggester {
    /// Street frontiers from the street network: nearby segments with no walked pieces, grouped
    /// by compass sector, richest-per-distance first.
    public static func frontiers(from origin: Coordinate, network: StreetNetwork, coverage: StreetCoverage,
                                 searchRadius: Double = 1500, minimumMeters: Double = 300, limit: Int = 2) -> [AdventureIdea] {
        let center = network.projection.project(origin)
        var roads: [[Coordinate]] = []
        for id in network.segments(near: center, radius: searchRadius) where coverage.bins[id] == nil {
            let s = network.segments[id]
            roads.append([network.projection.unproject(s.a), network.projection.unproject(s.b)])
        }
        // Reuse the sector logic with nothing marked explored (uncovered segments only).
        let grid = ExplorationGrid(origin: network.projection.origin)
        return frontiers(from: origin, roads: roads, explored: [], grid: grid, searchRadius: searchRadius,
                         minimumMeters: minimumMeters, limit: limit)
    }
}
