import Foundation

/// Bundled synthetic walks for presentations (scripts/build_demo_walks.py). Shown only in the
/// app's labelled Demo mode and never written to personal storage.
public struct DemoDataset: Codable, Sendable {
    public var schemaVersion: Int
    /// Human-readable disclosure shown with the data.
    public var label: String
    public var generator: String
    public var walks: [WalkSession]

    public static func decode(_ data: Data) throws -> DemoDataset {
        try JSONDecoder().decode(DemoDataset.self, from: data)
    }

    public var exploration: Exploration {
        var exploration = Exploration()
        for walk in walks { exploration.merge(walk) }
        return exploration
    }

    public func contains(_ session: WalkSession) -> Bool { walks.contains { $0.id == session.id } }
}

/// Plays a recorded or synthetic walk back sample by sample so the reveal can be shown seated.
/// Always labelled as a replay in the UI.
public struct WalkReplay: Sendable {
    public let source: WalkSession
    public private(set) var shownSamples = 0
    public let totalSamples: Int

    public init(source: WalkSession) {
        self.source = source
        totalSamples = source.acceptedSampleCount
    }

    public var isFinished: Bool { shownSamples >= totalSamples }

    public mutating func advance(by count: Int) {
        shownSamples = min(totalSamples, shownSamples + max(0, count))
    }

    /// The part of the walk revealed so far, keeping segment boundaries.
    public var partialSession: WalkSession {
        var session = source
        var remaining = shownSamples
        session.segments = source.segments.compactMap { segment in
            guard remaining > 0 else { return nil }
            let take = min(remaining, segment.count)
            remaining -= take
            return Array(segment.prefix(take))
        }
        return session
    }

    public var currentSample: TrackSample? { partialSession.lastSample }
}
