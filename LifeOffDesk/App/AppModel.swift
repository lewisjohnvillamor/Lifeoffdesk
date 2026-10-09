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
    /// The request was cancelled by a walk start, low memory or erase; the typed text is kept.
    case interrupted(String)
}

@MainActor
final class AppModel: ObservableObject {
    // Bundled regions, streamed in and out like game chunks (see RegionChunks)
    let regions: RegionLibrary?
    @Published private(set) var content: StarterContent?
    /// Bumped whenever the set of loaded cities changes (map geometry and graphs rebuild).
    @Published private(set) var contentVersion = 0
    @Published private(set) var loadingRegions: Set<String> = []
    private var regionUsedAt: [String: Date] = [:]
    private var mapViewport: BoundingBox?
    private var viewportTask: Task<Void, Never>?
    private var chunkCheckPosition: Coordinate?
    private var networkGeneration = 0
    let contentError: String?
    let grid: ExplorationGrid

    // Personal data
    let store: LocalStore?
    @Published private(set) var storeProblem: String?
    @Published private(set) var exploration = Exploration()
    @Published private(set) var finishedWalks: [WalkSession] = []

    // Walking
    @Published private(set) var recorder: WalkRecorder?
    @Published private(set) var phase: WalkPhase = .idle
    @Published private(set) var lastFix: TrackSample? {
        didSet {
            refreshDestinationStreet()
            // Moving (walking or riding) streams the next city in before you reach it.
            if let fix = lastFix?.coordinate,
               chunkCheckPosition.map({ Geo.distanceMeters($0, fix) > 300 }) ?? true {
                chunkCheckPosition = fix
                updateChunks()
            }
        }
    }
    @Published private(set) var lastFixReceivedAt: Date?
    @Published private(set) var lastRejection: RejectionReason?
    @Published var permissionDenied = false
    @Published var locationError: String?
    @Published var recoveredSession: WalkSession?
    @Published var presentedRecap: WalkSession?

    // Planner
    @Published var destination: Place? { didSet { refreshDestinationStreet(); updateChunks() } }
    /// Set when the walk in progress reaches the chosen destination; the map says "you've arrived"
    /// and the route clears (founder report: the route and pill stayed up after arriving).
    @Published var arrived: Place?
    @Published var plannerText = ""
    @Published var plannerState: PlannerState = .idle
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

    // MARK: Local AI features (P0-12–15); logic lives in AppModel+LocalAI.swift
    /// Saved preferences (nil = none saved). Only changed by an explicit user action.
    @Published var preferenceProfile: PreferenceProfile?
    /// Set when preferences.json was written by a newer app version; editing is disabled.
    @Published var preferencesLocked: String?
    @Published var preferencesProblem: String?
    @Published var historyQuery: HistoryQueryV1?
    @Published var historyState: HistoryState = .idle
    @Published var narrations: [UUID: NarrationState] = [:]
    var historyTask: Task<Void, Never>?

    let ai = AIService()
    private let location = LocationService()
    private var lastPersist = Date.distantPast
    private var startPending = false

    init() {
        do {
            // Launch reads only manifests, the always-on main-road context and the primary city;
            // every other city streams in when the map, GPS, planner or history needs it.
            let library = try RegionLibrary.open()
            var packs: [RegionPack] = [], issues: [String] = []
            for id in library.contextIDs + [library.primary.id] where !packs.contains(where: { $0.region.id == id }) {
                let loaded = try library.loadPack(id)
                packs.append(loaded.pack)
                issues += loaded.issues
            }
            regions = library
            content = StarterContent(library: library, packs: packs, issues: issues)
            contentError = nil
            grid = ExplorationGrid(origin: library.primary.center)
        } catch {
            regions = nil
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
        updateChunks()
    }

    // MARK: Region streaming (game-style chunks)

    /// Called by the map when the visible area changes; debounced so scrolling stays smooth.
    func mapViewportChanged(_ box: BoundingBox) {
        mapViewport = box
        viewportTask?.cancel()
        viewportTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.ensureChunks()
        }
    }

    func updateChunks() {
        Task { [weak self] in await self?.ensureChunks() }
    }

