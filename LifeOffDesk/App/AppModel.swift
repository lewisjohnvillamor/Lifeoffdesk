import Foundation
import LifeOffDeskCore
import SwiftUI
import UIKit

enum WalkPhase: Equatable {
    case idle
    case requestingPermission
    /// Walk started, no accepted fix yet: never draw a fabricated position.
    case acquiringFix
    case walking
    case paused
}

enum PlannerState: Equatable {
    case idle
    case locating
    case loadingModel
    case thinking
    case answered(PlannerResponse, usedAI: Bool)
    case modelUnavailable(String)
}

@MainActor
final class AppModel: ObservableObject {
    // Bundled starter area
    let content: StarterContent?
    let contentError: String?
    let grid: ExplorationGrid

    // Personal data
    private let store: LocalStore?
    @Published private(set) var storeProblem: String?
    @Published private(set) var exploration = Exploration()
    @Published private(set) var finishedWalks: [WalkSession] = []

    // Walking
    @Published private(set) var recorder: WalkRecorder?
    @Published private(set) var phase: WalkPhase = .idle
    @Published private(set) var lastFix: TrackSample?
    @Published private(set) var lastFixReceivedAt: Date?
    @Published private(set) var lastRejection: RejectionReason?
    @Published var permissionDenied = false
    @Published var locationError: String?
    @Published var recoveredSession: WalkSession?
    @Published var presentedRecap: WalkSession?

    // Planner
    @Published var destination: Place?
    @Published var plannerText = ""
    @Published private(set) var plannerState: PlannerState = .idle
    @Published private(set) var lastTrace: PlannerTrace?
    @Published var searchRadiusMeters: Double = SearchOptions.defaultRadiusMeters
    private var plannerTask: Task<Void, Never>?

    // Demo mode: bundled synthetic walks for presentations, never mixed with personal data.
    @Published private(set) var demoMode = false
    @Published private(set) var replay: WalkReplay?
    @Published private(set) var demoProblem: String?
    private(set) var demo: DemoDataset?
    private var demoExploration = Exploration()
    private var replayTask: Task<Void, Never>?
    private var replayIndex = 0

    @Published var selectedTab: AppTab = .map

    let ai = AIService()
    private let location = LocationService()
    private var lastPersist = Date.distantPast
    private var startPending = false

