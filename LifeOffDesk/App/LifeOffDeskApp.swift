import SwiftUI

@main
struct LifeOffDeskApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(model)
                .tint(Theme.primary)
                .preferredColorScheme(.light)
                // The map is already loaded underneath; the intro never blocks it beyond one tap.
                .fullScreenCover(isPresented: Binding(get: { !hasSeenIntro && !Self.skipIntro },
                                                      set: { if !$0 { hasSeenIntro = true } })) {
                    OnboardingView(startPage: Self.introStartPage) { hasSeenIntro = true }
                }
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("--show-intro") { hasSeenIntro = false }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appMovedToBackground() }
        }
    }

    /// Test/screenshot helpers: --skip-intro, --show-intro, --intro-page <n>.
    private static var skipIntro: Bool { ProcessInfo.processInfo.arguments.contains("--skip-intro") }
    private static var introStartPage: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--intro-page"), i + 1 < args.count, let n = Int(args[i + 1]) else { return 0 }
        return max(0, min(4, n))
    }
}
