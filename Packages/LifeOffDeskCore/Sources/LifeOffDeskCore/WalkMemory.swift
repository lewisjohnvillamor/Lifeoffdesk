import Foundation

/// A moment the user captured during a walk: a photo, optional note, and the accepted GPS
/// position at that time if there was one (never invented when there was no fix).
public struct WalkMemory: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var takenAt: Date
    public var latitude: Double?
    public var longitude: Double?
    public var note: String?

    public init(id: UUID = UUID(), sessionID: UUID, takenAt: Date, coordinate: Coordinate?, note: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.takenAt = takenAt
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
        self.note = note
    }

    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    public var fileName: String { "\(id.uuidString).jpg" }
}

/// A run of consecutive accepted samples that is either new ground or a revisit.
public struct TrailRun: Hashable, Sendable {
    public var points: [Coordinate]
    public var isNew: Bool
}

extension ExplorationGrid {
    /// Splits accepted segments into runs over new ground (outside `prior` cells) and revisits.
    /// Segments are never joined across gaps.
    public func trailRuns(for segments: [[TrackSample]], prior: Set<GridCell>) -> [TrailRun] {
        var runs: [TrailRun] = []
        for segment in segments {
            guard segment.count >= 2 else { continue }
            var current: TrailRun?
            for (a, b) in zip(segment, segment.dropFirst()) {
                let mid = Coordinate(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
                let isNew = !prior.contains(cell(containing: mid))
                if var run = current, run.isNew == isNew {
                    run.points.append(b.coordinate)
                    current = run
                } else {
                    if let run = current { runs.append(run) }
                    current = TrailRun(points: [a.coordinate, b.coordinate], isNew: isNew)
                }
            }
            if let run = current { runs.append(run) }
        }
        return runs
    }
}
