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
final class MapGeometry {
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
        for pack in content.packs {
            for road in pack.roads.roads {
                let points = road.coordinates.map { projection.project($0) }
                guard let first = points.first else { continue }
                var line = Path()
                line.move(to: CGPoint(x: first.x, y: first.y))
                for point in points.dropFirst() { line.addLine(to: CGPoint(x: point.x, y: point.y)) }
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

/// Ivory fog over the starter map. Only the accepted corridor (revealWidthMeters wide)
/// shows road detail; the trail, live position and chosen destination draw on top.
struct FogMapView: View {
    let geometry: MapGeometry
    let exploration: Exploration
    let activeSegments: [[TrackSample]]
    let position: Coordinate?
    let destination: Place?
    @Binding var camera: MapCamera

    @State private var dragStart: CGPoint?
    @State private var zoomStart: CGFloat?

    var body: some View {
        Canvas { context, size in
            let transform = camera.transform(in: size)
            let ppm = camera.pointsPerMeter

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.canvas))
            drawClouds(in: &context, size: size)

            // Revealed layer: ground + roads, kept only where the corridor was walked. Only tiles that are
            // both on screen and under explored paths are drawn, so city-scale packs stay cheap.
            let explored = geometry.path(for: exploration)
            let visible = CGRect(origin: .zero, size: size).applying(transform.inverted())
            let areas = geometry.exploredRects(for: exploration).compactMap { rect -> CGRect? in
                let clipped = rect.intersection(visible)
                return clipped.isNull ? nil : clipped
            }
            let screenExplored = explored.applying(transform)
            context.drawLayer { layer in
                // Clip before painting. A destinationIn stroke does not clear pixels
                // outside its bounds, and an empty stroke leaves the whole ground visible.
                let corridor = screenExplored.strokedPath(StrokeStyle(
                    lineWidth: max(2, CGFloat(exploration.revealWidthMeters) * ppm),
                    lineCap: .round, lineJoin: .round))
                layer.clip(to: corridor)
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.revealedGround))
                if !areas.isEmpty {
                    for tile in geometry.tiles where areas.contains(where: tile.bounds.intersects) {
                        layer.stroke(tile.minor.applying(transform), with: .color(Theme.border),
                                     style: StrokeStyle(lineWidth: max(1, 6 * ppm), lineCap: .round, lineJoin: .round))
                        layer.stroke(tile.major.applying(transform), with: .color(Theme.secondaryInk.opacity(0.45)),
                                     style: StrokeStyle(lineWidth: max(1.5, 12 * ppm), lineCap: .round, lineJoin: .round))
                        layer.stroke(tile.footways.applying(transform), with: .color(Theme.primary.opacity(0.55)),
                                     style: StrokeStyle(lineWidth: max(1, 2 * ppm), lineCap: .round, dash: [3, 3]))
                        layer.stroke(tile.restricted.applying(transform), with: .color(Theme.border.opacity(0.6)),
                                     style: StrokeStyle(lineWidth: max(0.5, 2 * ppm), dash: [2, 4]))
                    }
                }
            }

            // Region outlines so coverage limits are visible.
            context.stroke(geometry.detailedCoverage.applying(transform), with: .color(Theme.secondaryInk.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            context.stroke(geometry.contextCoverage.applying(transform), with: .color(Theme.secondaryInk.opacity(0.18)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 6]))

            // Current walk trail, segment by segment (never joined across gaps).
            var trail = Path()
            for segment in activeSegments {
                guard let first = segment.first else { continue }
                trail.move(to: geometry.point(first.coordinate).applying(transform))
                for sample in segment.dropFirst() { trail.addLine(to: geometry.point(sample.coordinate).applying(transform)) }
            }
            context.stroke(trail, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if let destination {
                let p = geometry.point(destination.coordinate).applying(transform)
                let pin = Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
                context.fill(pin, with: .color(Theme.surface))
                context.stroke(pin, with: .color(Theme.ink), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(Theme.ink))
            }

            if let position {
                let p = geometry.point(position).applying(transform)
                let dot = Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
                context.fill(dot, with: .color(Theme.primary))
                context.stroke(dot, with: .color(Theme.surface), lineWidth: 3)
            }
        }
        .gesture(dragGesture.simultaneously(with: zoomGesture))
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    /// Static, soft cloud banks: no animation, so Reduce Motion is respected.
    /// Decorative only; cloud shapes never add exploration or invented geography.
    private func drawClouds(in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 165
        let offsetX = (-camera.center.x * camera.pointsPerMeter * 0.15).truncatingRemainder(dividingBy: spacing)
        let offsetY = (camera.center.y * camera.pointsPerMeter * 0.15).truncatingRemainder(dividingBy: spacing)
        for row in -2...Int(size.height / spacing) + 2 {
            for column in -2...Int(size.width / spacing) + 2 {
                let x = CGFloat(column) * spacing + (row.isMultiple(of: 2) ? 0 : 80) + offsetX
                let y = CGFloat(row) * spacing + offsetY
                let bank = CGRect(x: x - 110, y: y - 42, width: 225, height: 100)
                var cloud = Path(ellipseIn: bank)
                cloud.addEllipse(in: CGRect(x: x - 85, y: y - 80, width: 115, height: 115))
                cloud.addEllipse(in: CGRect(x: x - 15, y: y - 66, width: 95, height: 100))
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: Theme.secondaryInk.opacity(0.09), radius: 14, y: 7))
                    layer.fill(cloud, with: .linearGradient(
                        Gradient(colors: [Theme.surface.opacity(0.9), Theme.canvas]),
                        startPoint: CGPoint(x: x, y: y - 80), endPoint: CGPoint(x: x, y: y + 58)))
                }
            }
        }
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
        return parts.joined(separator: " ")
    }
}
