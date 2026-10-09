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
            MainActor.assumeIsolated { self?.locationError = message }
        }
        loadPersonalData()
    }

    // MARK: Loading and recovery

    private func loadPersonalData() {
        guard let store else { return }
        exploration = store.loadExploration() ?? Exploration()
        finishedWalks = store.loadFinishedWalks()
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

    /// Saved exploration plus the walk in progress, for rendering.
    var displayExploration: Exploration {
        guard let session = recorder?.session else { return exploration }
        var merged = exploration
        merged.merge(session)
        return merged
    }

    /// A fix only counts as "you are here" while it is recent.
    var currentPosition: Coordinate? {
        guard let lastFix, let at = lastFixReceivedAt, Date().timeIntervalSince(at) < 30 else { return nil }
        return lastFix.coordinate
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
        recorder = nil
        recoveredSession = nil
        phase = .idle
        presentedRecap = session
    }

    func recap(for session: WalkSession) -> WalkRecap {
        WalkRecap.compute(session: session, exploration: exploration, grid: grid, now: session.endedAt ?? Date())
    }

    // MARK: Samples

    private func handle(_ samples: [TrackSample]) {
        guard var current = recorder, current.session.state == .walking else { return }
        let now = Date()
        var acceptedAny = false
        for sample in samples {
            guard let decision = current.ingest(sample, receivedAt: now) else { continue }
            switch decision {
            case .accepted:
                acceptedAny = true
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
        guard !request.isEmpty, let content, let origin = distanceOrigin else { return }
        plannerTask?.cancel()
        let options = SearchOptions(radiusMeters: searchRadiusMeters)
        plannerTask = Task { [weak self] in
            guard let self else { return }
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
    }

    func clearDestination() {
        destination = nil
    }

    // MARK: Privacy

    var canErase: Bool { recorder == nil }

    func erasePersonalData() {
        guard canErase, let store else { return }
        do {
            try store.erasePersonalData()
            exploration = Exploration()
            finishedWalks = []
            destination = nil
            lastFix = nil
            lastFixReceivedAt = nil
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
