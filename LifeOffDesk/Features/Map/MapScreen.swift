import LifeOffDeskCore
import SwiftUI

/// Map tab: the personal map with floating controls and nothing else in the way.
struct MapScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var camera = MapCamera()
    @State private var geometry: MapGeometry?
    @State private var showPlanner = false
    /// Simulator screenshot helper: the style travels with the item so the sheet never reads a stale value.
    @State private var simCard: SimCard?
    @State private var showCamera = false
    @State private var showHelp = false
    /// Simulator screenshot helper: opens the help chat with a question.
    @State private var simHelpQuestion: SimQuestion?
    /// Photo pin the user tapped on the map.
    @State private var openedMoment: WalkMemory?
    /// A found place tapped on the map.
    @State private var tappedPlace: Place?
    @State private var followUser = true
    @AppStorage("map.tilted") private var tilted = true
    @State private var launchScale: CGFloat?
    /// Destination whose route should be framed once it arrives (set when a place is chosen).
    @State private var routeToFrame: String?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if let geometry {
                FogMapView(geometry: geometry, exploration: model.displayExploration,
                           trailRuns: model.displayedTrailRuns,
                           pins: model.mapMoments.compactMap { m in
                               m.coordinate.map { MapPin(id: m.id, coordinate: $0, image: model.thumbnail(for: m)) }
                           },
                           onPinTap: { id in openedMoment = model.mapMoments.first { $0.id == id } },
                           foundPlaces: model.foundPlaces,
                           onFoundTap: { place in withAnimation(.easeOut(duration: 0.2)) { tappedPlace = place } },
                           position: model.mapPosition, destination: model.destination,
                           route: model.destinationRoute?.points,
                           camera: $camera, tilted: tilted)
                    .ignoresSafeArea()
                    .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in followUser = false })
            } else if let error = model.contentError {
                Text("Starter map could not load: \(error)").foregroundStyle(Theme.danger).padding()
            }

            VStack(spacing: 8) {
                header
                statusBanners
                if model.phase == .idle, let coach = model.coach { coachCard(coach) }
                Spacer()
                HStack(alignment: .bottom) {
                    statsStack
                    Spacer()
                    sideButtons
                }
                centerControls
            }
            .padding(.horizontal, Theme.inset)
            .padding(.bottom, 8)
        }
        .onAppear(perform: setUp)
        #if targetEnvironment(simulator)
        .task {
            // Screenshot helpers that must wait for the first frame (simulator only).
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--open-recap") || arguments.contains("--open-card") else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard model.demoMode, let walk = model.historyWalks.first else { return }
            // --seed-photo: adds the bundled test image (simulator build only) to this sample adventure,
            // exercising photo saving, thumbnails, collage and the sticker cut-out.
            if arguments.contains("--seed-photo"), let image = UIImage(named: "life-off-desk-cat-concept.png") {
                model.addMoment(image, to: walk, at: walk.lastSample?.coordinate)
                model.addMoment(image, to: walk, at: walk.segments.first?.first?.coordinate)
            }
            var style = CardStyle.photo
            if let i = arguments.firstIndex(of: "--card-style"), i + 1 < arguments.count {
                style = CardStyle(rawValue: arguments[i + 1]) ?? .photo
            }
            if arguments.contains("--open-card") { simCard = SimCard(session: walk, style: style) } else { model.presentedRecap = walk }
            // --request-narration: exercises the recap narration path (Simulator has no model, so this
            // shows the labelled computed fallback, never an AI result).
            if arguments.contains("--request-narration") { model.requestNarration(for: walk) }
        }
        .sheet(item: $simCard) { card in
            MemoryCardSheet(session: card.session, initialStyle: card.style).environmentObject(model)
        }
        #endif
        .onChange(of: model.demoMode) { _, on in
            if on { camera = MapCamera(center: .zero, pointsPerMeter: launchScale ?? 0.12) }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .acquiringFix || phase == .walking { followUser = true }
        }
        .onChange(of: model.contentVersion) { _, _ in rebuildGeometry() }
        .onChange(of: model.destination?.id) { _, id in routeToFrame = id }
        .onChange(of: model.destinationRoute) { _, route in
            // Show the whole suggested route once when a place is chosen (not while walking).
            guard let route, let id = routeToFrame, id == model.destination?.id, model.phase == .idle,
                  let geometry else { return }
            routeToFrame = nil
            frame(route.points, using: geometry, padding: 120)
        }
        .onChange(of: camera) { _, camera in reportViewport(camera) }
        // Replays and "Watch your world grow" follow the moving pointer.
        .onChange(of: model.replay?.source.id) { _, id in
            if id != nil { followUser = true }
        }
        .onChange(of: model.mapPosition) { _, position in
            guard followUser, let position, let geometry else { return }
            camera.center = geometry.point(position)
        }
        .sheet(isPresented: $showPlanner) { PlannerSheet().environmentObject(model) }
        .sheet(isPresented: $showHelp) { HelpSheet().environmentObject(model) }
        .sheet(item: $simHelpQuestion) { question in
            NavigationStack { SafetyChatView(initialQuestion: question.text) }.environmentObject(model)
        }
        .sheet(item: $openedMoment) { memory in
            MomentSheet(memory: memory) { session in
                openedMoment = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { model.presentedRecap = session }
            }
            .environmentObject(model)
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { model.captureMoment($0) }.ignoresSafeArea()
        }
        .sheet(item: $model.presentedRecap) { session in
            RecapView(session: session).environmentObject(model)
        }
        .alert("Adventure paused", isPresented: Binding(get: { model.recoveredSession != nil },
                                                    set: { if !$0 { model.recoveredSession = nil } })) {
            Button("Resume walking") { model.resume() }
            Button("Finish") { model.finish() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The app closed during your adventure. Nothing was recorded while it was closed.")
        }
    }

    private func setUp() {
        guard geometry == nil, let content = model.content else { return }
        let built = MapGeometry(content: content)
        geometry = built
        camera.center = .zero
        frameRecentExploration(using: built)
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--demo-map") {
            model.setDemoMode(true)
            camera = MapCamera(center: .zero, pointsPerMeter: 0.12)
        }
        // Screenshot helpers for CI (simulator only).
        if let i = arguments.firstIndex(of: "--map-scale"), i + 1 < arguments.count, let scale = Double(arguments[i + 1]) {
            launchScale = CGFloat(scale)
            camera.pointsPerMeter = CGFloat(scale)
        }
        if arguments.contains("--flat") { tilted = false }
        if arguments.contains("--start-walk") { model.startWalking() } // simulator GPS route is supplied by simctl
        if arguments.contains("--open-help") { showHelp = true }
        if let i = arguments.firstIndex(of: "--help-chat"), i + 1 < arguments.count {
            simHelpQuestion = SimQuestion(text: arguments[i + 1])
        }
        // Draws the street route to a bundled place (simulated GPS position from simctl).
        if let i = arguments.firstIndex(of: "--route-to"), i + 1 < arguments.count,
           let place = model.content?.catalog.place(id: arguments[i + 1]) { model.choose(place) }
        if arguments.contains("--open-planner") {
            showPlanner = true
            if let i = arguments.firstIndex(of: "--planner-filter"), i + 1 < arguments.count,
               let category = PlaceCategory(rawValue: arguments[i + 1]) { model.manualSearch(category: category) }
        }
        #endif
    }

    /// Cities streamed in or out: redraw with the new set off the main thread. The projection
    /// origin never changes, so the camera stays where it is.
    private func rebuildGeometry() {
        guard let content = model.content else { return }
        Task {
            let built = await Task.detached(priority: .userInitiated) { MapGeometry(content: content) }.value
            geometry = built
        }
    }

    /// Tells the model what is on screen so nearby cities stream in. Zoomed far out (wider than
    /// ~12 km) the map shows main roads only and does not pull in every city (level of detail).
    private func reportViewport(_ camera: MapCamera) {
        guard let geometry else { return }
        let size = UIScreen.main.bounds.size
        let halfWidth = Double(size.width / 2 / camera.pointsPerMeter)
        let halfHeight = Double(size.height / 2 / camera.pointsPerMeter)
        guard halfWidth < 6000 else { return }
        let center = MeterPoint(x: Double(camera.center.x), y: Double(camera.center.y))
        let sw = geometry.projection.unproject(MeterPoint(x: center.x - halfWidth, y: center.y - halfHeight))
        let ne = geometry.projection.unproject(MeterPoint(x: center.x + halfWidth, y: center.y + halfHeight))
        model.mapViewportChanged(BoundingBox(south: sw.latitude, west: sw.longitude,
                                             north: ne.latitude, east: ne.longitude))
    }

    /// Open on the user's explored world: frame their most recent walk instead of the Makati origin.
    private func frameRecentExploration(using geometry: MapGeometry) {
        guard let recent = model.historyWalks.max(by: { $0.startedAt < $1.startedAt }) else { return }
        frame(recent.segments.flatMap { $0 }.map(\.coordinate), using: geometry, padding: 250)
    }

    private func frame(_ coordinates: [Coordinate], using geometry: MapGeometry, padding: CGFloat) {
        let points = coordinates.map { geometry.point($0) }
        guard let first = points.first else { return }
        var box = CGRect(origin: first, size: .zero)
        for p in points { box = box.union(CGRect(origin: p, size: .zero)) }
        box = box.insetBy(dx: -padding, dy: -padding)
        let screen = UIScreen.main.bounds.size
        camera = MapCamera(center: CGPoint(x: box.midX, y: box.midY),
                           pointsPerMeter: min(1.2, max(0.05, min(screen.width / box.width, screen.height * 0.6 / box.height))))
        followUser = false
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            roundIcon("sparkles", label: "Help me choose somewhere", size: 48) { showPlanner = true }
            Spacer()
            Text(model.demoMode ? "Demo world" : "There's more to life than your screen.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
            Spacer()
            if model.demoMode {
                roundIcon("xmark", label: "Back to my map", size: 48) { model.setDemoMode(false) }
            } else {
                Color.clear.frame(width: 48, height: 48)
            }
        }
    }

    @ViewBuilder private var statusBanners: some View {
        if let place = model.arrived { arrivedCard(place) }
        if let place = tappedPlace, model.destination?.id != place.id { foundPill(place) }
        if let destination = model.destination {
            destinationPill(destination)
            if let route = model.destinationRoute {
                Text(route.throughRestricted
                     ? "Dashed line: suggested route on mapped streets · passes a private or gated way"
                     : "Dashed line: suggested route on mapped streets · check gates and crossings")
                    .font(.caption2).foregroundStyle(Theme.secondaryInk)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Theme.surface.opacity(0.9), in: Capsule())
                    .accessibilityHidden(true) // the pill's label already says this
            }
        }
        if let problem = model.demoProblem { banner(icon: "exclamationmark.triangle", text: problem) }
        #if targetEnvironment(simulator)
        if !ProcessInfo.processInfo.arguments.contains("--marketing") {
            banner(icon: "desktopcomputer", text: "Simulator · no AI · simulated GPS")
        }
        #endif
        if model.permissionDenied {
            banner(icon: "location.slash", text: "Location is off. Turn it on to record walks.",
                   action: ("Settings", model.openSystemSettings))
        }
        if model.phase == .acquiringFix { banner(icon: "location.magnifyingglass", text: "Finding your location…") }
        switch model.coverageHere {
        case .outside?: banner(icon: "map", text: "No map detail here · still recording")
        case let .mainRoadsOnly(name)?: banner(icon: "map", text: "Main roads only (\(name)) · still recording")
        case .detailed?, nil: EmptyView()
        }
        if let error = model.locationError { banner(icon: "exclamationmark.triangle", text: error) }
        if let problem = model.storeProblem { banner(icon: "externaldrive.badge.exclamationmark", text: problem) }
    }

    private func banner(icon: String, text: String, action: (String, () -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.ink).accessibilityHidden(true)
            Text(text).font(.footnote).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1).font(.footnote.bold()).foregroundStyle(Theme.primary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.surface.opacity(0.95), in: Capsule())
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
    }

    /// "Your world" coach: the on-device AI picks what to say about your computed exploring trend
    /// and which real next step to offer; values and places come from app code.
    private func coachCard(_ card: CoachCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                MascotView(pose: card.signal == .growing ? .celebrating : .encouragement, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.text).font(.subheadline).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(coachCaption(card)).font(.caption2).foregroundStyle(Theme.secondaryInk)
                }
            }
            HStack(spacing: 10) {
                Button("Tara!") { model.acceptCoach() }
                    .buttonStyle(.borderedProminent).tint(Theme.primary)
                    .frame(minHeight: Theme.minTarget)
                    .accessibilityLabel("Let's go: show the route")
                Button("Mamaya na") { model.dismissCoach() }
                    .buttonStyle(.bordered).tint(Theme.ink)
                    .frame(minHeight: Theme.minTarget)
                    .accessibilityLabel("Not today")
            }
        }
        .padding(14)
        .background(Theme.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: Theme.corner))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
    }

    private func coachCaption(_ card: CoachCard) -> String {
        var parts: [String] = []
        switch card.status {
        case .working: parts.append("On-device AI is thinking… · computed for now")
        case .ai: parts.append("On-device AI · numbers from your adventures")
        case let .computed(reason): parts.append("Computed suggestion" + (reason.isEmpty ? "" : " · \(reason)"))
        }
        if card.sample { parts.append("SAMPLE DATA") }
        return parts.joined(separator: " · ")
    }

    /// Shown once when the walk reaches the chosen destination; the route has already cleared.
    private func arrivedCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered").font(.title3).foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nakarating ka na!").font(.headline).foregroundStyle(Theme.ink)
                    Text("You've arrived at \(place.name).").font(.subheadline).foregroundStyle(Theme.secondaryInk)
                }
            }
            HStack(spacing: 10) {
                Button { model.arrived = nil; model.finish() } label: {
                    Text("End adventure").font(.subheadline.weight(.semibold)).padding(.horizontal, 14)
                        .frame(minHeight: Theme.minTarget)
                        .background(Theme.primary, in: Capsule()).foregroundStyle(Theme.canvas)
                }
                Button { model.arrived = nil } label: {
                    Text("Keep exploring").font(.subheadline.weight(.semibold)).padding(.horizontal, 14)
                        .frame(minHeight: Theme.minTarget)
                        .background(Theme.revealedGround, in: Capsule()).foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: Theme.corner))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// A found place tapped on the map: its name, and a way to go there again.
    private func foundPill(_ place: Place) -> some View {
        HStack(spacing: 6) {
            Image(systemName: PlaceIcon.symbol(place)).font(.caption).foregroundStyle(PlaceIcon.tint(place))
                .accessibilityHidden(true)
            Text(place.name).font(.footnote.weight(.semibold)).lineLimit(1)
            Text("· found").font(.footnote).foregroundStyle(Theme.secondaryInk)
            if model.phase == .idle {
                Button("Go again") { model.choose(place); tappedPlace = nil }
                    .font(.footnote.bold()).foregroundStyle(Theme.primary)
            }
            Button { tappedPlace = nil } label: { Image(systemName: "xmark").font(.caption.bold()) }
                .frame(width: 28, height: 28)
                .accessibilityLabel("Close")
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 4)
        .background(Theme.surface, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
    }

    private func destinationPill(_ place: Place) -> some View {
        HStack(spacing: 6) {
            Image(systemName: PlaceIcon.symbol(place)).font(.caption).foregroundStyle(PlaceIcon.tint(place))
                .accessibilityHidden(true)
            Text(place.name).font(.footnote.weight(.semibold)).lineLimit(1)
            if let position = model.currentPosition {
                Text("· " + PlannerCopy.distanceText(model.destinationStreet, straightLine: Geo.distanceMeters(position, place.coordinate)))
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            if model.phase == .idle {
                Button { model.clearDestination() } label: { Image(systemName: "xmark").font(.caption.bold()) }
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Clear destination")
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 4)
        .background(Theme.surface, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.destinationRoute == nil
            ? "Destination \(place.name). Straight-line distance only, no street route."
            : "Destination \(place.name). Suggested route along mapped streets drawn on the map; check gates and crossings.")
    }

    // MARK: Stats and side buttons

    private var statsStack: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                if let session = model.activeSession {
                    statRow("timer", "This adventure", Format.duration(session.activeDuration(at: context.date)),
                            unit: Format.distance(session.distanceMeters))
                }
                let today = Format.distanceParts(model.todayNewDistanceMeters)
                statRow("pencil.line", "New streets today", today.value, unit: today.unit)
                statRow("sparkles", "Places found", "\(model.discoveredPlaceIDs.count)", unit: "")
            }
        }
    }

    private func statRow(_ icon: String, _ title: String, _ value: String, unit: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.secondaryInk).frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(Theme.secondaryInk)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(PaperStyle.ink)
                    Text(unit).font(.caption).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sideButtons: some View {
        VStack(spacing: 14) {
            if model.phase == .walking || model.phase == .acquiringFix || model.phase == .paused {
                labeledIcon("camera", "Spot", label: "Take a photo") { showCamera = true }
            }
            labeledIcon("sos", "Help", tint: Theme.danger,
                        label: "Get help: emergency call, your location and the nearest police, hospitals and fire stations") {
                showHelp = true
            }
            labeledIcon("scope", "Locate", label: "Center on my location") {
                followUser = true
                if let position = model.mapPosition, let geometry { camera.center = geometry.point(position) }
                else if let destination = model.destination, let geometry { camera.center = geometry.point(destination.coordinate) }
                else { camera.center = .zero }
            }
        }
    }

    // MARK: Center controls

    @ViewBuilder private var centerControls: some View {
        switch model.phase {
        case .idle where model.demoMode:
            // Same big walk button as "Start exploring", so the demo feels like the real app.
            labeledIcon("figure.walk", model.replay == nil ? "Play a sample adventure" : "Next sample adventure",
                        label: "Play a sample adventure", primary: true, size: 76) { model.startReplay() }
        case .idle, .requestingPermission:
            labeledIcon("figure.walk", "Start exploring", label: "Start exploring", primary: true, size: 76) { model.startWalking() }
                .disabled(model.phase == .requestingPermission)
        case .acquiringFix, .walking:
            HStack(spacing: 28) {
                labeledIcon("pause.fill", "Pause", label: "Pause", size: 68) { model.pause() }
                HoldToEndButton { model.finish() }
            }
        case .paused:
            VStack(spacing: 8) {
                Text("Paused").font(.subheadline.weight(.semibold)).foregroundStyle(PaperStyle.ink)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                HStack(spacing: 28) {
                    labeledIcon("play.fill", "Resume", label: "Resume walking", size: 68) { model.resume() }
                    HoldToEndButton { model.finish() }
                }
            }
        }
    }

    // MARK: Building blocks

    private func circle(_ symbol: String, size: CGFloat, primary: Bool = false, tint: Color? = nil) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(primary || tint != nil ? Theme.canvas : PaperStyle.ink)
            .frame(width: size, height: size)
            .background(tint ?? (primary ? Theme.primary : Theme.surface), in: Circle())
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }

    private func labeledIcon(_ symbol: String, _ caption: String, tint: Color? = nil, label: String, primary: Bool = false,
                             size: CGFloat = 56, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                circle(symbol, size: size, primary: primary, tint: tint)
                Text(caption).font(.caption).foregroundStyle(Theme.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func roundIcon(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { circle(symbol, size: size) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

/// Finish requires a short hold so a walk is never ended by accident. VoiceOver gets a direct action.
struct HoldToEndButton: View {
    let onEnd: () -> Void
    @State private var progress: CGFloat = 0
    private let duration = 0.9

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(PaperStyle.ink)
                Circle().trim(from: 0, to: progress)
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                Image(systemName: "stop.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.canvas)
            }
            .frame(width: 68, height: 68)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .onLongPressGesture(minimumDuration: duration, pressing: { pressing in
                withAnimation(pressing ? .linear(duration: duration) : .easeOut(duration: 0.2)) { progress = pressing ? 1 : 0 }
            }, perform: {
                progress = 0
                onEnd()
            })
            Text("Hold to end").font(.caption).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finish")
        .accessibilityHint("Touch and hold to end the adventure")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onEnd() }
    }
}

private struct SimCard: Identifiable {
    let session: WalkSession
    let style: CardStyle
    var id: UUID { session.id }
}

/// Simulator screenshot helper item for the help chat sheet.
struct SimQuestion: Identifiable {
    let text: String
    var id: String { text }
}
