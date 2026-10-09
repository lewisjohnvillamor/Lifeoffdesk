import Foundation

public enum DistanceOrigin: Hashable, Sendable {
    /// A fresh accepted GPS fix.
    case currentLocation(Coordinate)
    /// No usable fix: distances are measured from the starter area's reference point.
    case areaCenter(Coordinate)

    public var coordinate: Coordinate {
        switch self {
        case let .currentLocation(c), let .areaCenter(c): return c
        }
    }
}

/// Facts the app cannot vouch for, shown on the card instead of being guessed.
public enum Uncertainty: Hashable, Sendable {
    case hoursUnverified(sourceClaim: String?)
    case priceUnknown(budgetPHP: Int)
    case moodUnverified(MoodTag)
    case accessUnverified
    case approximatePosition
    case mayExceedTime(minutes: Int)
    /// The request named something specific ("pizza") that no nearby record mentions.
    case noKeywordMatch([String])
    /// A keyword matched the OSM cuisine tag, which nobody has reviewed.
    case cuisineFromSource
}

public struct Suggestion: Hashable, Identifiable, Sendable {
    public var place: Place
    public var straightLineMeters: Double
    public var matchedCategory: PlaceCategory?
    public var matchedMoods: [MoodTag]
    public var matchedKeywords: [String] = []
    public var withinKnownBudget: Bool
    public var uncertainties: [Uncertainty]

    public var id: String { place.id }
}

public struct SearchOptions: Hashable, Sendable {
    public static let defaultRadiusMeters: Double = 2000
    public static let maxRadiusMeters: Double = 5000

    public var radiusMeters: Double
    public var limit: Int

    public init(radiusMeters: Double = defaultRadiusMeters, limit: Int = 3) {
        self.radiusMeters = min(max(radiusMeters, 100), Self.maxRadiusMeters)
        self.limit = limit
    }

    /// Rough one-way straight-line reach for a round trip at a relaxed pace. Used only to
    /// warn that a place may not fit, never to promise a travel time.
    public static func approximateOneWayReachMeters(minutes: Int) -> Double {
        let metersPerMinute = 75.0, detourFactor = 1.3
        return Double(minutes) * metersPerMinute / 2 / detourFactor
    }
}

/// Deterministic catalog search. The model never sees or produces place records.
public enum PlaceSearch {
    public static func suggest(_ prefs: OutingPreferences, catalog: PlaceCatalog, origin: DistanceOrigin,
                               options: SearchOptions = SearchOptions()) -> [Suggestion] {
        let reach = prefs.durationMinutes.map(SearchOptions.approximateOneWayReachMeters)
        // Specific words ("pizza") narrow results to places whose name or OSM cuisine mentions them.
        let keywordMatches: (Place) -> [String] = { place in
            prefs.keywords.filter { word in place.searchableTerms.contains { $0.contains(word) } }
        }
        let keywordHits = prefs.keywords.isEmpty ? [] : catalog.places.filter {
            !keywordMatches($0).isEmpty && Geo.distanceMeters(origin.coordinate, $0.coordinate) <= options.radiusMeters
        }
        let useKeywords = !keywordHits.isEmpty
        // Nothing mentions the word and no category to fall back on: an honest empty result.
        if !prefs.keywords.isEmpty && !useKeywords && prefs.categories.isEmpty { return [] }
        var results: [(Suggestion, fitsTime: Bool)] = []
        for place in catalog.places {
            let matchedKeywords = keywordMatches(place)
            if useKeywords && matchedKeywords.isEmpty { continue }
            let distance = Geo.distanceMeters(origin.coordinate, place.coordinate)
            guard distance <= options.radiusMeters else { continue }
            if !useKeywords && !prefs.categories.isEmpty && !prefs.categories.contains(place.category) { continue }

            var uncertainties: [Uncertainty] = []
            var withinBudget = false
            if let budget = prefs.budgetPHP {
                if let price = place.budgetPHP {
                    guard price <= budget else { continue }
                    withinBudget = true
                } else {
                    // Unknown price never satisfies a ceiling; it is shown, labelled.
                    uncertainties.append(.priceUnknown(budgetPHP: budget))
                }
            }
            let matchedMoods = prefs.moodTags.filter(place.tags.contains)
            for mood in prefs.moodTags where !place.tags.contains(mood) {
                uncertainties.append(.moodUnverified(mood))
            }
            var fitsTime = true
            if let reach, let minutes = prefs.durationMinutes, distance > reach {
                fitsTime = false
                uncertainties.append(.mayExceedTime(minutes: minutes))
            }
            if place.openingHours == nil { uncertainties.append(.hoursUnverified(sourceClaim: place.sourceOpeningHours)) }
            if !place.isReviewed { uncertainties.append(.accessUnverified) }
            if place.positionMethod == "bounds-midpoint" { uncertainties.append(.approximatePosition) }
            if !prefs.keywords.isEmpty && !useKeywords { uncertainties.insert(.noKeywordMatch(prefs.keywords), at: 0) }
            if matchedKeywords.contains(where: { word in !place.name.lowercased().contains(word) }) {
                uncertainties.append(.cuisineFromSource)
            }

            var suggestion = Suggestion(place: place, straightLineMeters: distance,
                                        matchedCategory: prefs.categories.contains(place.category) ? place.category : nil,
                                        matchedMoods: matchedMoods, withinKnownBudget: withinBudget,
                                        uncertainties: uncertainties)
            suggestion.matchedKeywords = matchedKeywords
            results.append((suggestion, fitsTime))
        }
        results.sort { a, b in
            if a.0.withinKnownBudget != b.0.withinKnownBudget { return a.0.withinKnownBudget }
            if a.0.matchedMoods.count != b.0.matchedMoods.count { return a.0.matchedMoods.count > b.0.matchedMoods.count }
            if a.fitsTime != b.fitsTime { return a.fitsTime }
            if a.0.straightLineMeters != b.0.straightLineMeters { return a.0.straightLineMeters < b.0.straightLineMeters }
            return a.0.place.id < b.0.place.id
        }
        return Array(results.prefix(options.limit).map(\.0))
    }
}
