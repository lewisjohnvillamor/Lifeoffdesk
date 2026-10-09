import Foundation

/// Distance along bundled streets from one point to another.
public struct StreetDistance: Hashable, Sendable {
    /// Street length plus the short straight approaches to and from the nearest street node.
    public var meters: Double
    /// The shortest path uses a way OSM marks private/no-access (gated villages, service roads).
    public var throughRestricted: Bool

    public init(meters: Double, throughRestricted: Bool) {
        self.meters = meters
        self.throughRestricted = throughRestricted
    }

    /// Rough walking minutes at 4.5 km/h. An estimate, never a promise.
    public var walkingMinutes: Int { max(1, Int((meters / 75).rounded())) }
}

/// On-device walking graph built from the bundled OSM street lines. It answers "how far is it
/// along mapped streets" so suggestions stop quoting straight-line distance. It is not
/// turn-by-turn navigation: OSM ways can be missing, gated or unsafe, and nobody reviewed them.
public final class WalkingGraph: @unchecked Sendable {
    struct Edge { var to: Int32; var meters: Float; var restricted: Bool }

    /// Ways nobody may walk on.
    public static let excludedClasses: Set<String> = ["motorway", "motorway_link"]
    /// Restricted ways count double so public streets win unless the detour is large.
    public static let restrictedPenalty = 2.0
    /// Points farther than this from any street get no street distance.
    public static let maxSnapMeters = 250.0
    /// Edges are split to at most this length so the snapping index stays local.
    static let maxEdgeMeters = 50.0

    struct Segment { var u: Int32; var v: Int32; var meters: Float; var restricted: Bool }
    /// Where a point meets the nearest street: fraction `t` along segment u→v, `offset` metres away.
    struct Snap { var segment: Segment; var t: Double; var offset: Double }

    private var coordinates: [Coordinate] = []
    private var adjacency: [[Edge]] = []
    private var segments: [Segment] = []
    private var buckets: [Int64: [Int32]] = [:]
    private static let bucketDegrees = 0.0025

    public var nodeCount: Int { coordinates.count }

