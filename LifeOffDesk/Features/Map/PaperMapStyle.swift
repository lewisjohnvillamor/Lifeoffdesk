import LifeOffDeskCore
import SwiftUI
import UIKit

/// Paper-and-ink map look: fibrous paper fog over unexplored areas, a raised torn-paper
/// island where the user actually walked, and hand-drawn ink roads on the island.
/// All randomness is a deterministic hash of world position, so shapes never shimmer
/// between frames and nothing here adds or removes exploration.
enum PaperStyle {
    static let paper = Color(hex: 0xF1EFE8)          // fog paper (slightly darker than the island)
    static let island = Color(hex: 0xFFFEFB)         // explored paper
    static let edge = Color(hex: 0xCBC6B8)           // visible paper thickness under the island
    static let ink = Color(hex: 0x1F2A24)            // road ink (near-black brand ink)
    static let ghostInk = Color(hex: 0x283A31).opacity(0.22)
    static let grid = Color(hex: 0x283A31).opacity(0.05)
    static let fogOpacity: Double = 0.72
    static let gridMeters: CGFloat = 60

    /// Deterministic value in [-1, 1] for integer inputs.
    static func noise(_ a: Int, _ b: Int, _ c: Int = 0) -> CGFloat {
        var h = UInt64(bitPattern: Int64(a)) &* 0x9E3779B97F4A7C15
        h ^= UInt64(bitPattern: Int64(b)) &* 0xC2B2AE3D27D4EB4F
        h ^= UInt64(bitPattern: Int64(c)) &* 0x165667B19E3779F9
        h ^= h >> 29; h = h &* 0xBF58476D1CE4E5B9; h ^= h >> 32
        return CGFloat(h % 20_001) / 10_000 - 1
    }

    /// Polyline with small perpendicular wobble (±amplitude metres) so roads read as hand-inked.
    static func inkedLine(_ points: [MeterPoint], amplitude: CGFloat = 1.1, step: CGFloat = 14) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = CGFloat(b.x - a.x), dy = CGFloat(b.y - a.y)
            let length = hypot(dx, dy)
            guard length > 0.01 else { continue }
            let pieces = max(1, Int((length / step).rounded(.up)))
            let nx = -dy / length, ny = dx / length
            var previous = CGPoint(x: a.x, y: a.y)
            for i in 1...pieces {
                let t = CGFloat(i) / CGFloat(pieces)
                let end = CGPoint(x: CGFloat(a.x) + dx * t, y: CGFloat(a.y) + dy * t)
                let mid = CGPoint(x: (previous.x + end.x) / 2, y: (previous.y + end.y) / 2)
                let n = noise(Int(mid.x * 2), Int(mid.y * 2), 7) * amplitude
                path.addQuadCurve(to: end, control: CGPoint(x: mid.x + nx * n, y: mid.y + ny * n))
                previous = end
            }
        }
        return path
    }

    /// Fibrous paper texture tile (rendered once): fine fibres plus soft cloudy blotches.
    static let fiberTile: Image = {
        let side: CGFloat = 384
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            for i in 0..<34 {
                let x = (noise(i, 1, 11) + 1) / 2 * side, y = (noise(i, 2, 11) + 1) / 2 * side
                let r = 40 + (noise(i, 3, 11) + 1) * 45
                let alpha = 0.035 + (noise(i, 4, 11) + 1) * 0.025
                for dx in [-side, 0, side] { for dy in [-side, 0, side] {
                    cg.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                    cg.fillEllipse(in: CGRect(x: x + dx - r, y: y + dy - r * 0.7, width: r * 2, height: r * 1.4))
                } }
            }
            cg.setLineCap(.round)
            for i in 0..<420 {
                let x = (noise(i, 5, 13) + 1) / 2 * side, y = (noise(i, 6, 13) + 1) / 2 * side
                let angle = noise(i, 7, 13) * .pi
                let length = 10 + (noise(i, 8, 13) + 1) * 26
                let bend = noise(i, 9, 13) * 9
                let dark = noise(i, 10, 13) > 0.35
                cg.setStrokeColor(dark ? UIColor(red: 0.16, green: 0.23, blue: 0.19, alpha: 0.10 + (noise(i, 12, 13) + 1) * 0.04).cgColor
                                       : UIColor(white: 1, alpha: 0.55).cgColor)
                cg.setLineWidth(dark ? 0.6 : 1.1)
                let end = CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length)
                let control = CGPoint(x: (x + end.x) / 2 - sin(angle) * bend, y: (y + end.y) / 2 + cos(angle) * bend)
                for dx in [-side, 0, side] { for dy in [-side, 0, side] {
                    cg.move(to: CGPoint(x: x + dx, y: y + dy))
                    cg.addQuadCurve(to: CGPoint(x: end.x + dx, y: end.y + dy),
                                    control: CGPoint(x: control.x + dx, y: control.y + dy))
                    cg.strokePath()
                } }
            }
        }
        return Image(uiImage: image)
    }()
}

