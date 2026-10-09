import CoreImage
import LifeOffDeskCore
import PhotosUI
import SwiftUI
import Vision

enum CardStyle: String, CaseIterable, Identifiable {
    case photo = "Photo", collage = "Collage", sticker = "Sticker"
    var id: String { rawValue }
}

/// Shareable 9:16 walk memory: the user's photos, the real route, computed numbers.
struct MemoryCardView: View {
    static let size = CGSize(width: 360, height: 640)

    let session: WalkSession
    let recap: WalkRecap
    var style: CardStyle = .photo
    var photos: [UIImage] = []
    var selected: Int = 0
    /// Subject cut-out for the sticker style (nil = use the photo with a white border).
    var sticker: UIImage?
    let isSample: Bool

    private var textColor: Color { style == .sticker ? PaperStyle.ink : .white }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            if style != .sticker {
                LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom)
            }
            RouteOverlay(segments: session.segments, label: session.destinationName,
                         color: style == .sticker ? PaperStyle.ink : .white)
                .padding(.horizontal, 44)
                .padding(.top, style == .sticker ? 70 : 110)
                .padding(.bottom, style == .sticker ? 330 : 220)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(Self.dateText(session.startedAt)).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if isSample {
                        Text("SAMPLE DATA")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
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
                            .font(.system(size: 11)).opacity(0.85).padding(.top, 2)
                    }
                    Spacer()
                    BrandBadge(onPaper: style == .sticker)
                }
            }
            .foregroundStyle(textColor)
            .padding(22)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .photo:
            if photos.indices.contains(selected) { fill(photos[selected]) } else { forest }
        case .collage:
            if photos.isEmpty { forest } else { collage }
        case .sticker:
            ZStack {
                PaperStyle.island
                Rectangle().fill(ImagePaint(image: PaperStyle.fiberTile, scale: 0.5)).opacity(0.6)
                if photos.indices.contains(selected) {
                    StickerView(cutout: sticker, photo: photos[selected])
                        .frame(width: 250, height: 250)
                        .rotationEffect(.degrees(-4))
                        .offset(y: 70)
                }
            }
        }
    }

    private var forest: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x46785B), Color(hex: 0x283A31)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(ImagePaint(image: PaperStyle.fiberTile, scale: 0.5)).opacity(0.35)
        }
    }

    private func fill(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().scaledToFill()
            .frame(width: Self.size.width, height: Self.size.height).clipped()
    }

    /// Up to four photos: 1 full, 2 stacked, 3 = one big + two small, 4 = grid.
    private var collage: some View {
        let shown = Array(photos.prefix(4))
        let w = Self.size.width, h = Self.size.height, gap: CGFloat = 3
        func tile(_ i: Int, _ width: CGFloat, _ height: CGFloat) -> some View {
            Image(uiImage: shown[i]).resizable().scaledToFill().frame(width: width, height: height).clipped()
        }
        return Group {
            switch shown.count {
            case 1: tile(0, w, h)
            case 2: VStack(spacing: gap) { tile(0, w, (h - gap) / 2); tile(1, w, (h - gap) / 2) }
            case 3:
                VStack(spacing: gap) {
                    tile(0, w, h * 0.55)
                    HStack(spacing: gap) { tile(1, (w - gap) / 2, h * 0.45 - gap); tile(2, (w - gap) / 2, h * 0.45 - gap) }
                }
            default:
                VStack(spacing: gap) {
                    HStack(spacing: gap) { tile(0, (w - gap) / 2, (h - gap) / 2); tile(1, (w - gap) / 2, (h - gap) / 2) }
                    HStack(spacing: gap) { tile(2, (w - gap) / 2, (h - gap) / 2); tile(3, (w - gap) / 2, (h - gap) / 2) }
                }
            }
        }
        .frame(width: w, height: h)
        .background(.white)
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

/// Die-cut sticker: the lifted subject with a thick white outline, or the photo with a white border.
struct StickerView: View {
    let cutout: UIImage?
    let photo: UIImage

    var body: some View {
        if let cutout {
            ZStack {
                // White outline: the subject's silhouette offset in a ring behind it.
                ForEach(0..<16, id: \.self) { i in
                    let angle = Double(i) / 16 * 2 * .pi
                    Image(uiImage: cutout).resizable().renderingMode(.template).scaledToFit()
                        .foregroundStyle(.white)
                        .offset(x: cos(angle) * 7, y: sin(angle) * 7)
                }
                Image(uiImage: cutout).resizable().scaledToFit()
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        } else {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: 220, height: 220).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(9)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        }
    }

    /// iOS 17 on-device subject lifting. Returns nil where unsupported (e.g. Simulator) or no subject.
    static func liftSubject(from image: UIImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let cg = image.cgImage else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: image.cgOrientation)
            do {
                try handler.perform([request])
                guard let result = request.results?.first else { return nil }
                let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                            croppedToInstancesExtent: true)
                let ci = CIImage(cvPixelBuffer: buffer)
                guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
                return UIImage(cgImage: out)
            } catch {
                return nil
            }
        }.value
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