    init() {
        do {
            let loaded = try StarterContent.loadFromBundle()
            content = loaded
            contentError = nil
            grid = ExplorationGrid(origin: loaded.region.center)
        } catch {
            content = nil
            contentError = "\(error)"
            grid = ExplorationGrid(origin: Coordinate(latitude: 14.5566, longitude: 121.0244))
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        do {
            store = try LocalStore(directory: support.appendingPathComponent("Personal", isDirectory: true))
        } catch {
            store = nil
            storeProblem = "Saving is unavailable: \(error.localizedDescription)"
        }

        location.onSamples = { [weak self] samples in
            MainActor.assumeIsolated { self?.handle(samples) }
        }
        location.onAuthorizationChange = { [weak self] status in
            MainActor.assumeIsolated { self?.authorizationChanged(status) }
        }
        location.onError = { [weak self] message in
            // One-shot fixes outside a walk fail quietly; only walking errors need a banner.
            MainActor.assumeIsolated { if self?.recorder != nil { self?.locationError = message } }
        }
        loadPersonalData()
        refreshStats()
        buildStreetNetwork()
        refreshIdleLocation()
    }

    // MARK: Loading and recovery

    private func loadPersonalData() {
        guard let store else { return }
        exploration = store.loadExploration() ?? Exploration()
        finishedWalks = store.loadFinishedWalks()
        moments = store.loadMoments()
        if let active = store.loadActiveSession() {
            if finishedWalks.contains(where: { $0.id == active.id }) {
                // Crashed between saving the finished walk and clearing the active file.
                try? store.clearActiveSession()
            } else {
                let recovered = WalkRecorder.recover(active)
                try? store.saveActiveSession(recovered)
                recorder = WalkRecorder(session: recovered)
                phase = .paused
                if recovered.wasRecovered && active.state == .walking { recoveredSession = recovered }
                if let id = recovered.destinationPlaceID { destination = content?.catalog.place(id: id) }
            }
        }
        if !store.issues.isEmpty {
            storeProblem = store.issues.map(\.message).joined(separator: " ")
        }
    }

    // MARK: Derived state

    var activeSession: WalkSession? { recorder?.session }

    /// Saved exploration plus the walk in progress, for rendering. In Demo mode: the sample
    /// walks plus any replay in progress, and nothing personal.
    // MARK: Street matching

    /// Built once in the background from bundled roads; nil until ready (legacy strip until then).
    private(set) var streetNetwork: StreetNetwork?
    /// Matched-street reveal of the shown history (from `stats`), used for the paper island.
    @Published private(set) var streetReveal: Exploration?
    private var liveCache: (key: String, reveal: [ExploredPath], runs: [TrailRun])?

    private func buildStreetNetwork() {
        guard let content else { return }
        Task { [weak self] in
            let network = await Task.detached(priority: .utility) {
                StreetNetwork(roads: content.matchingRoads, origin: content.region.center)
            }.value
            self?.streetNetwork = network
            self?.refreshStats()
        }
    }

    /// Street match of the live adventure (or replay), cached until it gains samples.
    private func liveMatch() -> (reveal: [ExploredPath], runs: [TrailRun])? {
        guard let network = streetNetwork else { return nil }
        let segments = displayedTrail
        guard let id = replay?.source.id ?? recorder?.session.id, !segments.isEmpty else { return nil }
        let count = segments.reduce(0) { $0 + $1.count }
        let key = "\(id)-\(count)-\(segments.last?.last?.timestamp.timeIntervalSinceReferenceDate ?? 0)"
        if let liveCache, liveCache.key == key { return (liveCache.reveal, liveCache.runs) }
        var prior = StreetCoverage()
        for (walkID, coverage) in stats.coverageByWalk where walkID != id { prior.merge(coverage) }
        let matched = StreetMatcher.match(segments, network: network)
        let reveal = matched.coverage.pieces(in: network).map {
            ExploredPath(sessionID: id, points: $0.points.map(network.projection.unproject))
        } + matched.unmatched.map { ExploredPath(sessionID: id, points: $0) }
        let runs = matched.coverage.pieces(in: network, prior: prior).map {
            TrailRun(points: $0.points.map(network.projection.unproject), isNew: $0.isNew)
        } + matched.unmatched.map { TrailRun(points: $0, isNew: true) }
        liveCache = (key, reveal, runs)
        return (reveal, runs)
    }

    /// What the map reveals: matched streets (paper ribbons along real streets) once the street
    /// network is ready, otherwise the raw GPS corridor.
    var displayExploration: Exploration {
        guard streetNetwork != nil, let reveal = streetReveal else { return rawDisplayExploration }
        var base = timelapseBase ?? reveal
        if timelapseBase == nil, let replay { base = base.excluding(sessionID: replay.source.id) }
        if let live = liveMatch() { base.paths += live.reveal }
        return base
    }

    private var rawDisplayExploration: Exploration {
        if var base = timelapseBase {
            if let replay { base.merge(replay.partialSession) }
            return base
        }
        if demoMode {
            guard let replay else { return demoExploration }
            var shown = demoExploration.excluding(sessionID: replay.source.id)
            shown.merge(replay.partialSession)
            return shown
        }
        guard let session = recorder?.session else { return exploration }
        var merged = exploration
        merged.merge(session)
        return merged
    }

    /// Trail drawn on top of the fog: the live walk, or the replay in Demo mode.
    /// Trail split into new ground (drawn dotted) and revisits (drawn solid grey).
    var displayedTrailRuns: [TrailRun] {
        liveMatch()?.runs ?? grid.trailRuns(for: displayedTrail, prior: priorCells)
    }

    var displayedTrail: [[TrackSample]] {
        if demoMode || timelapseBase != nil { return replay?.partialSession.segments ?? [] }
        return recorder?.session.segments ?? []
    }

    /// Marker position: live GPS, or the replay's current sample (labelled) in Demo mode.
    var mapPosition: Coordinate? {
        (demoMode || timelapseBase != nil) ? replay?.currentSample?.coordinate : currentPosition
    }

    var historyWalks: [WalkSession] { demoMode ? (demo?.walks ?? []) : finishedWalks }

    func isDemo(_ session: WalkSession) -> Bool { demo?.contains(session) ?? false }

    /// A fix only counts as "you are here" while it is recent (30 s walking, 5 min from a one-shot fix).
    var currentPosition: Coordinate? {
        guard let lastFix, let at = lastFixReceivedAt else { return nil }
        let limit: TimeInterval = recorder?.session.state == .walking ? 30 : 300
        return Date().timeIntervalSince(at) < limit ? lastFix.coordinate : nil
    }

    /// One-shot fixes outside a walk: shown as "you are here" and used for planning; never trail.
    private func handleIdleFix(_ samples: [TrackSample]) {
        let now = Date()
        guard let best = samples.filter({ $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 100
                                            && now.timeIntervalSince($0.timestamp) < 60 })
                                 .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else { return }
        lastFix = best
        lastFixReceivedAt = now
    }

    /// Ask for a fresh position when planning or choosing a destination (prompts once if needed).
    func refreshIdleLocation(promptIfNeeded: Bool = false) {
        switch location.authorization {
        case .authorized: location.requestOneShot()
        case .notDetermined where promptIfNeeded: location.requestPermission()
        default: break
        }
    }

    /// Coverage at the live position; nil when there is no recent fix.
    var coverageHere: StarterContent.Coverage? {
        guard let content, let position = currentPosition else { return nil }
        return content.coverage(at: position)
    }

    var distanceOrigin: DistanceOrigin? {
        guard let content else { return nil }
        if let position = currentPosition { return .currentLocation(position) }
        return .areaCenter(content.region.center)
    }

    // MARK: Walk commands

    func startWalking() {
        guard recorder == nil else { return }
        if demoMode { setDemoMode(false) } // real walks always start from personal data
        locationError = nil
        switch location.authorization {
        case .authorized:
            beginSession()
        case .notDetermined:
            startPending = true
            phase = .requestingPermission
            location.requestPermission()
        case .denied, .restricted:
            permissionDenied = true
            phase = .idle
        }
    }

    private func authorizationChanged(_ status: LocationService.Authorization) {
        permissionDenied = status == .denied || status == .restricted
        if status == .authorized && recorder == nil && !startPending { location.requestOneShot() }
        guard startPending else {
            if permissionDenied && phase == .walking { location.stop() }
            return
        }
        switch status {
        case .authorized:
            startPending = false
            beginSession()
        case .denied, .restricted:
            startPending = false
            phase = .idle
        case .notDetermined:
            break
        }
    }

    private func beginSession() {
        ai.unload() // keep the model out of memory while tracking
        let new = WalkRecorder.start(at: Date(), destinationPlaceID: destination?.id, destinationName: destination?.name)
        recorder = new
        lastFix = nil
        lastFixReceivedAt = nil
        priorCells = []
        priorCellsReady = false
        phase = .acquiringFix
        persistActive(force: true)
        location.start()
    }

    func pause() {
        guard var current = recorder else { return }
        do { try current.pause(at: Date()) } catch { return }
        recorder = current
        location.stop()
        phase = .paused
        persistActive(force: true)
    }

    func resume() {
        guard var current = recorder else { return }
        guard location.authorization == .authorized else {
            permissionDenied = true
            return
        }
        do { try current.resume(at: Date()) } catch { return }
        recorder = current
        recoveredSession = nil
        phase = current.session.acceptedSampleCount == 0 ? .acquiringFix : .walking
        persistActive(force: true)
        location.start()
    }

    func finish() {
        guard var current = recorder else { return }
        location.stop()
        current.finish(at: Date())
        let session = current.session
        exploration.merge(session)
        if let store {
            do {
                try store.saveExploration(exploration)
                try store.commitFinished(session)
            } catch {
                storeProblem = "Could not save this walk: \(error.localizedDescription)"
            }
        }
        finishedWalks.insert(session, at: 0)
        refreshStats()
        recorder = nil
        recoveredSession = nil
        phase = .idle
        presentedRecap = session
    }

    /// Recap measured against walks that started earlier (cached in `stats` when available).
    func recap(for session: WalkSession) -> WalkRecap {
        if let cached = stats.recaps[session.id] { return cached }
        var earlier = Exploration()
        for walk in historyWalks where walk.startedAt < session.startedAt && walk.id != session.id { earlier.merge(walk) }
        return WalkRecap.compute(session: session, exploration: earlier, grid: grid, now: session.endedAt ?? Date())
    }

    // MARK: History stats

    @Published private(set) var stats = WalkStats.empty
    private var statsTask: Task<Void, Never>?

    /// Places each adventure passed (within 40 m of its accepted trail).
    @Published private(set) var discoveries: [UUID: [Place]] = [:]

    var discoveredPlaceIDs: Set<String> { Set(discoveries.values.flatMap { $0.map(\.id) }) }

    /// Recomputes lifetime/per-adventure stats and discoveries off the main thread.
    func refreshStats() {
        statsTask?.cancel()
        let walks = historyWalks
        let grid = self.grid
        let catalog = content?.catalog
        let network = streetNetwork
        statsTask = Task { [weak self] in
            let (computed, found, reveal) = await Task.detached(priority: .utility) { () -> (WalkStats, [UUID: [Place]], Exploration?) in
                let stats = WalkStats.compute(walks: walks, grid: grid, network: network)
                var found: [UUID: [Place]] = [:]
                if let catalog { for walk in walks { found[walk.id] = Discovery.placesPassed(by: walk, in: catalog) } }
                let reveal = network.map {
                    StreetReveal.exploration(coverage: stats.coverageByWalk, unmatched: stats.unmatchedByWalk, network: $0)
                }
                return (stats, found, reveal)
            }.value
            guard !Task.isCancelled else { return }
            self?.stats = computed
            self?.discoveries = found
            self?.streetReveal = reveal
            self?.liveCache = nil
        }
    }

    func discovered(in session: WalkSession) -> [Place] {
        if let cached = discoveries[session.id] { return cached }
        guard let catalog = content?.catalog else { return [] }
        return Discovery.placesPassed(by: session, in: catalog)
    }

    // MARK: Next adventure

    @Published private(set) var adventureIdeas: [AdventureIdea] = []

    /// Real targets only: undiscovered catalogue places matching the user's taste, and computed
    /// street frontiers (unexplored street length near them). Distances are straight-line.
    func refreshAdventureIdeas() {
        guard let content else { return }
        let origin = currentPosition ?? historyWalks.max(by: { $0.startedAt < $1.startedAt })?.lastSample?.coordinate
            ?? content.region.center
        let exploration = displayExploration
        let grid = self.grid
        let discoveredIDs = discoveredPlaceIDs
        let taste = AdventureSuggester.favouriteCategories(discoveries.values.flatMap { $0 } + (destination.map { [$0] } ?? []))
        let roadContexts = content.packs.map(\.roads)
        let catalog = content.catalog
        let network = streetNetwork
        let walkedStreets = stats.streetCoverage
        Task { [weak self] in
            let ideas = await Task.detached(priority: .userInitiated) { () -> [AdventureIdea] in
                if let network {
                    return AdventureSuggester.frontiers(from: origin, network: network, coverage: walkedStreets, limit: 1)
                        + AdventureSuggester.undiscoveredPlaces(from: origin, catalog: catalog, discoveredIDs: discoveredIDs,
                                                                preferred: taste, limit: 2)
                }
                let center = grid.projection.project(origin)
                let region = MeterRect(minX: center.x - 2000, minY: center.y - 2000, maxX: center.x + 2000, maxY: center.y + 2000)
                let explored = grid.cells(for: exploration, region: region)
                let roads = roadContexts.flatMap(\.roads).map(\.coordinates)
                    .filter { road in road.contains { Geo.distanceMeters($0, origin) < 1800 } }
                return AdventureSuggester.frontiers(from: origin, roads: roads, explored: explored, grid: grid, limit: 1)
                    + AdventureSuggester.undiscoveredPlaces(from: origin, catalog: catalog, discoveredIDs: discoveredIDs,
                                                            preferred: taste, limit: 2)
            }.value
            self?.adventureIdeas = ideas
        }
    }

    func choose(_ idea: AdventureIdea) {
        switch idea.kind {
        case let .undiscoveredPlace(place): choose(place)
        case let .frontier(meters, bearing):
            choose(Place.frontierTarget(at: idea.target,
                                        label: "New streets · \(AdventureSuggester.compassWord(bearing)) (\(Format.distance(meters)))"))
        }
    }

    /// New-ground distance of the walk in progress (dotted part of the trail).
    var liveNewDistanceMeters: Double {
        guard recorder != nil || replay != nil else { return 0 }
        return displayedTrailRuns.filter(\.isNew).reduce(0) { total, run in
            zip(run.points, run.points.dropFirst()).reduce(total) { $0 + Geo.distanceMeters($1.0, $1.1) }
        }
    }

    /// New streets today: finished walks that started today plus the live walk.
    var todayNewDistanceMeters: Double {
        let start = Calendar.current.startOfDay(for: Date())
        let finished = stats.recaps(in: historyWalks, from: start, to: start.addingTimeInterval(86_400))
        return finished.reduce(0) { $0 + $1.newDistanceMeters } + (demoMode ? 0 : liveNewDistanceMeters)
    }

    // MARK: Timelapse ("Watch your world grow")

    @Published private(set) var timelapseBase: Exploration?

    /// Replays every shown walk in date order, revealing the map as it grew.
    func startTimelapse() {
        let ordered = historyWalks.sorted { $0.startedAt < $1.startedAt }
        guard !ordered.isEmpty, recorder == nil else { return }
        stopReplay()
        replayTask = Task { [weak self] in
            var base = Exploration()
            var shown = Set<UUID>()
            for walk in ordered {
                guard let self, !Task.isCancelled else { return }
                if let network = self.streetNetwork {
                    base = StreetReveal.exploration(coverage: self.stats.coverageByWalk, unmatched: self.stats.unmatchedByWalk,
                                                    network: network, include: shown)
                }
                self.timelapseBase = base
                var current = WalkReplay(source: walk)
                let step = max(1, current.totalSamples / 40)
                while !current.isFinished, !Task.isCancelled {
                    current.advance(by: step)
                    self.replay = current
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
                if self.streetNetwork == nil { base.merge(walk) }
                shown.insert(walk.id)
            }
            if let self, let network = self.streetNetwork {
                base = StreetReveal.exploration(coverage: self.stats.coverageByWalk, unmatched: self.stats.unmatchedByWalk,
                                                network: network, include: shown)
            }
            self?.timelapseBase = base
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.timelapseBase = nil
            self?.replay = nil
        }
    }

    var isTimelapseRunning: Bool { timelapseBase != nil }

    // MARK: New-ground classification

    /// Explored cells from earlier walks near the current walk (or replay), for dotted/solid trail.
    private var priorCells: Set<GridCell> = []
    private var priorCellsReady = false

    private func preparePriorCells(around coordinate: Coordinate, from base: Exploration) {
        let center = grid.projection.project(coordinate)
        let region = MeterRect(minX: center.x - 3000, minY: center.y - 3000, maxX: center.x + 3000, maxY: center.y + 3000)
        priorCells = grid.cells(for: base, region: region)
        priorCellsReady = true
    }

    // MARK: Captured moments

    @Published private(set) var moments: [WalkMemory] = []
    private var sampleMoments: [WalkMemory] = []
    private var sampleMomentPhotos: [UUID: UIImage] = [:]

    /// Moments pinned on the map: personal ones, or only sample ones in Demo mode.
    var mapMoments: [WalkMemory] { demoMode ? sampleMoments : moments }

    func moments(for session: WalkSession) -> [WalkMemory] {
        (isDemo(session) ? sampleMoments : moments).filter { $0.sessionID == session.id }.sorted { $0.takenAt < $1.takenAt }
    }

    func photo(for memory: WalkMemory) -> UIImage? {
        if let sample = sampleMomentPhotos[memory.id] { return sample }
        return store?.momentPhoto(memory).flatMap(UIImage.init(data:))
    }

    /// Captures a moment on the active walk at the latest accepted position (none if no recent fix).
    func captureMoment(_ image: UIImage) {
        guard let session = recorder?.session else { return }
        addMoment(image, to: session, at: currentPosition)
    }

    /// Adds a photo to a walk (e.g. a final photo on the recap). Location only if it is the live fix.
    func addMoment(_ image: UIImage, to session: WalkSession, at coordinate: Coordinate?) {
        let memory = WalkMemory(sessionID: session.id, takenAt: Date(), coordinate: coordinate)
        if isDemo(session) {
            sampleMoments.append(memory)
            sampleMomentPhotos[memory.id] = image
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            try store?.addMoment(memory, jpeg: data)
            moments.append(memory)
        } catch {
            storeProblem = "Could not save the photo: \(error.localizedDescription)"
        }
    }

    private var thumbnails: [UUID: UIImage] = [:]

    /// Small cached thumbnail for map pins (decoded once).
    func thumbnail(for memory: WalkMemory) -> UIImage? {
        if let cached = thumbnails[memory.id] { return cached }
        guard let full = photo(for: memory) else { return nil }
        let side: CGFloat = 96
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let scale = max(side / full.size.width, side / full.size.height)
            let size = CGSize(width: full.size.width * scale, height: full.size.height * scale)
            full.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        thumbnails[memory.id] = thumb
        return thumb
    }

    // MARK: Demo mode

    func setDemoMode(_ on: Bool) {
        if !on {
            stopReplay()
            demoMode = false
            refreshStats()
            return
        }
        guard recorder == nil else { return }
        if demo == nil {
            do {
                guard let url = Bundle.main.url(forResource: "sample-walks", withExtension: "json",
                                                subdirectory: "StarterData/demo") else {
                    demoProblem = "Demo data is not bundled in this build."
                    return
                }
                let loaded = try DemoDataset.decode(Data(contentsOf: url))
                demo = loaded
                demoExploration = loaded.exploration
            } catch {
                demoProblem = "Demo data could not be read: \(error.localizedDescription)"
                return
            }
        }
        demoProblem = nil
        demoMode = true
        refreshStats()
    }

    /// Animates one sample walk revealing the fog (~20 s), cycling through the sample walks.
    func startReplay() {
        guard demoMode, let walks = demo?.walks, !walks.isEmpty else { return }
        stopReplay()
        let source = walks[replayIndex % walks.count]
        replayIndex += 1
        replay = WalkReplay(source: source)
        if let start = source.segments.first?.first?.coordinate {
            preparePriorCells(around: start, from: demoExploration.excluding(sessionID: source.id))
        }
        let step = max(1, source.acceptedSampleCount / 400)
        replayTask = Task { [weak self] in
            while let self, var current = self.replay, !current.isFinished, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                current.advance(by: step)
                self.replay = current
            }
        }
    }

    func stopReplay() {
        timelapseBase = nil
        replayTask?.cancel()
        replayTask = nil
        replay = nil
    }

    // MARK: Samples

    private func handle(_ samples: [TrackSample]) {
        guard var current = recorder, current.session.state == .walking else {
            handleIdleFix(samples)
            return
        }
        let now = Date()
        var acceptedAny = false
        for sample in samples {
            guard let decision = current.ingest(sample, receivedAt: now) else { continue }
            switch decision {
            case .accepted:
                acceptedAny = true
                if !priorCellsReady { preparePriorCells(around: sample.coordinate, from: exploration) }
                lastFix = sample
                lastFixReceivedAt = now
                lastRejection = nil
            case .stationary:
                lastFix = sample
                lastFixReceivedAt = now
            case let .rejected(reason):
                lastRejection = reason
            }
        }
        current.checkpoint(at: now)
        recorder = current
        if current.session.acceptedSampleCount > 0 { phase = .walking }
        persistActive(force: acceptedAny && current.session.acceptedSampleCount == 1)
    }

    /// Incremental saves: immediately on state changes, otherwise at most every 10 seconds.
    func persistActive(force: Bool = false) {
        guard let store, let session = recorder?.session else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastPersist) >= 10 else { return }
        do {
            try store.saveActiveSession(session)
            lastPersist = now
        } catch {
            storeProblem = "Could not save the walk in progress: \(error.localizedDescription)"
        }
    }

