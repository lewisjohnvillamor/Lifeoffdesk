import SwiftUI

enum AppTab: Hashable { case map, walks, me }

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(AppTab.map)
            WalksView()
                .tabItem { Label("Adventures", systemImage: "flag.fill") }
                .tag(AppTab.walks)
            MeView()
                .tabItem { Label("Me", systemImage: "person") }
                .tag(AppTab.me)
        }
        .tint(PaperStyle.ink)
        #if targetEnvironment(simulator)
        .onAppear {
            // Screenshot helper: --tab walks|me (simulator only).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--demo-map") { model.setDemoMode(true) }
            if let i = args.firstIndex(of: "--tab"), i + 1 < args.count {
                model.selectedTab = args[i + 1] == "me" ? .me : args[i + 1] == "walks" ? .walks : .map
            }
        }
        #endif
    }
}
