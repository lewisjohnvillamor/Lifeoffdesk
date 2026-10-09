import LifeOffDeskCore
import SwiftUI

/// Recap after Finish (or from history). Every number is computed from accepted samples.
struct RecapView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: WalkSession
    @State private var showCard = false
    @State private var confirmDelete = false

    var body: some View {
        let recap = model.recap(for: session)
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 10) {
                        MascotView(pose: .celebrating, size: 64)
                        Text("You made room for a little adventure.")
                            .font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    }
                    if model.isDemo(session) {
                        Label("Sample adventure · not real GPS", systemImage: "sparkles")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.danger)
                    }
                    Button { showCard = true } label: {
                        MemoryCardView(session: session, recap: recap,
                                       photos: model.moments(for: session).compactMap { model.photo(for: $0) },
                                       isSample: model.isDemo(session), placesFound: model.discovered(in: session).count,
                                       route: model.cardRoute(for: session))
                            .scaleEffect(0.78)
                            .frame(width: MemoryCardView.size.width * 0.78, height: MemoryCardView.size.height * 0.78)
                            .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Adventure card. Add a photo and share.")
                    HStack(spacing: 0) {
                        stat("New streets", Format.distance(recap.newDistanceMeters))
                        stat("Places found", "\(model.discovered(in: session).count)")
                        stat("Time", Format.duration(recap.activeDuration))
                    }
                    if recap.ridingMeters >= 50 {
                        Text("On foot \(Format.distance(recap.onFootMeters)) · Riding \(Format.distance(recap.ridingMeters))")
                            .font(.footnote).foregroundStyle(Theme.secondaryInk)
                            .accessibilityLabel("On foot \(Format.distance(recap.onFootMeters)), riding \(Format.distance(recap.ridingMeters))")
                    }
                    let found = model.discovered(in: session)
                    if !found.isEmpty {
                        Text("You passed " + found.prefix(4).map(\.name).joined(separator: ", ") + (found.count > 4 ? " and more" : ""))
                            .font(.footnote).foregroundStyle(Theme.secondaryInk).multilineTextAlignment(.center)
                    }
                    narration
                    Button { showCard = true } label: { Label("Make a card", systemImage: "camera") }
                        .buttonStyle(PrimaryButtonStyle())
                    if recap.wasRecovered {
                        Label("App closed mid-walk; that time isn't counted.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                    if recap.acceptedSamples == 0 {
                        Text("No GPS points kept, so nothing was revealed.")
                            .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .padding(Theme.inset)
            }
            .background(Theme.canvas)
            .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !model.isDemo(session) {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                            .foregroundStyle(Theme.danger)
                            .accessibilityLabel("Delete adventure")
                    }
                }
            }
            .confirmationDialog("Delete this adventure?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete adventure", role: .destructive) {
                    model.deleteAdventure(session)
                    dismiss()
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("Its trail, photos and the streets it uncovered will be removed from this iPhone. This can't be undone.")
            }
            .sheet(isPresented: $showCard) { MemoryCardSheet(session: session).environmentObject(model) }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.ink)
            Text(title).font(.footnote).foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
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

extension RecapView {
    /// P0-13: the model only picks computed facts and a tone; numbers come from the recap.
    @ViewBuilder private var narration: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.narrations[session.id] {
            case nil:
                if let cached = model.cachedNarration(for: session) {
                    narrationText(cached, note: "AI-selected highlights · values computed from your trail")
                } else {
                    Button { model.requestNarration(for: session) } label: {
                        Label("Taglish recap", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Uses the on-device model to pick highlights; numbers are computed")
                }
            case .working?:
                HStack(spacing: 8) { ProgressView(); Text("Pumipili ng highlights…").font(.footnote) }
            case let .ai(text)?:
                narrationText(text, note: "AI-selected highlights · values computed from your trail")
            case let .fallback(text, reason)?:
                narrationText(text, note: "Computed summary (no AI result: \(reason))")
                Button("Try again") { model.requestNarration(for: session) }.font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func narrationText(_ text: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.body).foregroundStyle(Theme.ink)
            Text(note).font(.caption).foregroundStyle(Theme.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
