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
    /// Points farther than this from any street node get no street distance.
    public static let maxSnapMeters = 250.0
    /// Edges are split to at most this length so snapping finds a node near any street point.
    static let maxEdgeMeters = 50.0

    private var coordinates: [Coordinate] = []
    private var adjacency: [[Edge]] = []
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
            buckets[Self.bucket(c), default: []].append(id)
            return id
        }
        for road in roads where !Self.excludedClasses.contains(road.h) {
            let points = road.coordinates
            for (a, b) in zip(points, points.dropFirst()) {
                // Long straight pieces get intermediate nodes so any point along them can snap.
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

    /// Nearest street node within `maxSnapMeters`.
    func nearestNode(to c: Coordinate) -> (id: Int32, meters: Double)? {
        let row = Int((c.latitude / Self.bucketDegrees).rounded(.down))
        let column = Int((c.longitude / Self.bucketDegrees).rounded(.down))
        var best: (Int32, Double)?
        for dr in -1...1 {
            for dc in -1...1 {
                for id in buckets[Self.bucket(row + dr, column + dc)] ?? [] {
                    let d = Geo.distanceMeters(c, coordinates[Int(id)])
                    if d <= Self.maxSnapMeters, d < (best?.1 ?? .infinity) { best = (id, d) }
                }
            }
        }
        return best
    }

    /// Shortest street distance from `origin` to each target (nil when either end is off the
    /// mapped streets or no connected path exists within `maxMeters`). One search serves all targets.
    public func distances(from origin: Coordinate, to targets: [Coordinate],
                          maxMeters: Double = 15_000) -> [StreetDistance?] {
        guard let start = nearestNode(to: origin) else { return targets.map { _ in nil } }
        let goals = targets.map { nearestNode(to: $0) }
        var remaining = Set(goals.compactMap { $0?.id })
        guard !remaining.isEmpty else { return targets.map { _ in nil } }

        var cost = [Int32: Double]()      // penalised cost used for ordering
        var length = [Int32: Double]()    // real street metres along the chosen path
        var restricted = [Int32: Bool]()
        var settled = Set<Int32>()
        var heap = MinHeap()
        cost[start.id] = 0; length[start.id] = 0; restricted[start.id] = false
        heap.push(0, start.id)
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
                let next = c + Double(edge.meters) * (edge.restricted ? Self.restrictedPenalty : 1)
                if next < cost[edge.to] ?? .infinity {
                    cost[edge.to] = next
                    length[edge.to] = baseLength + Double(edge.meters)
                    restricted[edge.to] = baseRestricted || edge.restricted
                    heap.push(next, edge.to)
                }
            }
        }
        return goals.map { goal in
            guard let goal, settled.contains(goal.id), let meters = length[goal.id], meters <= maxMeters else { return nil }
            return StreetDistance(meters: meters + start.meters + goal.meters,
                                  throughRestricted: restricted[goal.id] ?? false)
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