/// Builds the torn-paper island (union of jagged discs stamped along explored paths) in local
/// metres. Cached per path so a growing live walk or replay only rebuilds its own path.
final class IslandCache {
    private struct Entry {
        var pointCount: Int
        var lastPoint: Coordinate?
        var path: Path
        var bounds: CGRect
    }

    private var entries: [String: Entry] = [:]

    func islands(for exploration: Exploration, geometry: MapGeometry) -> [(path: Path, bounds: CGRect)] {
        let radius = CGFloat(exploration.revealWidthMeters) / 2
        var counters: [UUID: Int] = [:]
        var live = Set<String>()
        var result: [(Path, CGRect)] = []
        for explored in exploration.paths {
            let index = counters[explored.sessionID, default: 0]
            counters[explored.sessionID] = index + 1
            let key = "\(explored.sessionID.uuidString)#\(index)"
            live.insert(key)
            if let cached = entries[key], cached.pointCount == explored.points.count,
               cached.lastPoint == explored.points.last {
                result.append((cached.path, cached.bounds))
                continue
            }
            let path = Self.island(along: explored.points.map { geometry.projection.project($0) }, radius: radius)
            let entry = Entry(pointCount: explored.points.count, lastPoint: explored.points.last,
                              path: path, bounds: path.boundingRect)
            entries[key] = entry
            result.append((path, entry.bounds))
        }
        entries = entries.filter { live.contains($0.key) }
        return result
    }

    static func island(along points: [MeterPoint], radius: CGFloat) -> Path {
        var stamps: [CGPoint] = []
        let spacing = radius * 0.55
        guard let first = points.first else { return Path() }
        stamps.append(CGPoint(x: first.x, y: first.y))
        var carry: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = CGFloat(b.x - a.x), dy = CGFloat(b.y - a.y)
            let length = hypot(dx, dy)
            var travelled = spacing - carry
            while travelled <= length {
                let t = travelled / length
                stamps.append(CGPoint(x: CGFloat(a.x) + dx * t, y: CGFloat(a.y) + dy * t))
                travelled += spacing
            }
            carry = length - (travelled - spacing)
        }
        if let last = points.last, points.count > 1 { stamps.append(CGPoint(x: last.x, y: last.y)) }

        var path = Path()
        let vertices = 14
        for stamp in stamps {
            let gx = Int((stamp.x * 1.7).rounded()), gy = Int((stamp.y * 1.7).rounded())
            for v in 0..<vertices {
                let angle = CGFloat(v) / CGFloat(vertices) * 2 * .pi
                // Two noise octaves: slow wobble plus fine torn-paper jitter.
                let r = radius * (1 + 0.13 * PaperStyle.noise(gx, gy, v / 3) + 0.07 * PaperStyle.noise(gx, gy, v + 101))
                let point = CGPoint(x: stamp.x + cos(angle) * r, y: stamp.y + sin(angle) * r)
                if v == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        return path
    }
}