/// The accepted route fitted into the card as dots, with start/end markers and a place pill.
struct RouteOverlay: View {
    let segments: [[TrackSample]]
    let label: String?
    var color: Color = .white

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
                .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round, dash: [0.1, 9]))
                .shadow(color: .black.opacity(color == .white ? 0.35 : 0), radius: 3)
                if let start = fitted.first?.first {
                    Circle().stroke(color, lineWidth: 3).frame(width: 12, height: 12).position(start)
                }
                if let end = fitted.last?.last {
                    Circle().fill(color).frame(width: 12, height: 12).position(end)
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
    var onPaper = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "figure.walk")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(onPaper ? Theme.canvas : Theme.primary)
                .frame(width: 46, height: 46)
                .background(onPaper ? Theme.primary : Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Life Off Desk").font(.system(size: 10, weight: .semibold))
        }
    }
}

/// Choose a style and photo (from the walk, the library, or a final shot), preview, share.
struct MemoryCardSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: WalkSession
    @State private var style: CardStyle = .photo
    @State private var selected = 0
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var sticker: UIImage?
    @State private var liftingFor: Int?

    var body: some View {
        let recap = model.recap(for: session)
        let photos = model.moments(for: session).compactMap { model.photo(for: $0) }
        let card = MemoryCardView(session: session, recap: recap, style: style, photos: photos,
                                  selected: min(selected, max(0, photos.count - 1)), sticker: sticker,
                                  isSample: model.isDemo(session))
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    card
                        .scaleEffect(0.72)
                        .frame(width: MemoryCardView.size.width * 0.72, height: MemoryCardView.size.height * 0.72)
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                    Picker("Style", selection: $style) {
                        ForEach(CardStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    photoStrip(photos)
                    if let image = render(card) {
                        ShareLink(item: image, preview: SharePreview("Life Off Desk walk", image: image)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(Theme.inset)
            }
            .background(Theme.canvas)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { add($0, photosCount: photos.count) }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                add(image, photosCount: photos.count)
                pickerItem = nil
            }
        }
        .task(id: "\(style.rawValue)-\(selected)-\(photos.count)") {
            guard style == .sticker, photos.indices.contains(selected), liftingFor != selected else { return }
            liftingFor = selected
            sticker = await StickerView.liftSubject(from: photos[selected])
        }
    }

    private func add(_ image: UIImage, photosCount: Int) {
        // Photos added after the walk get no location: there is no live fix to attach honestly.
        model.addMoment(image, to: session, at: nil)
        selected = photosCount
        liftingFor = nil
        sticker = nil
    }

    private func photoStrip(_ photos: [UIImage]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { showCamera = true } label: { stripIcon("camera.fill") }
                    .accessibilityLabel("Take a final photo")
                PhotosPicker(selection: $pickerItem, matching: .images) { stripIcon("photo.badge.plus") }
                    .accessibilityLabel("Add from library")
                ForEach(photos.indices, id: \.self) { i in
                    Button {
                        selected = i
                        liftingFor = nil
                        sticker = nil
                    } label: {
                        Image(uiImage: photos[i]).resizable().scaledToFill()
                            .frame(width: 60, height: 60).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(i == selected ? Theme.primary : .clear, lineWidth: 3))
                    }
                    .accessibilityLabel("Photo \(i + 1)")
                }
            }
        }
    }

    private func stripIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 60, height: 60)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
    }

    @MainActor private func render(_ card: MemoryCardView) -> Image? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
