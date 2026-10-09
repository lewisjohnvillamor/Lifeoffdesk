import Foundation

/// P0-16: one scoped, source-backed fact (docs/ACCESSIBILITY-AND-SAFETY.md). There is no global
/// "accessible" or "safe" flag: a venue, an entrance and a street are different subjects.
public struct EvidenceFactV1: Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public enum SubjectKind: String, Codable, Sendable { case place, entrance, street, crossing }
    public enum Kind: String, Codable, Sendable { case stepFreeEntrance, wheelchair, pedestrianAccess }
    public enum AccessValue: String, Codable, Sendable { case yes, no, limited, unknown }
    public enum SourceType: String, Codable, Sendable { case osm, `operator`, fieldObservation }
    public enum ReviewStatus: String, Codable, Sendable { case sourceOnly, reviewed, conflicted }

    public var id: String
    public var schemaVersion: Int
    /// Stable ID of the subject (a place ID, or an entrance/segment ID).
    public var subjectID: String
    public var subjectKind: SubjectKind
    /// The place an entrance belongs to, so entrance facts can be matched to a venue.
    public var placeID: String?
    public var kind: Kind
    public var value: AccessValue
    public var sourceType: SourceType
    public var sourceURL: String
    public var sourceRecordID: String
    public var license: String
    public var retrievedAt: Date
    public var observedAt: Date?
    public var reviewStatus: ReviewStatus
    public var reviewedAt: Date?
    public var reviewerID: String?
    /// Without an explicit validity the fact cannot establish current hard eligibility.
    public var validUntil: Date?
    /// Conditions such as "staff assistance" or "weekdays only"; any condition makes it unknown.
    public var conditions: [String]
    public var supersedesID: String?
}

/// Versioned sidecar (`place-facts.json`). Missing on older packs = no evidence.
public struct EvidenceSidecar: Codable, Sendable {
    public var schemaVersion: Int
    public var regionID: String
    public var note: String?
    public var facts: [EvidenceFactV1]

    public static func empty(regionID: String) -> EvidenceSidecar {
        EvidenceSidecar(schemaVersion: EvidenceFactV1.currentSchemaVersion, regionID: regionID, note: nil, facts: [])
    }

    /// Decodes with ISO-8601 dates; facts with an unknown schema version are dropped, not guessed.
    public static func decode(_ data: Data) throws -> EvidenceSidecar {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var sidecar = try decoder.decode(EvidenceSidecar.self, from: data)
        sidecar.facts = sidecar.facts.filter { $0.schemaVersion <= EvidenceFactV1.currentSchemaVersion }
        return sidecar
    }
}

public enum Eligibility: Hashable, Sendable {
    case eligible(factIDs: [String])
    case ineligible(reason: String, factIDs: [String])
    case unknown(reason: String)

    public var isEligible: Bool { if case .eligible = self { return true }; return false }
}

/// Deterministic, pure. For a hard requirement only a scoped, reviewed, unconditional, positive
/// fact inside its explicit validity passes. Negative, limited, conflicting, stale, conditional,
/// source-only and absent evidence never pass. Model output cannot override this.
public enum EligibilityPolicy {
    public static func evaluate(_ need: AccessNeed, place: Place, facts: [EvidenceFactV1], now: Date) -> Eligibility {
        let kind: EvidenceFactV1.Kind = need == .stepFreeEntrance ? .stepFreeEntrance : .wheelchair
        // Scope: venue-level or one of its entrances. A street or crossing never speaks for a venue.
        let scoped = facts.filter { fact in
            fact.kind == kind && (
                (fact.subjectKind == .place && fact.subjectID == place.id) ||
                (fact.subjectKind == .entrance && fact.placeID == place.id))
        }
        let superseded = Set(scoped.compactMap(\.supersedesID))
        let current = scoped.filter { !superseded.contains($0.id) }
        guard !current.isEmpty else { return .unknown(reason: "No recorded evidence") }
        let ids = current.map(\.id)
        if current.contains(where: { $0.reviewStatus == .conflicted }) ||
            Set(current.filter { $0.reviewStatus == .reviewed }.map(\.value)).count > 1 {
            return .ineligible(reason: "Conflicting records", factIDs: ids)
        }
        if let negative = current.first(where: { $0.reviewStatus == .reviewed && ($0.value == .no || $0.value == .limited) }) {
            return .ineligible(reason: negative.value == .no ? "Recorded as not accessible" : "Recorded as limited",
                               factIDs: [negative.id])
        }
        let usable = current.filter { fact in
            fact.reviewStatus == .reviewed && fact.value == .yes && fact.conditions.isEmpty
                && (fact.observedAt ?? .distantFuture) <= now && (fact.reviewedAt ?? .distantFuture) <= now
                && fact.validUntil.map { now < $0 } == true
        }
        if let fact = usable.first { return .eligible(factIDs: [fact.id]) }
        if current.contains(where: { $0.reviewStatus == .sourceOnly }) { return .unknown(reason: "Source-only, not reviewed") }
        if current.contains(where: { !$0.conditions.isEmpty }) { return .unknown(reason: "Only with conditions") }
        if current.contains(where: { $0.validUntil == nil }) { return .unknown(reason: "No validity period recorded") }
        return .unknown(reason: "Evidence is out of date")
    }

    /// All needs must be eligible; the first non-eligible result explains why.
    public static func evaluate(_ needs: [AccessNeed], place: Place, facts: [EvidenceFactV1], now: Date) -> Eligibility {
        var ids: [String] = []
        for need in needs {
            let result = evaluate(need, place: place, facts: facts, now: now)
            guard case let .eligible(factIDs) = result else { return result }
            ids += factIDs
        }
        return .eligible(factIDs: ids)
    }

    /// Card text: never implies the path is verified.
    public static func label(_ need: AccessNeed, _ result: Eligibility) -> String {
        let name = need == .stepFreeEntrance ? "Step-free entrance" : "Wheelchair access"
        switch result {
        case .eligible: return "\(name): recorded (see source and date) · Path to it: not verified"
        case let .ineligible(reason, _): return "\(name): \(reason.lowercased())"
        case .unknown: return "\(name): not verified"
        }
    }
}
