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
        case .modelAsked: return "Anong trip mo? Park, café, museum o library? Ilang minutes ang meron ka?"
        case .budgetOutOfRange: return "Medyo kakaiba ang budget na 'yan. Magkano ang puwede mong gastusin (0–10,000 pesos)?"
        case .durationOutOfRange: return "Ilang minutes ang meron ka? Kaya ko ang 5 hanggang 120 minutes."
        }
    }

    public static func categoryWord(_ category: PlaceCategory) -> String {
        switch category {
        case .park: return "park"
        case .cafe: return "café"
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

    public static func intro(prefs: OutingPreferences, count: Int, origin: DistanceOrigin, radiusMeters: Double) -> String {
        let what = prefs.categories.isEmpty ? "lugar" : prefs.categories.map(categoryWord).joined(separator: "/")
        let from: String
        switch origin {
        case .currentLocation: from = "mula sa location mo"
        case .areaCenter: from = "mula sa gitna ng Makati starter area (wala pang GPS fix)"
        }
        var line = "Heto ang \(count) na \(what) within \(Format.distance(radiusMeters)) \(from)."
        if let minutes = prefs.durationMinutes { line += " May \(minutes) minutes ka." }
        if let budget = prefs.budgetPHP { line += " Budget: ₱\(budget)." }
        return line + " Straight-line distance lang ito, hindi walking route."
    }

    public static func reason(_ suggestion: Suggestion) -> String {
        var parts: [String] = []
        if let category = suggestion.matchedCategory { parts.append("Tugma sa \(categoryWord(category)) preference mo") }
        for mood in suggestion.matchedMoods { parts.append("verified na \(moodWord(mood))") }
        if suggestion.withinKnownBudget { parts.append("pasok sa budget") }
        parts.append("\(Format.distance(suggestion.straightLineMeters)) straight-line")
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
        }
    }
}
