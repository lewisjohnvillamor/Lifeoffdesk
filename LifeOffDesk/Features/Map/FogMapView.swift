import LifeOffDeskCore
import SwiftUI

/// Roads near each other, grouped so only tiles under the explored corridor are drawn.
struct RoadTile {
    var bounds: CGRect = .null
    var major = Path()
    var minor = Path()
    var footways = Path()
    var restricted = Path()
}

/// Pre-projected starter geometry in local metres (y north). Built once.
final class MapGeometry: @unchecked Sendable { // immutable after init
    static let tileSize: CGFloat = 1000

    let projection: LocalProjection
    let tiles: [RoadTile]
    /// Full-detail region outlines (dashed) and context-only outlines (fainter).
    let detailedCoverage: Path
    let contextCoverage: Path

    init(content: StarterContent) {
        let projection = LocalProjection(origin: content.region.center)
        self.projection = projection
        var grouped: [GridKey: RoadTile] = [:]
        var detailed = Path(), context = Path()
        let detailedBounds = content.packs.filter { $0.region.hasFullDetail }.map(\.region.bounds)
        for pack in content.packs {
            for road in pack.roads.roads {
                let coordinates = road.coordinates
                // Context-only packs (Metro Manila main roads) repeat roads that detailed packs already
                // contain; drawing both gave doubled, drifting lines. Detailed packs win.
                if !pack.region.hasFullDetail, let mid = coordinates.dropFirst(coordinates.count / 2).first,
                   detailedBounds.contains(where: { $0.contains(mid) }) { continue }
                let points = coordinates.map { projection.project($0) }
                guard points.count >= 2 else { continue }
                let line = PaperStyle.inkedLine(points)
                let box = line.boundingRect
                let key = GridKey(x: Int((box.midX / Self.tileSize).rounded(.down)),
                                  y: Int((box.midY / Self.tileSize).rounded(.down)))
                var tile = grouped[key] ?? RoadTile()
                tile.bounds = tile.bounds.union(box)
                if road.r {
                    tile.restricted.addPath(line)
                } else {
                    switch road.h {
                    case "motorway", "trunk", "primary", "secondary", "tertiary": tile.major.addPath(line)
                    case "footway", "path", "pedestrian": tile.footways.addPath(line)
                    default: tile.minor.addPath(line)
                    }
                }
                grouped[key] = tile
            }
            let b = pack.region.bounds
            let sw = projection.project(Coordinate(latitude: b.south, longitude: b.west))
            let ne = projection.project(Coordinate(latitude: b.north, longitude: b.east))
            let rect = CGRect(x: sw.x, y: sw.y, width: ne.x - sw.x, height: ne.y - sw.y)
            if pack.region.hasFullDetail { detailed.addRect(rect) } else { context.addRect(rect) }
        }
        tiles = Array(grouped.values)
        detailedCoverage = detailed
        contextCoverage = context
    }

    private struct GridKey: Hashable { var x: Int; var y: Int }

    func point(_ c: Coordinate) -> CGPoint {
        let p = projection.project(c)
        return CGPoint(x: p.x, y: p.y)
    }

    /// Bounds of each explored path, padded by the corridor width, in local metres.
    func exploredRects(for exploration: Exploration) -> [CGRect] {
        let pad = CGFloat(exploration.revealWidthMeters)
        return exploration.paths.compactMap { explored in
            let points = explored.points.map(point)
            guard let first = points.first else { return nil }
            var rect = CGRect(origin: first, size: .zero)
            for p in points.dropFirst() { rect = rect.union(CGRect(origin: p, size: .zero)) }
            return rect.insetBy(dx: -pad, dy: -pad)
        }
    }

    func path(for exploration: Exploration) -> Path {
        var path = Path()
        for explored in exploration.paths {
            guard let first = explored.points.first else { continue }
            path.move(to: point(first))
            if explored.points.count == 1 {
                path.addLine(to: point(first)) // a single fix reveals a small round spot
            }
            for c in explored.points.dropFirst() { path.addLine(to: point(c)) }
        }
        return path
    }
}

