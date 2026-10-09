import Foundation

/// P0-14: preferences the user explicitly saved. Nothing extracted from a request is stored
/// until the user taps "Save these preferences". Never inferred from routes or photos.
public struct PreferenceProfile: Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public enum Novelty: String, Codable, CaseIterable, Sendable { case any, new, familiar }
    public enum Language: String, Codable, CaseIterable, Sendable { case taglish, english }

    public var schemaVersion = PreferenceProfile.currentSchemaVersion
    public var categories: [PlaceCategory] = []
    public var durationMinutes: Int?
    public var radiusMeters: Double?
    public var novelty: Novelty = .any
    public var language: Language = .taglish
    /// Functional access requirements the user chose to save (hard filters until they remove them).
    public var accessNeeds: [AccessNeed] = []
    public var updatedAt: Date?

    public init(categories: [PlaceCategory] = [], durationMinutes: Int? = nil, radiusMeters: Double? = nil,
                novelty: Novelty = .any, language: Language = .taglish, accessNeeds: [AccessNeed] = []) {
        self.categories = categories; self.durationMinutes = durationMinutes; self.radiusMeters = radiusMeters
        self.novelty = novelty; self.language = language; self.accessNeeds = accessNeeds
    }

    public var isEmpty: Bool {
        categories.isEmpty && durationMinutes == nil && radiusMeters == nil && novelty == .any && accessNeeds.isEmpty
    }

    /// Clamps values to the same bounds the planner accepts.
    public func normalized() -> PreferenceProfile {
        var p = self
        p.categories = Array(categories.reduce(into: [PlaceCategory]()) { if !$0.contains($1) { $0.append($1) } }.prefix(3))
        if let d = durationMinutes, !OutingPreferences.durationRange.contains(d) { p.durationMinutes = nil }
        if let r = radiusMeters { p.radiusMeters = min(max(r, 100), SearchOptions.maxRadiusMeters) }
        p.accessNeeds = Array(Set(accessNeeds)).sorted { $0.rawValue < $1.rawValue }
        return p
    }

    /// Profile built from one planner result, for an explicit "Save these preferences".
    public static func from(_ prefs: OutingPreferences, radiusMeters: Double) -> PreferenceProfile {
        PreferenceProfile(categories: prefs.categories, durationMinutes: prefs.durationMinutes, radiusMeters: radiusMeters,
                          novelty: prefs.novelty, accessNeeds: prefs.accessNeeds).normalized()
    }
}

/// Functional requirements for a destination. Route accessibility is not supported (no routing).
public enum AccessNeed: String, Codable, CaseIterable, Sendable {
    case stepFreeEntrance, wheelchair
}

/// Which preference won, shown to the user so precedence is never hidden.
public struct ResolvedPreferences: Hashable, Sendable {
    public var prefs: OutingPreferences
    public var radiusMeters: Double
    /// Fields filled from saved preferences, e.g. ["duration", "novelty"].
    public var fromSaved: [String]
}

public enum PreferenceResolver {
    /// Explicit current request > saved soft preferences > defaults. Saved hard access needs
    /// stay active (union) until the user edits them; a request cannot silently drop them.
    public static func resolve(request: OutingPreferences, saved: PreferenceProfile?, radiusMeters explicitRadius: Double?,
                               defaultRadius: Double = SearchOptions.defaultRadiusMeters) -> ResolvedPreferences {
        var prefs = request
        var fromSaved: [String] = []
        var radius = explicitRadius ?? defaultRadius
        if let saved {
            if prefs.durationMinutes == nil, let d = saved.durationMinutes { prefs.durationMinutes = d; fromSaved.append("duration") }
            if prefs.novelty == .any, saved.novelty != .any { prefs.novelty = saved.novelty; fromSaved.append("novelty") }
            if explicitRadius == nil, let r = saved.radiusMeters { radius = r; fromSaved.append("radius") }
            // Saved categories only fill a request that named no kind of place and no specific thing.
            if prefs.categories.isEmpty && prefs.keywords.isEmpty && !saved.categories.isEmpty {
                prefs.categories = saved.categories; fromSaved.append("categories")
            }
            let missing = saved.accessNeeds.filter { !prefs.accessNeeds.contains($0) }
            if !missing.isEmpty { prefs.accessNeeds += missing; fromSaved.append("access") }
        }
        return ResolvedPreferences(prefs: prefs, radiusMeters: radius, fromSaved: fromSaved)
    }
}

public enum PreferenceLoadResult: Equatable, Sendable {
    case none
    case loaded(PreferenceProfile)
    /// Saved by a newer app version: kept untouched and not overwritten.
    case newerSchema(Int)
}

extension LocalStore {
    private struct SchemaProbe: Decodable { var schemaVersion: Int }
    private var preferencesURL: URL { directory.appendingPathComponent("preferences.json") }

    /// Missing file = no saved preferences. A newer schema is preserved (and blocks saving).
    public func loadPreferences() -> PreferenceLoadResult {
        for url in [preferencesURL, preferencesURL.appendingPathExtension("bak")] {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let probe = try? JSONDecoder().decode(SchemaProbe.self, from: data),
               probe.schemaVersion > PreferenceProfile.currentSchemaVersion {
                return .newerSchema(probe.schemaVersion)
            }
            if let profile = try? JSONDecoder().decode(PreferenceProfile.self, from: data) { return .loaded(profile) }
        }
        return .none
    }

    public func savePreferences(_ profile: PreferenceProfile) throws {
        if case let .newerSchema(found) = loadPreferences() {
            throw StoreError.unsupportedSchema(file: "preferences.json", found: found)
        }
        var p = profile.normalized()
        p.schemaVersion = PreferenceProfile.currentSchemaVersion
        try writeJSON(p, to: preferencesURL)
    }

    public func resetPreferences() throws {
        try removeJSON(preferencesURL)
    }

    // MARK: Narration cache (P0-13)

    private var narrationsURL: URL { directory.appendingPathComponent("narrations.json") }

    public func loadNarrations() -> [NarrationRecord] {
        guard let data = try? Data(contentsOf: narrationsURL) else { return [] }
        return (try? JSONDecoder().decode([NarrationRecord].self, from: data)) ?? []
    }

    public func saveNarration(_ record: NarrationRecord) throws {
        var all = loadNarrations().filter { $0.sessionID != record.sessionID }
        all.append(record)
        try writeJSON(all, to: narrationsURL)
    }

    public func removeNarrations(for sessionID: UUID?) throws {
        let kept = sessionID.map { id in loadNarrations().filter { $0.sessionID != id } } ?? []
        if kept.isEmpty { try removeJSON(narrationsURL) } else { try writeJSON(kept, to: narrationsURL) }
    }
}