    /// Loads the cities near the map view, GPS, destination, planner origin (`extra` + `reach`)
    /// and every city a shown adventure passed through; frees idle far-away cities.
    func ensureChunks(around extra: [Coordinate] = [], reach: Double? = nil) async {
        guard let library = regions, let current = content else { return }
        let detailed = library.detailed.map { (id: $0.id, bounds: $0.bounds) }
        var points = extra
        if let position = currentPosition { points.append(position) }
        if let destination { points.append(destination.coordinate) }
        if let last = recorder?.session.lastSample { points.append(last.coordinate) }
        let walks = historyWalks + (recorder.map { [$0.session] } ?? [])
        let demand = RegionChunks.Demand(viewport: mapViewport, points: points,
                                         reachMeters: max(reach ?? 0, 2500),
                                         pinned: RegionChunks.touched(by: walks, regions: detailed))
        let desired = Set(RegionChunks.desired(detailed, demand: demand)).union([library.primary.id])
        let now = Date()
        for id in desired { regionUsedAt[id] = now }
        let detailedIDs = Set(detailed.map { $0.id })
        let loadedDetailed = current.loadedIDs.intersection(detailedIDs)
        let missing = desired.subtracting(current.loadedIDs).subtracting(loadingRegions)
        let evict = RegionChunks.evictions(loaded: regionUsedAt.filter { loadedDetailed.contains($0.key) },
                                           desired: desired).subtracting([library.primary.id])
        guard !missing.isEmpty || !evict.isEmpty else { return }
        loadingRegions.formUnion(missing)
        let results = await Task.detached(priority: .userInitiated) { () -> [(pack: RegionPack?, issues: [String])] in
            missing.sorted().map { id in
                do {
                    let loaded = try library.loadPack(id)
                    return (loaded.pack, loaded.issues)
                } catch {
                    return (nil, ["\(id) could not be loaded: \(error)"])
                }
            }
        }.value
        loadingRegions.subtract(missing)
        guard let latest = content else { return }
        var packs = latest.packs.filter { !evict.contains($0.region.id) }
        var issues = latest.issues
        for result in results {
            issues += result.issues
            if let pack = result.pack, !packs.contains(where: { $0.region.id == pack.region.id }) { packs.append(pack) }
        }
        for id in evict { regionUsedAt[id] = nil }
        content = StarterContent(library: library, packs: packs, issues: issues)
        contentVersion += 1
        buildStreetNetwork()
    }

    // MARK: Loading and recovery

    private func loadPersonalData() {
        guard let store else { return }
        exploration = store.loadExploration() ?? Exploration()
        finishedWalks = store.loadFinishedWalks()
        moments = store.loadMoments()
        switch store.loadPreferences() {
        case .none: preferenceProfile = nil
        case let .loaded(profile): preferenceProfile = profile
        case let .newerSchema(version):
            preferencesLocked = "Saved by a newer app version (schema \(version)); kept untouched."
        }
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
    /// Street graph for "how far along streets"; nil until built (distances fall back to straight-line).
    private(set) var walkingGraph: WalkingGraph?

    /// Street distance from here to the chosen destination, recomputed when either moves 40 m.
    var destinationStreet: StreetDistance? { destinationRoute?.distance }
    /// Shortest path along bundled streets to the destination, drawn on the map as a suggestion.
    @Published private(set) var destinationRoute: StreetRoute?
    private var destinationStreetKey: (id: String, from: Coordinate)?

    private func refreshDestinationStreet() {
        guard let graph = walkingGraph, let place = destination, let from = currentPosition else {
            if destination == nil { destinationRoute = nil; destinationStreetKey = nil }
            return
        }
        if let key = destinationStreetKey, key.id == place.id, Geo.distanceMeters(key.from, from) < 40 { return }
        if destinationStreetKey?.id != place.id { destinationRoute = nil }
        destinationStreetKey = (place.id, from)
        let target = place.coordinate
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { graph.route(from: from, to: target) }.value
            guard self?.destination?.id == place.id else { return }
            self?.destinationRoute = result
        }
    }
    /// Matched-street reveal of the shown history (from `stats`), used for the paper island.
    @Published private(set) var streetReveal: Exploration?
    private var liveCache: (key: String, reveal: [ExploredPath], runs: [TrailRun])?

