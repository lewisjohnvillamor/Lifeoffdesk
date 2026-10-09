import Foundation

/// One location fix as delivered by the OS. Stored exactly as received once accepted.
public struct TrackSample: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var timestamp: Date
    public var horizontalAccuracy: Double
    /// Measured speed in m/s when the OS reports one (negative means unavailable).
    public var speed: Double?

    public init(latitude: Double, longitude: Double, timestamp: Date, horizontalAccuracy: Double, speed: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

/// Provisional tuning values from docs/ARCHITECTURE-AND-DATA.md. Not validated outdoors yet.
public struct TrackFilterPolicy: Codable, Hashable, Sendable {
    public var maxHorizontalAccuracy: Double = 30
    public var maxSampleAge: TimeInterval = 10
    public var maxFutureTolerance: TimeInterval = 2
    public var segmentGap: TimeInterval = 15
    public var maxPedestrianSpeed: Double = 4
    public var minimumMovement: Double = 5
    /// Multiple of the mean accuracy of the anchor and new fix that a move must exceed.
    public var accuracyMovementFactor: Double = 1.0
    /// OS-measured speed below this (m/s) marks a fix stationary unless it clearly moved.
    public var stationarySpeed: Double = 0.3

    public init() {}
    public static let provisional = TrackFilterPolicy()
}

public enum RejectionReason: String, Codable, Sendable {
    case invalidAccuracy, inaccurate, stale, futureTimestamp, nonIncreasingTimestamp, implausibleJump
}

public enum TrackDecision: Equatable, Sendable {
    /// Accepted into the trail. `startsSegment` means it must not be joined to the previous point.
    case accepted(startsSegment: Bool)
    /// A valid fix that did not move far enough to count; it proves the user is still here.
    case stationary
    case rejected(RejectionReason)
}

/// Decides which fixes become trail points. Pure and deterministic given `receivedAt`.
public struct TrackFilter: Sendable {
    public let policy: TrackFilterPolicy
    /// Last point added to the trail (movement anchor).
    public private(set) var anchor: TrackSample?
    /// Last valid fix of any kind (accepted or stationary); used for gap detection.
    public private(set) var lastValidFixTime: Date?
    private var forceNewSegment = true

    public init(policy: TrackFilterPolicy = .provisional) {
        self.policy = policy
    }

    /// Called on pause/resume or recovery: the next accepted point starts a new segment.
    public mutating func breakSegment() {
        forceNewSegment = true
    }

    /// Restores state after relaunch so the next fix is compared to persisted history.
    public mutating func restore(anchor: TrackSample?) {
        self.anchor = anchor
        lastValidFixTime = anchor?.timestamp
        forceNewSegment = true
    }

    public mutating func evaluate(_ sample: TrackSample, receivedAt: Date) -> TrackDecision {
        let accuracy = sample.horizontalAccuracy
        guard accuracy >= 0, accuracy.isFinite else { return .rejected(.invalidAccuracy) }
        guard accuracy <= policy.maxHorizontalAccuracy else { return .rejected(.inaccurate) }
        let age = receivedAt.timeIntervalSince(sample.timestamp)
        if age > policy.maxSampleAge { return .rejected(.stale) }
        if -age > policy.maxFutureTolerance { return .rejected(.futureTimestamp) }

        guard let anchor else {
            accept(sample)
            return .accepted(startsSegment: true)
        }
        let lastTime = max(anchor.timestamp, lastValidFixTime ?? anchor.timestamp)
        guard sample.timestamp > lastTime else { return .rejected(.nonIncreasingTimestamp) }

        let gap = sample.timestamp.timeIntervalSince(lastTime)
        if gap > policy.segmentGap || forceNewSegment {
            // Never draw a line across missing time; the new point begins a fresh segment.
            accept(sample)
            return .accepted(startsSegment: true)
        }

        let distance = Geo.distanceMeters(anchor.coordinate, sample.coordinate)
        let elapsed = sample.timestamp.timeIntervalSince(anchor.timestamp)
        // Allow the uncertainty of the worse fix before judging speed.
        let uncertainty = max(anchor.horizontalAccuracy, accuracy)
        let explainedDistance = max(0, distance - uncertainty)
        if elapsed > 0, explainedDistance / elapsed > policy.maxPedestrianSpeed {
            return .rejected(.implausibleJump)
        }

        // Drift of a few metres must not grow the trail: require displacement beyond the
        // combined uncertainty of both fixes, and trust a near-zero measured speed for small moves.
        let threshold = max(policy.minimumMovement,
                            (anchor.horizontalAccuracy + accuracy) / 2 * policy.accuracyMovementFactor)
        let measuredStill = (sample.speed ?? -1) >= 0 && (sample.speed ?? -1) < policy.stationarySpeed
        if distance < threshold || (measuredStill && distance < threshold * 2) {
            lastValidFixTime = sample.timestamp
            return .stationary
        }
        accept(sample)
        return .accepted(startsSegment: false)
    }

    private mutating func accept(_ sample: TrackSample) {
        anchor = sample
        lastValidFixTime = sample.timestamp
        forceNewSegment = false
    }
}
