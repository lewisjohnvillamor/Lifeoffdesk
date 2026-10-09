import Foundation

/// Taglish replies built from validated preferences and actual matches. The model never
/// writes these sentences, so they cannot contain invented venue facts.
public enum PlannerCopy {
    public static let placeholder = "A quiet place for a 30-minute break"
    public static let noMatch = "Walang matching place sa area na ito. Try natin ibang activity o mas malawak na area?"
    public static let modelFailure = "I couldn't understand that request. Try again or choose filters."
    public static let modelMissing = "Wala pa ang local AI model sa phone na ito. Puwede ka pa ring pumili gamit ang filters o mag-start walking."

    public static func clarification(_ reason: ClarificationReason) -> String {
        switch reason {
        case .modelAsked, .nothingToSearch: return "Anong hanap mo? Pagkain, kape, park o museum? Ilang minutes ang meron ka?"
        case .budgetOutOfRange: return "Medyo kakaiba ang budget na 'yan. Magkano ang puwede mong gastusin (0–10,000 pesos)?"
        case .durationOutOfRange: return "Ilang minutes ang meron ka? Kaya ko ang 5 hanggang 120 minutes."
        }
    }

    public static func categoryWord(_ category: PlaceCategory) -> String {
        switch category {
        case .park: return "park"
        case .cafe: return "café"
        case .food: return "kainan"
        case .museum: return "museum"
        case .library: return "library"
        case .scenic: return "scenic spot"
        case .other: return "lugar"
        }
    }

    public static func moodWord(_ mood: MoodTag) -> String {
        switch mood {
        case .quiet: return "tahimik"
        case .nature: return "nature vibes"
        case .curious: return "may bagong makikita"
        case .relax: return "relaxing"
        case .active: return "active"
        }
    }

    /// One short line above the results, e.g. "3 park malapit sa'yo · straight-line".
    public static func intro(prefs: OutingPreferences, count: Int, origin: DistanceOrigin, radiusMeters: Double) -> String {
        let what = prefs.categories.isEmpty ? "lugar" : prefs.categories.map(categoryWord).joined(separator: "/")
        var parts: [String]
        switch origin {
        case .currentLocation: parts = ["\(count) \(what) malapit sa'yo"]
        case .areaCenter: parts = ["\(count) \(what) sa starter area", "wala pang GPS fix"]
        }
        if let minutes = prefs.durationMinutes { parts.append("\(minutes) min") }
        if let budget = prefs.budgetPHP { parts.append("₱\(budget)") }
        parts.append("straight-line")
        return parts.joined(separator: " · ")
    }

    /// Compact subtitle: "Park · 850 m", plus verified matches only.
    public static func reason(_ suggestion: Suggestion) -> String {
        var parts = [categoryWord(suggestion.place.category).capitalized, Format.distance(suggestion.straightLineMeters)]
        for word in suggestion.matchedKeywords { parts.append(word) }
        for mood in suggestion.matchedMoods { parts.append("\(moodWord(mood)) ✓") }
        if suggestion.withinKnownBudget { parts.append("pasok sa budget") }
        return parts.joined(separator: " · ")
    }

    /// One caveat line summarising every uncertainty; full labels stay available on tap.
    public static func caveat(_ suggestion: Suggestion) -> String {
        var parts: [String] = []
        let hours = suggestion.uncertainties.contains { if case .hoursUnverified = $0 { return true }; return false }
        let access = suggestion.uncertainties.contains(.accessUnverified)
        if hours && access { parts.append("Hours & access unverified") }
        else if hours { parts.append("Hours unverified") }
        else if access { parts.append("Access unverified") }
        if suggestion.uncertainties.contains(where: { if case .priceUnknown = $0 { return true }; return false }) {
            parts.append("price unknown")
        }
        if suggestion.uncertainties.contains(where: { if case .noKeywordMatch = $0 { return true }; return false }) {
            parts.insert("no exact match", at: 0)
        }
        if suggestion.uncertainties.contains(where: { if case .mayExceedTime = $0 { return true }; return false }) {
            parts.append("baka kulang ang oras")
        }
        return parts.joined(separator: " · ")
    }

    public static func label(_ uncertainty: Uncertainty) -> String {
        switch uncertainty {
        case let .hoursUnverified(claim?): return "Opening hours unverified (OSM lists: \(claim))"
        case .hoursUnverified(nil): return "Opening hours unknown"
        case let .priceUnknown(budget): return "Presyo unknown — hindi ma-confirm kung pasok sa ₱\(budget)"
        case let .moodUnverified(mood): return "Hindi pa verified kung \(moodWord(mood))"
        case .accessUnverified: return "Source-only (OpenStreetMap), access hindi pa reviewed"
        case .approximatePosition: return "Approximate marker (gitna ng area)"
        case let .mayExceedTime(minutes): return "Baka hindi kasya sa \(minutes) minutes mo"
        case let .noKeywordMatch(words): return "Walang exact match para sa \(words.joined(separator: ", ")); ito ang pinakamalapit na \(words.count == 1 ? "kategorya" : "mga kategorya")"
        case .cuisineFromSource: return "Cuisine galing sa OpenStreetMap (unverified)"
        }
    }
}
