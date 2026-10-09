import LifeOffDeskCore
import SwiftUI

/// Pre-projected starter geometry in local metres (y north). Built once.
final class MapGeometry {
    let projection: LocalProjection
    let majorRoads: Path
    let minorRoads: Path
    let footways: Path
    let restricted: Path
    let coverage: Path

    init(content: StarterContent) {
        let projection = LocalProjection(origin: content.region.center)
        self.projection = projection
        var major = Path(), minor = Path(), foot = Path(), restricted = Path()
        for road in content.roads.roads {
            let points = road.coordinates.map { projection.project($0) }
            guard let first = points.first else { continue }
            var line = Path()
            line.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() { line.addLine(to: CGPoint(x: point.x, y: point.y)) }
            if road.r {
                restricted.addPath(line)
                continue
            }
            switch road.h {
            case "primary", "secondary", "tertiary": major.addPath(line)
            case "footway", "path", "pedestrian": foot.addPath(line)
            default: minor.addPath(line)
            }
        }
        majorRoads = major; minorRoads = minor; footways = foot; self.restricted = restricted
        let b = content.region.bounds
        let sw = projection.project(Coordinate(latitude: b.south, longitude: b.west))
        let ne = projection.project(Coordinate(latitude: b.north, longitude: b.east))
        coverage = Path(CGRect(x: sw.x, y: sw.y, width: ne.x - sw.x, height: ne.y - sw.y))
    }

    func point(_ c: Coordinate) -> CGPoint {
        let p = projection.project(c)
        return CGPoint(x: p.x, y: p.y)
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

    static let minScale: CGFloat = 0.05
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
            let explored = geometry.path(for: exploration).applying(transform)

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.canvas))

            // Revealed layer: ground + roads, kept only where the corridor was walked.
            context.drawLayer { layer in
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.revealedGround))
                layer.stroke(geometry.minorRoads.applying(transform), with: .color(Theme.border),
                             style: StrokeStyle(lineWidth: max(1, 6 * ppm), lineCap: .round, lineJoin: .round))
                layer.stroke(geometry.majorRoads.applying(transform), with: .color(Theme.secondaryInk.opacity(0.45)),
                             style: StrokeStyle(lineWidth: max(1.5, 12 * ppm), lineCap: .round, lineJoin: .round))
                layer.stroke(geometry.footways.applying(transform), with: .color(Theme.primary.opacity(0.55)),
                             style: StrokeStyle(lineWidth: max(1, 2 * ppm), lineCap: .round, dash: [3, 3]))
                layer.stroke(geometry.restricted.applying(transform), with: .color(Theme.border.opacity(0.6)),
                             style: StrokeStyle(lineWidth: max(0.5, 2 * ppm), dash: [2, 4]))
                layer.blendMode = .destinationIn
                layer.stroke(explored, with: .color(.black),
                             style: StrokeStyle(lineWidth: max(2, CGFloat(exploration.revealWidthMeters) * ppm),
                                                lineCap: .round, lineJoin: .round))
            }

            // Starter coverage outline so the limits are visible.
            context.stroke(geometry.coverage.applying(transform), with: .color(Theme.secondaryInk.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1, dash: [6, 6]))

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