struct MapCamera: Equatable {
    /// Centre in local metres.
    var center = CGPoint.zero
    var pointsPerMeter: CGFloat = 0.35

    static let minScale: CGFloat = 0.01
    static let maxScale: CGFloat = 4

    func transform(in size: CGSize) -> CGAffineTransform {
        CGAffineTransform(a: pointsPerMeter, b: 0, c: 0, d: -pointsPerMeter,
                          tx: size.width / 2 - center.x * pointsPerMeter,
                          ty: size.height / 2 + center.y * pointsPerMeter)
    }
}

/// Paper-and-ink map. Unexplored areas sit under fibrous paper fog with streets only faintly
/// showing; the accepted corridor (revealWidthMeters wide) is a raised torn-paper island with
/// inked roads. Trail, live position and chosen destination draw on top.
struct FogMapView: View {
    let geometry: MapGeometry
    let exploration: Exploration
    /// Current walk (or replay): new ground dotted, revisited ground solid.
    let trailRuns: [TrailRun]
    /// Captured moments with a location, drawn as photo pins (nearby ones grouped into clusters).
    var pins: [MapPin] = []
    /// Tapping a single photo pin; tapping a cluster zooms in instead.
    var onPinTap: (UUID) -> Void = { _ in }
    let position: Coordinate?
    let destination: Place?
    /// Suggested path along mapped streets to the destination (not navigation).
    var route: [Coordinate]? = nil
    @Binding var camera: MapCamera
    var tilted: Bool = true

