import LifeOffDeskCore
import PhotosUI
import SwiftUI

/// Shareable 9:16 walk memory: the user's photo, the real route, computed numbers.
struct MemoryCardView: View {
    static let size = CGSize(width: 360, height: 640)

    let session: WalkSession
    let recap: WalkRecap
    let photo: UIImage?
    let isSample: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
            RouteOverlay(segments: session.segments, label: session.destinationName)
                .padding(.horizontal, 44)
                .padding(.top, 110)
                .padding(.bottom, 220)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(Self.dateText(session.startedAt))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if isSample {
                        Text("SAMPLE DATA")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("+\(Self.km(recap.newDistanceMeters))")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                            Text("km").font(.system(size: 15, weight: .semibold))
                            Text("New streets").font(.system(size: 13, weight: .medium)).padding(.leading, 6)
                        }
                        Text("\(Self.km(recap.distanceMeters)) km · \(Self.minutes(recap.activeDuration)) min")
                            .font(.system(size: 14, weight: .medium))
                        Text("There's more to life than your screen.")
                            .font(.system(size: 11)).opacity(0.85)
                            .padding(.top, 2)
                    }
                    Spacer()
                    BrandBadge()
                }
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var background: some View {
        if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height).clipped()
        } else {
            // No photo yet: brand forest backdrop with paper texture.
            ZStack {
                LinearGradient(colors: [Color(hex: 0x46785B), Color(hex: 0x283A31)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(ImagePaint(image: PaperStyle.fiberTile, scale: 0.5)).opacity(0.35)
            }
        }
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy.M.d EEE"
        return f.string(from: date)
    }

    static func km(_ meters: Double) -> String { String(format: "%.2f", meters / 1000) }
    static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }
}

/// The accepted route fitted into the card, white line with start/end dots and a place pill.
struct RouteOverlay: View {
    let segments: [[TrackSample]]
    let label: String?

    var body: some View {
        GeometryReader { proxy in
            let fitted = fit(in: proxy.size)
            ZStack {
                Path { path in
                    for segment in fitted {
                        guard let first = segment.first else { continue }
                        path.move(to: first)
                        for p in segment.dropFirst() { path.addLine(to: p) }
                    }
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.35), radius: 4)
                if let start = fitted.first?.first {
                    Circle().stroke(.white, lineWidth: 3).frame(width: 12, height: 12).position(start)
                }
                if let end = fitted.last?.last {
                    Circle().fill(.white).frame(width: 12, height: 12).position(end)
                    if let label {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.85), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1))
                            .position(x: min(max(end.x, 60), proxy.size.width - 60), y: end.y + 26)
                    }
                }
            }
        }
    }

    private func fit(in size: CGSize) -> [[CGPoint]] {
        guard let origin = segments.first?.first?.coordinate else { return [] }
        let projection = LocalProjection(origin: origin)
        let projected = segments.map { $0.map { projection.project($0.coordinate) } }
        let xs = projected.flatMap { $0.map(\.x) }, ys = projected.flatMap { $0.map(\.y) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let span = max(maxX - minX, maxY - minY, 50)
        let scale = Double(min(size.width, size.height)) / span
        let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
        return projected.map { segment in
            segment.map { CGPoint(x: Double(size.width) / 2 + ($0.x - midX) * scale,
                                  y: Double(size.height) / 2 - ($0.y - midY) * scale) }
        }
    }
}

struct BrandBadge: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "figure.walk")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 46, height: 46)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Life Off Desk").font(.system(size: 10, weight: .semibold))
        }
    }
}

/// Pick a photo, preview the card, share or save it.
struct MemoryCardSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: WalkSession
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?

    var body: some View {
        let recap = model.recap(for: session)
        let isSample = model.isDemo(session)
        let card = MemoryCardView(session: session, recap: recap, photo: photo, isSample: isSample)
        NavigationStack {
            VStack(spacing: 20) {
                card
                    .scaleEffect(0.82)
                    .frame(width: MemoryCardView.size.width * 0.82, height: MemoryCardView.size.height * 0.82)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? "Add photo" : "Change", systemImage: "photo")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if let image = render(card) {
                        ShareLink(item: image, preview: SharePreview("Life Off Desk walk", image: image)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.inset)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { photo = model.memoryPhoto(for: session) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                photo = image
                model.saveMemoryPhoto(image, for: session)
            }
        }
    }

    @MainActor private func render(_ card: MemoryCardView) -> Image? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
