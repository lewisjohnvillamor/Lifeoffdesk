import LifeOffDeskCore
import SwiftUI

/// Opening screen: the personal map with Start walking and Help me choose somewhere.
struct MapScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var camera = MapCamera()
    @State private var geometry: MapGeometry?
    @State private var showPlanner = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var followUser = true

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if let geometry {
                FogMapView(geometry: geometry, exploration: model.displayExploration,
                           activeSegments: model.displayedTrail,
                           position: model.mapPosition, destination: model.destination,
                           camera: $camera)
                    .ignoresSafeArea()
                    .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in followUser = false })
            } else if let error = model.contentError {
                Text("Starter map could not load: \(error)").foregroundStyle(Theme.danger).padding()
            }

            VStack(spacing: 8) {
                topBar
                statusBanners
                Spacer()
                if !model.demoMode && model.displayExploration.paths.isEmpty && model.phase == .idle {
                    VStack(spacing: 10) {
                        Image(systemName: "cloud.fill").font(.largeTitle)
                        Text("Your world is waiting").font(.title2.weight(.semibold))
                        Text("Streets appear as you walk. Start exploring to lift the fog.")
                            .font(.subheadline).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(24)
                    .background(Theme.canvas.opacity(0.94), in: RoundedRectangle(cornerRadius: 24))
                    Spacer()
                }
                bottomCard
            }
            .padding(.horizontal, Theme.inset)
            .padding(.bottom, 8)
        }
        .onAppear(perform: setUp)
        .onChange(of: model.demoMode) { _, on in
            // Frame the sample area when entering Demo mode.
            if on { camera = MapCamera(center: .zero, pointsPerMeter: 0.12) }
        }
        .onChange(of: model.mapPosition) { _, position in
            guard followUser, let position, let geometry else { return }
            camera.center = geometry.point(position)
        }
        .sheet(isPresented: $showPlanner) { PlannerSheet().environmentObject(model) }
        .sheet(isPresented: $showHistory) { HistoryView().environmentObject(model) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(model) }
        .sheet(item: $model.presentedRecap) { session in
            RecapView(session: session).environmentObject(model)
        }
        .alert("Walk paused", isPresented: Binding(get: { model.recoveredSession != nil },
                                                    set: { if !$0 { model.recoveredSession = nil } })) {
            Button("Resume walking") { model.resume() }
            Button("Finish walk") { model.finish() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Life Off Desk closed during your walk. Tracking stopped and nothing was recorded while it was closed.")
        }
    }

    private func setUp() {
        guard geometry == nil, let content = model.content else { return }
        geometry = MapGeometry(content: content)
        camera.center = .zero
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--demo-map") {
            model.setDemoMode(true)
            camera = MapCamera(center: .zero, pointsPerMeter: 0.12)
        }
        #endif
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            iconButton("clock.arrow.circlepath", label: "Past walks") { showHistory = true }
            Spacer()
            iconButton("location", label: "Center on my location") {
                followUser = true
                if let position = model.currentPosition, let geometry { camera.center = geometry.point(position) }
                else if let destination = model.destination, let geometry { camera.center = geometry.point(destination.coordinate) }
                else { camera.center = .zero }
            }
            iconButton("gearshape", label: "Settings and privacy") { showSettings = true }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: Theme.minTarget, height: Theme.minTarget)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.border))
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder private var statusBanners: some View {
        if model.demoMode {
            banner(icon: "sparkles", text: model.replay == nil
                   ? "DEMO MAP: synthetic sample walks along real streets. Not real GPS or anyone's walks."
                   : "REPLAY of a synthetic sample walk. Not real GPS.",
                   action: ("Exit demo", { model.setDemoMode(false) }))
        }
        if let problem = model.demoProblem {
            banner(icon: "exclamationmark.triangle", text: problem)
        }
        #if targetEnvironment(simulator)
        banner(icon: "desktopcomputer", text: "Simulator · AI unavailable · locations are simulated")
        #endif
        if model.permissionDenied {
            banner(icon: "location.slash", text: "Location is off for Life Off Desk. Walks need it; past walks and planning still work.",
                   action: ("Open Settings", model.openSystemSettings))
        }
        if model.phase == .acquiringFix {
            banner(icon: "location.magnifyingglass", text: "Finding your location…")
        }
        switch model.coverageHere {
        case .outside?:
            banner(icon: "map", text: "Map detail unavailable here. Your trail is still recorded.")
        case let .mainRoadsOnly(name)?:
            banner(icon: "map", text: "Only main roads are mapped here (\(name)). Your trail is still recorded.")
        case .detailed?, nil:
            EmptyView()
        }
        if let error = model.locationError {
            banner(icon: "exclamationmark.triangle", text: "Location problem: \(error)")
        }
        if let problem = model.storeProblem {
            banner(icon: "externaldrive.badge.exclamationmark", text: problem)
        }
    }

    private func banner(icon: String, text: String, action: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.ink).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.0, action: action.1).font(.subheadline.bold()).foregroundStyle(Theme.primary)
                    .frame(minHeight: Theme.minTarget)
            }
        }
        .padding(12)
        .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border))
        .accessibilityElement(children: .combine)
    }

    // MARK: Bottom

    @ViewBuilder private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let destination = model.destination { destinationRow(destination) }
            switch model.phase {
            case .idle where model.demoMode:
                Text("This is how a well-explored map looks.")
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                Button(model.replay == nil ? "Replay a sample walk" : "Replay another sample walk") { model.startReplay() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Back to my map") { model.setDemoMode(false) }
                    .buttonStyle(SecondaryButtonStyle())
            case .idle, .requestingPermission:
                Text("A little walk can open up your world.")
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                Button("Start walking") { model.startWalking() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.phase == .requestingPermission)
                Button("Help me choose somewhere") { showPlanner = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Preview demo map") { model.setDemoMode(true) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
            case .acquiringFix, .walking:
                walkStats
                HStack(spacing: 12) {
                    Button("Pause") { model.pause() }.buttonStyle(SecondaryButtonStyle())
                    Button("Finish") { model.finish() }.buttonStyle(PrimaryButtonStyle())
                }
            case .paused:
                Text("Walk paused").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                walkStats
                HStack(spacing: 12) {
                    Button("Finish") { model.finish() }.buttonStyle(SecondaryButtonStyle())
                    Button("Resume walking") { model.resume() }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .card()
    }

    private var walkStats: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let session = model.activeSession
            HStack(spacing: 24) {
                stat("Distance", Format.distance(session?.distanceMeters ?? 0))
                stat("Active time", Format.duration(session?.activeDuration(at: context.date) ?? 0))
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(Theme.secondaryInk)
            Text(value).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func destinationRow(_ place: Place) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle").foregroundStyle(Theme.ink).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(destinationDetail(place)).font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
            if model.phase == .idle {
                Button { model.clearDestination() } label: {
                    Image(systemName: "xmark").frame(width: Theme.minTarget, height: Theme.minTarget)
                }
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityLabel("Clear destination")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func destinationDetail(_ place: Place) -> String {
        guard let position = model.currentPosition else {
            return "Destination · straight-line distance shown once GPS has a fix · no route"
        }
        return "Destination · \(Format.distance(Geo.distanceMeters(position, place.coordinate))) straight-line · no route or ETA"
    }
}