    @State private var dragStart: CGPoint?
    @State private var zoomStart: CGFloat?
    @State private var islands = IslandCache()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        Canvas { context, size in
            let transform = camera.transform(in: size)
            let ppm = camera.pointsPerMeter
            let screen = CGRect(origin: .zero, size: size)
            let visible = screen.applying(transform.inverted()).insetBy(dx: -40, dy: -40)

            // 1. Paper and a faint world-anchored grid.
            context.fill(Path(screen), with: .color(PaperStyle.paper))
            let gridPath = grid(in: visible)
            if PaperStyle.gridMeters * ppm >= 12 {
                context.stroke(gridPath.applying(transform), with: .color(PaperStyle.grid), lineWidth: 0.6)
            }

            let visibleTiles = geometry.tiles.filter { $0.bounds.intersects(visible) }

            // 2. Island geometry for what was actually walked (only pieces near the screen).
            var island = Path()
            for piece in islands.islands(for: exploration, geometry: geometry) where piece.bounds.intersects(visible) {
                island.addPath(piece.path)
            }
            let screenIsland = island.applying(transform)
            let lift = max(2, min(7, 9 * ppm))

            // 3. Fibrous paper fog everywhere except the island.
            context.drawLayer { fog in
                fog.clip(to: screenIsland, options: .inverse)
                fog.fill(Path(screen), with: .color(PaperStyle.paper.opacity(reduceTransparency ? 0.92 : PaperStyle.fogOpacity)))
                let anchor = CGPoint(x: 0, y: 0).applying(transform)
                fog.fill(Path(screen), with: .tiledImage(PaperStyle.fiberTile, origin: anchor, scale: 0.5))
            }

            // Ghost streets: faint ink over the fog, so the city is hinted but not revealed.
            context.drawLayer { ghostLayer in
                ghostLayer.clip(to: screenIsland, options: .inverse)
                let detailed = ppm >= 0.03
                for tile in visibleTiles {
                    ghostLayer.stroke(tile.major.applying(transform), with: .color(PaperStyle.ghostInk),
                                      lineWidth: detailed ? 0.9 : 0.6)
                    if detailed {
                        ghostLayer.stroke(tile.minor.applying(transform), with: .color(PaperStyle.ghostInk.opacity(0.7)),
                                          lineWidth: 0.5)
                    }
                }
            }

            // Region outlines so coverage limits stay visible through the fog.
            context.stroke(geometry.detailedCoverage.applying(transform), with: .color(PaperStyle.ink.opacity(0.25)),
                           style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            context.stroke(geometry.contextCoverage.applying(transform), with: .color(PaperStyle.ink.opacity(0.12)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 6]))

            if !island.isEmpty {
                // 4. Raised paper: soft shadow, visible thickness, then the white sheet.
                // The blurred shadow is the costliest layer; zoomed far out (a year of adventures on
                // screen) it is invisible anyway, so it is skipped there.
                if ppm >= 0.05 {
                    context.drawLayer { shadow in
                        shadow.addFilter(.shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: lift + 4))
                        shadow.fill(screenIsland.offsetBy(dx: 0, dy: lift), with: .color(PaperStyle.edge))
                    }
                }
                context.fill(screenIsland.offsetBy(dx: 0, dy: lift), with: .color(PaperStyle.edge))
                context.fill(screenIsland, with: .color(PaperStyle.island))

                // 5. Ink roads and grid on the island only.
                context.drawLayer { sheet in
                    sheet.clip(to: screenIsland)
                    if PaperStyle.gridMeters * ppm >= 12 {
                        sheet.stroke(gridPath.applying(transform), with: .color(PaperStyle.grid.opacity(1.4)), lineWidth: 0.6)
                    }
                    let islandBounds = island.boundingRect
                    for tile in visibleTiles where tile.bounds.intersects(islandBounds) {
                        sheet.stroke(tile.restricted.applying(transform), with: .color(PaperStyle.ink.opacity(0.35)),
                                     style: StrokeStyle(lineWidth: max(0.4, 1.5 * ppm), lineCap: .round, dash: [2, 3]))
                        sheet.stroke(tile.footways.applying(transform), with: .color(PaperStyle.ink.opacity(0.8)),
                                     style: StrokeStyle(lineWidth: max(0.5, 1.6 * ppm), lineCap: .round, lineJoin: .round))
                        sheet.stroke(tile.minor.applying(transform), with: .color(PaperStyle.ink),
                                     style: StrokeStyle(lineWidth: max(0.8, 3.5 * ppm), lineCap: .round, lineJoin: .round))
                        sheet.stroke(tile.major.applying(transform), with: .color(PaperStyle.ink),
                                     style: StrokeStyle(lineWidth: max(1.4, 7 * ppm), lineCap: .round, lineJoin: .round))
                    }
                }
            }

            // Suggested street route to the destination: white casing, green dashes, under the trail.
            if let route, let first = route.first, route.count > 1 {
                var line = Path()
                line.move(to: geometry.point(first).applying(transform))
                for c in route.dropFirst() { line.addLine(to: geometry.point(c).applying(transform)) }
                context.stroke(line, with: .color(Theme.surface.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                context.stroke(line, with: .color(Theme.primary),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 6]))
            }