    /// Rebuilds street matching and walking distances for the loaded cities. A newer build
    /// always wins over a slower older one.
    private func buildStreetNetwork() {
        guard let content else { return }
        networkGeneration += 1
        let generation = networkGeneration
        Task { [weak self] in
            // Walking graph over every loaded road (context trunk roads included), for distances.
            let graph = await Task.detached(priority: .utility) {
                WalkingGraph(roads: content.packs.flatMap(\.roads.roads))
            }.value
            guard let self, self.networkGeneration == generation else { return }
            self.walkingGraph = graph
            self.destinationStreetKey = nil
            self.refreshDestinationStreet()
            self.refreshAdventureIdeas()
        }
        Task { [weak self] in
            let network = await Task.detached(priority: .utility) {
                StreetNetwork(roads: content.matchingRoads, origin: content.region.center)
            }.value
            guard let self, self.networkGeneration == generation else { return }
            self.streetNetwork = network
            self.liveCache = nil
            self.refreshStats()
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
        ai.unload(reason: "nagsimula ang adventure") // keep the model out of memory while tracking
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
        // A walk that reached the destination completes it, even if no live fix triggered arrival.
        if let place = destination, Arrival.reached(by: session, place: place.coordinate) { destination = nil }
        arrived = nil
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

    /// Every place found on any adventure, once each (drawn as small dots on the map).
    @Published private(set) var foundPlaces: [Place] = []

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
            var seen = Set<String>()
            self?.foundPlaces = found.values.flatMap { $0 }.filter { seen.insert($0.id).inserted }
            self?.streetReveal = reveal
            self?.liveCache = nil
        }
    }

    /// The destination this adventure was started for, when its trail reached it.
    func destinationReached(by session: WalkSession) -> Place? {
        guard let id = session.destinationPlaceID, let place = content?.catalog.place(id: id),
              Arrival.reached(by: session, place: place.coordinate) else { return nil }
        return place
    }

    func discovered(in session: WalkSession) -> [Place] {
        if let cached = discoveries[session.id] { return cached }
        guard let catalog = content?.catalog else { return [] }
        return Discovery.placesPassed(by: session, in: catalog)
    }

    // MARK: Next adventure

    @Published private(set) var adventureIdeas: [AdventureIdea] = []
    /// "Para sa'yo" recommendation on the Adventures tab (see AppModel+Recommend).
    @Published var recommendation: RecommendationState = .idle
    @Published var savedPlaces: [Place] = AppModel.loadSavedPlaces()
    /// "Your world" coach card on the map (see AppModel+Coach).
    @Published var coach: CoachCard?
    var coachKey: String?

