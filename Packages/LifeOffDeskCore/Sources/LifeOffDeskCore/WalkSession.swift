import Foundation

public enum WalkState: String, Codable, Sendable {
    case walking, paused, finished
}

/// Persisted walk. Distance and duration are always computed from this record.
public struct WalkSession: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var id: UUID
    public var schemaVersion: Int
    public var state: WalkState
    public var startedAt: Date
    public var endedAt: Date?
    /// Active time banked before the current walking interval (excludes pauses).
    public var bankedActiveDuration: TimeInterval
    /// Start of the current walking interval; nil while paused or finished.
    public var activeSince: Date?
    /// Latest moment the app knowingly persisted this session while walking.
    public var lastCheckpointAt: Date
    /// Accepted samples split into segments; segments are never joined when drawing or measuring.
    public var segments: [[TrackSample]]
    public var destinationPlaceID: String?
    public var destinationName: String?
    /// True when this session was restored after the app stopped unexpectedly.
    public var wasRecovered: Bool

    public init(id: UUID = UUID(), startedAt: Date, destinationPlaceID: String? = nil, destinationName: String? = nil) {
        self.id = id
        schemaVersion = Self.currentSchemaVersion
        state = .walking
        self.startedAt = startedAt
        endedAt = nil
        bankedActiveDuration = 0
        activeSince = startedAt
        lastCheckpointAt = startedAt
        segments = []
        self.destinationPlaceID = destinationPlaceID
        self.destinationName = destinationName
        wasRecovered = false
    }

    public func activeDuration(at now: Date) -> TimeInterval {
        guard let activeSince else { return bankedActiveDuration }
        return bankedActiveDuration + max(0, now.timeIntervalSince(activeSince))
    }

    /// Sum of accepted segments only; gaps between segments add nothing.
    public var distanceMeters: Double {
        segments.reduce(0) { total, segment in
            zip(segment, segment.dropFirst()).reduce(total) { $0 + Geo.distanceMeters($1.0.coordinate, $1.1.coordinate) }
        }
    }

    public var acceptedSampleCount: Int { segments.reduce(0) { $0 + $1.count } }

    public var lastSample: TrackSample? { segments.last?.last }
}

public enum WalkCommandError: Error, Equatable {
    case notWalking, notPaused, alreadyFinished
}

/// Applies explicit user commands and filtered samples to a session.
public struct WalkRecorder: Sendable {
    public private(set) var session: WalkSession
    public private(set) var filter: TrackFilter
    public private(set) var lastDecision: TrackDecision?

    public init(session: WalkSession, policy: TrackFilterPolicy = .provisional) {
        self.session = session
        filter = TrackFilter(policy: policy)
        filter.restore(anchor: session.lastSample)
    }

    public static func start(at date: Date, destinationPlaceID: String? = nil, destinationName: String? = nil,
                             policy: TrackFilterPolicy = .provisional) -> WalkRecorder {
        WalkRecorder(session: WalkSession(startedAt: date, destinationPlaceID: destinationPlaceID,
                                          destinationName: destinationName), policy: policy)
    }

    /// Returns the decision; samples while paused or finished are ignored entirely.
    @discardableResult
    public mutating func ingest(_ sample: TrackSample, receivedAt: Date) -> TrackDecision? {
        guard session.state == .walking else { return nil }
        let decision = filter.evaluate(sample, receivedAt: receivedAt)
        lastDecision = decision
        if case let .accepted(startsSegment) = decision {
            if startsSegment || session.segments.isEmpty {
                session.segments.append([sample])
            } else {
                session.segments[session.segments.count - 1].append(sample)
            }
        }
        return decision
    }

    public mutating func pause(at date: Date) throws {
        guard session.state != .finished else { throw WalkCommandError.alreadyFinished }
        guard session.state == .walking else { throw WalkCommandError.notWalking }
        session.bankedActiveDuration = session.activeDuration(at: date)
        session.activeSince = nil
        session.state = .paused
        session.lastCheckpointAt = date
        filter.breakSegment()
    }

    public mutating func resume(at date: Date) throws {
        guard session.state != .finished else { throw WalkCommandError.alreadyFinished }
        guard session.state == .paused else { throw WalkCommandError.notPaused }
        session.activeSince = date
        session.state = .walking
        session.lastCheckpointAt = date
        filter.breakSegment()
    }

    /// Idempotent: finishing a finished walk changes nothing.
    public mutating func finish(at date: Date) {
        guard session.state != .finished else { return }
        session.bankedActiveDuration = session.activeDuration(at: date)
        session.activeSince = nil
        session.state = .finished
        session.endedAt = date
        session.lastCheckpointAt = date
    }

    public mutating func checkpoint(at date: Date) {
        if session.state == .walking { session.lastCheckpointAt = date }
    }

    /// A session found on disk still marked walking means the app stopped unexpectedly.
    /// Bank only time up to the last known checkpoint or accepted sample and leave it paused;
    /// tracking never resumes without the user's explicit action.
    public static func recover(_ stored: WalkSession) -> WalkSession {
        guard stored.state == .walking, let activeSince = stored.activeSince else { return stored }
        var session = stored
        let lastKnown = max(stored.lastCheckpointAt, stored.lastSample?.timestamp ?? stored.lastCheckpointAt)
        session.bankedActiveDuration += max(0, lastKnown.timeIntervalSince(activeSince))
        session.activeSince = nil
        session.state = .paused
        session.wasRecovered = true
        return session
    }
}