            // 6. Current walk trail: dots over new ground, a quiet solid line over streets walked before.
            for run in trailRuns {
                guard let first = run.points.first else { continue }
                var line = Path()
                line.move(to: geometry.point(first).applying(transform))
                for c in run.points.dropFirst() { line.addLine(to: geometry.point(c).applying(transform)) }
                if run.isNew {
                    context.stroke(line, with: .color(PaperStyle.ink),
                                   style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [0.1, 10]))
                } else {
                    context.stroke(line, with: .color(Theme.secondaryInk.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }

            // Photo pins for captured moments; pins closer than a thumb's width share one pin with a count.
            for cluster in PinClusters.make(pins, project: { geometry.point($0).applying(transform) }) {
                let p = cluster.point
                let frame = CGRect(x: p.x - 19, y: p.y - 46, width: 38, height: 38)
                var stem = Path()
                stem.move(to: CGPoint(x: p.x - 6, y: p.y - 10)); stem.addLine(to: CGPoint(x: p.x, y: p.y))
                stem.addLine(to: CGPoint(x: p.x + 6, y: p.y - 10)); stem.closeSubpath()
                context.fill(stem, with: .color(.white))
                let badge = Path(roundedRect: frame.insetBy(dx: -3, dy: -3), cornerRadius: 12)
                context.drawLayer { pinLayer in
                    pinLayer.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, y: 2))
                    pinLayer.fill(badge, with: .color(.white))
                }
                if let image = cluster.image {
                    context.drawLayer { photoLayer in
                        photoLayer.clip(to: Path(roundedRect: frame, cornerRadius: 9))
                        photoLayer.draw(Image(uiImage: image), in: frame)
                    }
                } else {
                    context.fill(Path(roundedRect: frame, cornerRadius: 9), with: .color(Theme.revealedGround))
                }
                if cluster.ids.count > 1 {
                    let count = context.resolve(Text("\(cluster.ids.count)").font(.caption2.bold()).foregroundColor(.white))
                    let size = count.measure(in: CGSize(width: 60, height: 20))
                    let w = max(20, size.width + 10)
                    let bubble = CGRect(x: frame.maxX - w / 2 - 2, y: frame.minY - 12, width: w, height: 20)
                    context.fill(Path(roundedRect: bubble, cornerRadius: 10), with: .color(Theme.primary))
                    context.stroke(Path(roundedRect: bubble, cornerRadius: 10), with: .color(.white), lineWidth: 1.5)
                    context.draw(count, at: CGPoint(x: bubble.midX, y: bubble.midY), anchor: .center)
                }
            }