    public init(roads: [RoadContext.Road]) {
        var index: [Int64: Int32] = [:]
        func node(_ c: Coordinate) -> Int32 {
            // OSM nodes shared by two ways have identical coordinates, so this joins intersections.
            let key = Int64((c.latitude * 1e6).rounded()) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: Int((c.longitude * 1e6).rounded()))))
            if let id = index[key] { return id }
            let id = Int32(coordinates.count)
            index[key] = id
            coordinates.append(c)
            adjacency.append([])
            return id
        }
        for road in roads where !Self.excludedClasses.contains(road.h) {
            let points = road.coordinates
            for (a, b) in zip(points, points.dropFirst()) {
                let total = Geo.distanceMeters(a, b)
                let steps = max(1, Int((total / Self.maxEdgeMeters).rounded(.up)))
                var previous = node(a)
                for step in 1...steps {
                    let f = Double(step) / Double(steps)
                    let next = step == steps ? node(b) : node(Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                                                      longitude: a.longitude + (b.longitude - a.longitude) * f))
                    if next != previous {
                        let meters = Float(total / Double(steps))
                        adjacency[Int(previous)].append(Edge(to: next, meters: meters, restricted: road.r))
                        adjacency[Int(next)].append(Edge(to: previous, meters: meters, restricted: road.r))
                        let p = coordinates[Int(previous)], q = coordinates[Int(next)]
                        let mid = Coordinate(latitude: (p.latitude + q.latitude) / 2, longitude: (p.longitude + q.longitude) / 2)
                        buckets[Self.bucket(mid), default: []].append(Int32(segments.count))
                        segments.append(Segment(u: previous, v: next, meters: meters, restricted: road.r))
                    }
                    previous = next
                }
            }
        }
    }

    private static func bucket(_ c: Coordinate) -> Int64 {
        bucket(Int((c.latitude / bucketDegrees).rounded(.down)), Int((c.longitude / bucketDegrees).rounded(.down)))
    }

    private static func bucket(_ row: Int, _ column: Int) -> Int64 { Int64(row) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: column))) }

    /// Nearest point on any street segment within `maxSnapMeters`.
    func snap(_ c: Coordinate) -> Snap? {
        let row = Int((c.latitude / Self.bucketDegrees).rounded(.down))
        let column = Int((c.longitude / Self.bucketDegrees).rounded(.down))
        let mx = cos(c.latitude * .pi / 180) * 111_320.0, my = 110_540.0
        func local(_ p: Coordinate) -> (Double, Double) { ((p.longitude - c.longitude) * mx, (p.latitude - c.latitude) * my) }
        var best: Snap?
        for dr in -1...1 {
            for dc in -1...1 {
                for id in buckets[Self.bucket(row + dr, column + dc)] ?? [] {
                    let segment = segments[Int(id)]
                    let (ax, ay) = local(coordinates[Int(segment.u)]), (bx, by) = local(coordinates[Int(segment.v)])
                    let dx = bx - ax, dy = by - ay, lengthSquared = dx * dx + dy * dy
                    let t = lengthSquared > 0 ? min(1, max(0, -(ax * dx + ay * dy) / lengthSquared)) : 0
                    let px = ax + t * dx, py = ay + t * dy
                    let offset = (px * px + py * py).squareRoot()
                    if offset <= Self.maxSnapMeters, offset < (best?.offset ?? .infinity) {
                        best = Snap(segment: segment, t: t, offset: offset)
                    }
                }
            }
        }
        return best
    }

    /// Shortest street distance from `origin` to each target (nil when either end is off the
    /// mapped streets or no connected path exists within `maxMeters`). One search serves all targets.
    public func distances(from origin: Coordinate, to targets: [Coordinate],
                          maxMeters: Double = 15_000) -> [StreetDistance?] {
        guard let start = snap(origin) else { return targets.map { _ in nil } }
        let goals = targets.map { snap($0) }
        var remaining = Set(goals.flatMap { goal in goal.map { [$0.segment.u, $0.segment.v] } ?? [] })
        guard !remaining.isEmpty else { return targets.map { _ in nil } }

        func weight(_ meters: Double, _ restricted: Bool) -> Double { meters * (restricted ? Self.restrictedPenalty : 1) }
        var cost = [Int32: Double]()      // penalised cost used for ordering
        var length = [Int32: Double]()    // real street metres along the chosen path
        var restricted = [Int32: Bool]()
        var settled = Set<Int32>()
        var heap = MinHeap()
        // The start sits part-way along a segment: seed both of its ends.
        let startLength = Double(start.segment.meters)
        for (node, along) in [(start.segment.u, start.t * startLength), (start.segment.v, (1 - start.t) * startLength)] {
            let c = weight(along, start.segment.restricted)
            if c < cost[node] ?? .infinity {
                cost[node] = c; length[node] = along; restricted[node] = start.segment.restricted && along > 0.5
                heap.push(c, node)
            }
        }
        let costLimit = maxMeters * Self.restrictedPenalty
        while let top = heap.pop() {
            let (c, u) = top
            if c > costLimit { break }
            if settled.contains(u) { continue }
            settled.insert(u)
            remaining.remove(u)
            if remaining.isEmpty { break }
            let baseLength = length[u] ?? 0, baseRestricted = restricted[u] ?? false
            for edge in adjacency[Int(u)] where !settled.contains(edge.to) {
                let next = c + weight(Double(edge.meters), edge.restricted)
                if next < cost[edge.to] ?? .infinity {
                    cost[edge.to] = next
                    length[edge.to] = baseLength + Double(edge.meters)
                    restricted[edge.to] = baseRestricted || edge.restricted
                    heap.push(next, edge.to)
                }
            }
        }
        return goals.map { goal -> StreetDistance? in
            guard let goal else { return nil }
            let goalLength = Double(goal.segment.meters)
            var best: (cost: Double, meters: Double, restricted: Bool)?
            func consider(_ c: Double, _ meters: Double, _ r: Bool) {
                if c < (best?.cost ?? .infinity) { best = (c, meters, r) }
            }
            for (node, along) in [(goal.segment.u, goal.t * goalLength), (goal.segment.v, (1 - goal.t) * goalLength)]
            where settled.contains(node) {
                consider((cost[node] ?? 0) + weight(along, goal.segment.restricted), (length[node] ?? 0) + along,
                         (restricted[node] ?? false) || (goal.segment.restricted && along > 0.5))
            }
            // Both ends on the same piece of street.
            let sameSegment = (goal.segment.u == start.segment.u && goal.segment.v == start.segment.v)
            if sameSegment {
                let along = abs(goal.t - start.t) * goalLength
                consider(weight(along, goal.segment.restricted), along, goal.segment.restricted && along > 0.5)
            }
            guard let best, best.meters <= maxMeters else { return nil }
            return StreetDistance(meters: best.meters + start.offset + goal.offset, throughRestricted: best.restricted)
        }
    }

    public func distance(from origin: Coordinate, to target: Coordinate) -> StreetDistance? {
        distances(from: origin, to: [target])[0]
    }
}

/// Binary min-heap of (cost, node).
private struct MinHeap {
    private var items: [(Double, Int32)] = []

    mutating func push(_ cost: Double, _ node: Int32) {
        items.append((cost, node))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i].0 < items[parent].0 else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> (Double, Int32)? {
        guard let top = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var smallest = i
                if l < items.count, items[l].0 < items[smallest].0 { smallest = l }
                if r < items.count, items[r].0 < items[smallest].0 { smallest = r }
                guard smallest != i else { break }
                items.swapAt(i, smallest)
                i = smallest
            }
        }
        return top
    }
}
