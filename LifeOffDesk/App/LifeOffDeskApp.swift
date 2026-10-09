import SwiftUI

@main
struct LifeOffDeskApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(model)
                .tint(Theme.primary)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appMovedToBackground() }
        }
    }
}