    func appMovedToBackground() {
        if var current = recorder {
            current.checkpoint(at: Date())
            recorder = current
        }
        persistActive(force: true)
    }

    // MARK: Planner

    func ask() {
        let request = plannerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, let content else { return }
        plannerTask?.cancel()
        let options = SearchOptions(radiusMeters: searchRadiusMeters)
        plannerTask = Task { [weak self] in
            guard let self else { return }
            // Prefer where the user actually is: wait briefly for a fresh one-shot fix.
            if self.currentPosition == nil && self.location.authorization == .authorized {
                self.plannerState = .locating
                self.refreshIdleLocation()
                for _ in 0..<16 where self.currentPosition == nil && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            guard let origin = self.distanceOrigin else { return }
            self.plannerState = .loadingModel
            guard let engine = await self.ai.ensureLoaded() else {
                switch self.ai.state {
                case .missing: self.plannerState = .modelUnavailable(PlannerCopy.modelMissing)
                case let .failed(message): self.plannerState = .modelUnavailable("\(PlannerCopy.modelFailure) (\(message))")
                default: self.plannerState = .idle
                }
                return
            }
            self.plannerState = .thinking
            let (response, trace) = await Planner(engine: engine).plan(request, catalog: content.catalog,
                                                                       origin: origin, options: options)
            guard !Task.isCancelled else { return }
            self.lastTrace = trace
            self.plannerState = .answered(response, usedAI: true)
        }
    }

    func cancelPlanning() {
        plannerTask?.cancel()
        plannerTask = nil
        plannerState = .idle // the typed request stays in plannerText
    }

    /// Manual fallback. Keeps the app usable without AI but is labelled as such and is not Local AI evidence.
    func manualSearch(category: PlaceCategory) {
        guard let content, let origin = distanceOrigin else { return }
        let response = Planner.respond(OutingPreferences(categories: [category]), catalog: content.catalog,
                                       origin: origin, options: SearchOptions(radiusMeters: searchRadiusMeters))
        plannerState = .answered(response, usedAI: false)
    }

    func choose(_ place: Place) {
        destination = place
        refreshIdleLocation()
    }

    func clearDestination() {
        destination = nil
    }

    // MARK: Delete one adventure

    /// Permanently removes a finished adventure: its trail, photos and the streets it uncovered.
    func deleteAdventure(_ session: WalkSession) {
        guard !isDemo(session), let store else { return }
        do {
            try store.deleteFinished(session.id)
            finishedWalks.removeAll { $0.id == session.id }
            moments.removeAll { $0.sessionID == session.id }
            exploration.paths.removeAll { $0.sessionID == session.id }
            try store.saveExploration(exploration)
            if presentedRecap?.id == session.id { presentedRecap = nil }
            refreshStats()
        } catch {
            storeProblem = "Could not delete the adventure: \(error.localizedDescription)"
        }
    }

    /// Route for cards: matched street pieces (clean lines on real streets) plus off-street
    /// stretches; falls back to the raw accepted trail before street data is ready.
    func cardRoute(for session: WalkSession) -> [[Coordinate]] {
        if let network = streetNetwork, let coverage = stats.coverageByWalk[session.id] {
            let pieces = coverage.pieces(in: network).map { $0.points.map(network.projection.unproject) }
            let off = stats.unmatchedByWalk[session.id] ?? []
            if !pieces.isEmpty || !off.isEmpty { return pieces + off }
        }
        return session.segments.map { $0.map(\.coordinate) }
    }

    // MARK: Privacy

    var canErase: Bool { recorder == nil }

    func erasePersonalData() {
        guard canErase, let store else { return }
        do {
            try store.erasePersonalData()
            exploration = Exploration()
            finishedWalks = []
            refreshStats()
            destination = nil
            lastFix = nil
            lastFixReceivedAt = nil
            moments = []
            storeProblem = nil
        } catch {
            storeProblem = "Erase failed: \(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
