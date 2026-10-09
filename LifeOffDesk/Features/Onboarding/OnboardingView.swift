import SwiftUI

/// Five-page intro shown once on first launch (skippable; re-open from Settings).
/// Founder decision 2026-10-09; it never gates the map behind an account or download.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(startPage: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: startPage)
    }

    private let pages: [(title: String, subtitle: String)] = [
        ("Every street you walk becomes your map.", "The map starts blank. Only where you actually walk is drawn."),
        ("New streets count.", "Turn an unknown corner and your world grows."),
        ("Ask for a nearby spot.", "Type in Taglish. The AI on your phone suggests real places, even offline."),
        ("Stays on your phone.", "No account. Your walks and the AI never leave your iPhone."),
        ("Share your adventure as a card.", "Your route, your photos and the places you found in one card."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PaperStyle.island.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 0) {
                        Spacer()
                        IntroIllustration(page: index, animate: !reduceMotion)
                            .frame(height: 300)
                            .id("\(index)-\(page == index)") // restart the drawing when a page appears
                        Text(pages[index].title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(PaperStyle.ink)
                            .multilineTextAlignment(.center)
                            .padding(.top, 36)
                        Text(pages[index].subtitle)
                            .font(.body)
                            .foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                        Spacer()
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if page < pages.count - 1 {
                Button("Skip", action: onFinish)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                    .padding(.trailing, 20)
            }

            VStack(spacing: 20) {
                Spacer()
                if page == pages.count - 1 {
                    Button("Start exploring", action: onFinish)
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }
                PageDots(count: pages.count, current: page)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .animation(.easeOut(duration: 0.2), value: page)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? PaperStyle.ink : Theme.secondaryInk.opacity(0.35))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(PaperStyle.paper, in: Capsule())
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// Dotted ink routes that draw themselves, echoing the paper map.
private struct IntroIllustration: View {
    let page: Int
    let animate: Bool
    @State private var progress: CGFloat = 0

    private static let dots = StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.1, 13])

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                switch page {
                case 0:
                    route([(0.30, 0.78), (0.36, 0.62), (0.40, 0.55)], in: size)
                    Circle().stroke(PaperStyle.ink, lineWidth: 3).frame(width: 20, height: 20)
                        .position(point(0.30, 0.80, size))
                case 1:
                    Path { p in
                        p.move(to: point(0.12, 0.80, size))
                        p.addLine(to: point(0.38, 0.70, size))
                        p.addLine(to: point(0.48, 0.52, size))
                    }
                    .stroke(Theme.secondaryInk.opacity(0.45), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    route([(0.48, 0.52), (0.58, 0.38), (0.72, 0.32), (0.88, 0.28)], in: size)
                    pill("+0.4 km").position(point(0.66, 0.16, size)).opacity(progress)
                case 2:
                    route([(0.15, 0.85), (0.30, 0.62), (0.52, 0.56), (0.66, 0.40), (0.78, 0.30)], in: size)
                    Text("May 30 mins ako, park sana")
                        .font(.footnote).foregroundStyle(PaperStyle.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(PaperStyle.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .position(point(0.42, 0.14, size))
                    pill("Park 🌳").position(point(0.66, 0.30, size)).opacity(progress)
                    Circle().fill(PaperStyle.ink).frame(width: 14, height: 14).position(point(0.66, 0.40, size))
                        .opacity(progress)
                case 3:
                    route([(0.18, 0.78), (0.34, 0.60), (0.56, 0.62), (0.74, 0.44), (0.84, 0.30)], in: size)
                    Image(systemName: "iphone")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(PaperStyle.ink)
                        .overlay(Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(Theme.primary))
                        .position(point(0.5, 0.20, size))
                default:
                    MiniCard(progress: progress)
                        .frame(width: 210, height: 250)
                        .position(x: size.width / 2, y: size.height / 2)
                }
            }
        }
        .onAppear {
            guard animate else { progress = 1; return }
            progress = 0
            withAnimation(.easeInOut(duration: 1.4).delay(0.15)) { progress = 1 }
        }
    }

    private func point(_ x: CGFloat, _ y: CGFloat, _ size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    private func route(_ points: [(CGFloat, CGFloat)], in size: CGSize) -> some View {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: point(first.0, first.1, size))
            for next in points.dropFirst() { p.addLine(to: point(next.0, next.1, size)) }
        }
        .trim(from: 0, to: progress)
        .stroke(PaperStyle.ink, style: Self.dots)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(PaperStyle.ink)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(PaperStyle.island, in: Capsule())
            .overlay(Capsule().stroke(PaperStyle.ink, lineWidth: 2.5))
    }
}

/// Preview of the memory card for the last intro page.
private struct MiniCard: View {
    let progress: CGFloat

    var body: some View {
        VStack(alignment: .leading) {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                Path { p in
                    p.move(to: CGPoint(x: w * 0.2, y: h * 0.9))
                    p.addLine(to: CGPoint(x: w * 0.35, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w * 0.6, y: h * 0.48))
                    p.addLine(to: CGPoint(x: w * 0.7, y: h * 0.2))
                    p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.12))
                }
                .trim(from: 0, to: progress)
                .stroke(PaperStyle.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [0.1, 10]))
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("+1.1 km").font(.title3.weight(.bold)).foregroundStyle(PaperStyle.ink)
                    Text("New streets").font(.caption).foregroundStyle(Theme.secondaryInk)
                }
                Spacer()
                Image(systemName: "figure.walk")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 32, height: 32)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(20)
        .background(PaperStyle.island, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        .rotationEffect(.degrees(-2))
    }
}