            if let destination {
                // Category icon in a tinted badge on a short stem (red for police, hospitals, fire stations).
                let p = geometry.point(destination.coordinate).applying(transform)
                let badge = CGRect(x: p.x - 17, y: p.y - 44, width: 34, height: 34)
                var stem = Path()
                stem.move(to: CGPoint(x: p.x - 6, y: p.y - 12)); stem.addLine(to: CGPoint(x: p.x, y: p.y))
                stem.addLine(to: CGPoint(x: p.x + 6, y: p.y - 12)); stem.closeSubpath()
                let tint = PlaceIcon.tint(destination)
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, y: 2))
                    layer.fill(stem, with: .color(tint))
                    layer.fill(Path(ellipseIn: badge), with: .color(tint))
                }
                context.stroke(Path(ellipseIn: badge), with: .color(Theme.surface), lineWidth: 2.5)
                var symbol = context.resolve(Image(systemName: PlaceIcon.symbol(destination)))
                symbol.shading = .color(Theme.surface)
                context.draw(symbol, at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(PaperStyle.ink))
            }

            if let position {
                let p = geometry.point(position).applying(transform)
                let halo = Path(ellipseIn: CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32))
                context.fill(halo, with: .color(Theme.primary.opacity(0.18)))
                let dot = Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
                context.fill(dot, with: .color(Theme.primary))
                context.stroke(dot, with: .color(Theme.surface), lineWidth: 3)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { canvasSize = proxy.size }
                .onChange(of: proxy.size) { _, size in canvasSize = size }
        })
        // Attached before the tilt so the tap location is in the canvas's own coordinates.
        .simultaneousGesture(SpatialTapGesture().onEnded { value in handleTap(at: value.location) })
        // Gentle 3D tilt like a sheet of paper on a desk; the canvas is oversized so corners stay covered.
        .scaleEffect(tilted ? 1.45 : 1)
        .rotation3DEffect(.degrees(tilted ? 32 : 0), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
        .gesture(dragGesture.simultaneously(with: zoomGesture))
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    /// Single pin: open it. Cluster: zoom in around it until the photos separate.
    private func handleTap(at location: CGPoint) {
        guard canvasSize != .zero, !pins.isEmpty else { return }
        let transform = camera.transform(in: canvasSize)
        let clusters = PinClusters.make(pins, project: { geometry.point($0).applying(transform) })
        // The pin image sits above its anchor point.
        guard let hit = clusters.min(by: { distance($0, location) < distance($1, location) }),
              distance(hit, location) < 34 else { return }
        if hit.ids.count == 1 {
            onPinTap(hit.ids[0])
        } else {
            let world = hit.point.applying(transform.inverted())
            withAnimation(.easeInOut(duration: 0.35)) {
                camera.center = world
                camera.pointsPerMeter = min(MapCamera.maxScale, camera.pointsPerMeter * 2.5)
            }
        }
    }

    private func distance(_ cluster: PinClusters.Cluster, _ location: CGPoint) -> CGFloat {
        hypot(cluster.point.x - location.x, cluster.point.y - 28 - location.y)
    }

    private func grid(in rect: CGRect) -> Path {
        var path = Path()
        let step = PaperStyle.gridMeters
        guard rect.width / step < 400, rect.height / step < 400 else { return path }
        var x = (rect.minX / step).rounded(.down) * step
        while x <= rect.maxX { path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
        var y = (rect.minY / step).rounded(.down) * step
        while y <= rect.maxY { path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
        return path
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil { dragStart = camera.center }
                guard let start = dragStart else { return }
                camera.center = CGPoint(x: start.x - value.translation.width / camera.pointsPerMeter,
                                        y: start.y + value.translation.height / camera.pointsPerMeter)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if zoomStart == nil { zoomStart = camera.pointsPerMeter }
                guard let start = zoomStart else { return }
                camera.pointsPerMeter = min(MapCamera.maxScale, max(MapCamera.minScale, start * scale))
            }
            .onEnded { _ in zoomStart = nil }
    }

    private var accessibilitySummary: String {
        var parts = ["Personal map."]
        let walked = exploration.paths.count
        parts.append(walked == 0 ? "Nothing explored yet; the map is covered by fog." : "\(walked) explored path sections are revealed.")
        parts.append(position == nil ? "Current location not shown." : "Current location shown.")
        if let destination { parts.append("Destination marker: \(destination.name).") }
        if route != nil { parts.append("A suggested route along mapped streets is drawn to it.") }
        return parts.joined(separator: " ")
    }
}

/// A photo pin on the map.
struct MapPin: Identifiable {
    let id: UUID
    let coordinate: Coordinate
    let image: UIImage?
}

/// Groups pins that would overlap on screen (greedy, in screen space, so it re-clusters as you zoom).
/// Keeps a year of daily photos readable: far out they merge into a few counted pins.
enum PinClusters {
    struct Cluster {
        var point: CGPoint
        var ids: [UUID]
        var image: UIImage?
    }

    static let radius: CGFloat = 40

    static func make(_ pins: [MapPin], project: (Coordinate) -> CGPoint) -> [Cluster] {
        var clusters: [Cluster] = []
        var cells: [Int64: [Int]] = [:]
        func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: y))) }
        for pin in pins {
            let p = project(pin.coordinate)
            let cx = Int((p.x / radius).rounded(.down)), cy = Int((p.y / radius).rounded(.down))
            var joined = false
            search: for dx in -1...1 {
                for dy in -1...1 {
                    for index in cells[key(cx + dx, cy + dy)] ?? [] where hypot(clusters[index].point.x - p.x, clusters[index].point.y - p.y) < radius {
                        clusters[index].ids.append(pin.id)
                        joined = true
                        break search
                    }
                }
            }
            if !joined {
                cells[key(cx, cy), default: []].append(clusters.count)
                clusters.append(Cluster(point: p, ids: [pin.id], image: pin.image))
            }
        }
        return clusters
    }
}