    /// Real targets only: undiscovered catalogue places matching the user's taste, and computed
    /// street frontiers (unexplored street length near them). Distances follow streets once the graph is ready.
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
        let graph = walkingGraph
        let suggest: @Sendable () -> [AdventureIdea] = {
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
        }
        Task { [weak self] in
            let ideas = await Task.detached(priority: .userInitiated) { () -> [AdventureIdea] in
                var ideas = suggest()
                if let graph {
                    let streets = graph.distances(from: origin, to: ideas.map(\.target))
                    for i in ideas.indices { ideas[i].street = streets[i] }
                }
                return ideas
            }.value
            self?.adventureIdeas = ideas
            self?.refreshCoach()
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

    func isDemoMoment(_ memory: WalkMemory) -> Bool { sampleMomentPhotos[memory.id] != nil }

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

    /// Demo mode only: illustrated sample "captures" (mascot postcards stamped SAMPLE) pinned along
    /// some sample walks, so photo pins, Spots and memory cards can be tried. Never real photos.
    private func seedSampleMoments() {
        guard sampleMoments.isEmpty, let walks = demo?.walks else { return }
        let poses: [Mascot] = [.cafeBreak, .takingPhotos, .discovering, .resting, .walking, .celebrating, .fogPeek, .savingMemories]
        for (i, walk) in walks.prefix(24).enumerated() where i % 2 == 0 {
            let samples = walk.segments.flatMap { $0 }
            guard let mid = samples.dropFirst(samples.count / 2).first else { continue }
            let pose = poses[(i / 2) % poses.count]
            let memory = WalkMemory(sessionID: walk.id, takenAt: mid.timestamp, coordinate: mid.coordinate)
            sampleMoments.append(memory)
            sampleMomentPhotos[memory.id] = Self.samplePostcard(pose)
        }
    }

    private static func samplePostcard(_ pose: Mascot) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(Theme.revealedGround).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let mascot = UIImage(named: pose.imageName) {
                let side: CGFloat = 440
                let scale = min(side / mascot.size.width, side / mascot.size.height)
                let w = mascot.size.width * scale, h = mascot.size.height * scale
                mascot.draw(in: CGRect(x: (size.width - w) / 2, y: 40 + (side - h) / 2, width: w, height: h))
            }
            let label = NSAttributedString(string: "SAMPLE", attributes: [
                .font: UIFont.systemFont(ofSize: 44, weight: .heavy), .foregroundColor: UIColor(Theme.danger),
                .kern: 6,
            ])
            let bounds = label.size()
            label.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: size.height - bounds.height - 28))
        }
    }

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
            updateChunks()
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
        seedSampleMoments()
        refreshStats()
        updateChunks()
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
        // After at least 20 m of walking, so choosing a place next door doesn't "arrive" on the first fix.
        if acceptedAny, current.session.distanceMeters >= 20, let place = destination, let fix = lastFix,
           Arrival.reached(fix.coordinate, accuracyMeters: fix.horizontalAccuracy, place: place.coordinate) {
            arrived = place
            destination = nil
        }
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

    /// A warm-up is in flight (cheap when the prefix is already cached, so it runs on every open).
    private var plannerWarming = false

    func ask() {
        let request = plannerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, let content else { return }
        plannerTask?.cancel()
        let options = SearchOptions(radiusMeters: searchRadiusMeters)
        plannerTask = Task { [weak self] in
            guard let self else { return }
            self.plannerState = self.ai.state == .ready ? .thinking : .loadingModel
            // The model reads the request while GPS and city packs are still being fetched.
            let ai = self.ai
            let extraction = Task { try await ai.run { await Planner(engine: $0).extract(request) } }
            // Prefer where the user actually is: wait briefly for a fresh one-shot fix.
            if self.currentPosition == nil && self.location.authorization == .authorized {
                self.refreshIdleLocation()
                for _ in 0..<16 where self.currentPosition == nil && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            guard let origin = self.distanceOrigin else { extraction.cancel(); return }
            // Stream in every city the search radius reaches before searching.
            await self.ensureChunks(around: [origin.coordinate], reach: options.radiusMeters)
            let catalog = self.content?.catalog ?? content.catalog, graph = self.walkingGraph
            let context = self.searchContext, saved = self.preferenceProfile
            do {
                let (outcome, extractTrace) = try await withTaskCancellationHandler {
                    try await extraction.value
                } onCancel: { extraction.cancel() }
                let (response, trace) = Planner.answer(outcome, trace: extractTrace, request: request, catalog: catalog,
                                                       origin: origin, options: options, graph: graph,
                                                       context: context, saved: saved)
                guard !Task.isCancelled else { return }
                self.lastTrace = trace
                self.plannerState = .answered(response, usedAI: true)
            } catch InferenceError.stale, InferenceError.cancelled {
                // The user cancelled (keep idle) or something else stopped the model: say so.
                if !Task.isCancelled { self.plannerState = .interrupted(self.ai.interruptionMessage) }
            } catch {
                switch self.ai.state {
                case .missing: self.plannerState = .modelUnavailable(PlannerCopy.modelMissing)
                case let .failed(message): self.plannerState = .modelUnavailable("\(PlannerCopy.modelFailure) (\(message))")
                default: self.plannerState = .modelUnavailable("\(PlannerCopy.modelFailure) (\(error))")
                }
            }
        }
    }

    /// Loads the model and pre-reads the planner's fixed instructions and examples while the user
    /// types, so the request itself only processes the new words (llama.cpp KV prefix reuse).
    func warmPlanner() {
        guard !plannerWarming else { return }
        plannerWarming = true
        let prompt = PlannerPrompt.chatML(request: "")
        Task { [weak self] in
            _ = try? await self?.ai.run { try await $0.complete(prompt: prompt, grammar: nil, maxTokens: 1) }
            self?.plannerWarming = false
        }
    }

    func cancelPlanning() {
        plannerTask?.cancel()
        plannerTask = nil
        plannerState = .idle // the typed request stays in plannerText
    }

    /// Manual fallback. Keeps the app usable without AI but is labelled as such and is not Local AI evidence.
    func manualSearch(category: PlaceCategory) {
        guard let origin = distanceOrigin else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.ensureChunks(around: [origin.coordinate], reach: self.searchRadiusMeters)
            self.runManualSearch(category: category, origin: origin)
        }
    }

    private func runManualSearch(category: PlaceCategory, origin: DistanceOrigin) {
        guard let content else { return }
        let response = Planner.respond(OutingPreferences(categories: [category],
                                                         accessNeeds: preferenceProfile?.accessNeeds ?? []),
                                       catalog: content.catalog,
                                       origin: origin, options: SearchOptions(radiusMeters: searchRadiusMeters),
                                       graph: walkingGraph, context: searchContext)
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
            narrations[session.id] = nil
            if let query = historyQuery { applyHistoryQuery(query) }
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
            ai.unload(reason: "erase") // cancels in-flight AI so nothing regenerates from erased data
            try store.erasePersonalData()
            exploration = Exploration()
            finishedWalks = []
            refreshStats()
            destination = nil
            lastFix = nil
            lastFixReceivedAt = nil
            moments = []
            preferenceProfile = nil
            preferencesLocked = nil
            narrations = [:]
            clearHistorySearch()
            clearRecommendations()
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
