import LifeOffDeskCore
import SwiftUI

/// Recap after Finish (or from history). Every number is computed from accepted samples.
struct RecapView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: WalkSession

    var body: some View {
        let recap = model.recap(for: session)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("You made room for a little adventure.")
                        .font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    RoutePreview(segments: session.segments)
                        .frame(height: 220)
                        .background(Theme.revealedGround, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("Route preview with \(recap.segmentCount) tracked sections")
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                        GridRow {
                            stat("Distance", Format.distance(recap.distanceMeters))
                            stat("Active time", Format.duration(recap.activeDuration))
                        }
                        GridRow {
                            stat("Newly revealed", Format.area(recap.newlyRevealedSquareMeters))
                            stat("GPS points kept", "\(recap.acceptedSamples)")
                        }
                    }
                    if let destination = recap.destinationName {
                        Label("Destination chosen: \(destination)", systemImage: "mappin.circle")
                            .foregroundStyle(Theme.ink)
                    }
                    if recap.wasRecovered {
                        Label("The app closed during this walk; time while closed is not counted.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                    if recap.acceptedSamples == 0 {
                        Text("No GPS points were accepted, so nothing was revealed.")
                            .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                    Text("Distance counts only accepted GPS points; gaps and paused time add nothing.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
                .padding(Theme.inset)
            }
            .background(Theme.canvas)
            .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(Theme.secondaryInk)
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small fitted drawing of the accepted segments.
struct RoutePreview: View {
    let segments: [[TrackSample]]

    var body: some View {
        Canvas { context, size in
            let all = segments.flatMap { $0 }
            guard let first = all.first else { return }
            let projection = LocalProjection(origin: first.coordinate)
            let points = segments.map { $0.map { projection.project($0.coordinate) } }
            let xs = points.flatMap { $0.map { CGFloat($0.x) } }, ys = points.flatMap { $0.map { CGFloat($0.y) } }
            let minX: CGFloat = xs.min() ?? 0, maxX: CGFloat = xs.max() ?? 0
            let minY: CGFloat = ys.min() ?? 0, maxY: CGFloat = ys.max() ?? 0
            let span: CGFloat = max(maxX - minX, maxY - minY, 30)
            let scale: CGFloat = (min(size.width, size.height) - 40) / span
            let midX: CGFloat = (minX + maxX) / 2, midY: CGFloat = (minY + maxY) / 2
            func screen(_ p: MeterPoint) -> CGPoint {
                CGPoint(x: size.width / 2 + (CGFloat(p.x) - midX) * scale,
                        y: size.height / 2 - (CGFloat(p.y) - midY) * scale)
            }
            for segment in points {
                guard let start = segment.first else { continue }
                var path = Path()
                path.move(to: screen(start))
                if segment.count == 1 { path.addLine(to: screen(start)) }
                for p in segment.dropFirst() { path.addLine(to: screen(p)) }
                context.stroke(path, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.finishedWalks.isEmpty {
                    Text("No finished walks yet. Your walks stay on this iPhone.")
                        .foregroundStyle(Theme.secondaryInk)
                }
                ForEach(model.finishedWalks) { walk in
                    NavigationLink {
                        RecapView(session: walk).environmentObject(model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(walk.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.ink)
                            Text("\(Format.distance(walk.distanceMeters)) · \(Format.duration(walk.activeDuration(at: walk.endedAt ?? Date())))")
                                .font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                        .frame(minHeight: Theme.minTarget)
                    }
                }
            }
            .navigationTitle("Past walks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
