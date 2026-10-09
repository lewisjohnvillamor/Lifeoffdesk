import Foundation

/// Validated intent extracted by the local model. Null means unknown, never a default guess.
public struct OutingPreferences: Codable, Hashable, Sendable {
    public var durationMinutes: Int?
    public var budgetPHP: Int?
    public var categories: [PlaceCategory]
    public var moodTags: [MoodTag]
    /// Specific things asked for ("pizza", "ramen", "milk tea"); matched against names and OSM cuisine.
    public var keywords: [String]
    public var travelMode: String
    public var needsClarification: Bool

    public init(durationMinutes: Int? = nil, budgetPHP: Int? = nil, categories: [PlaceCategory] = [],
                moodTags: [MoodTag] = [], keywords: [String] = [], needsClarification: Bool = false) {
        self.durationMinutes = durationMinutes
        self.budgetPHP = budgetPHP
        self.categories = categories
        self.moodTags = moodTags
        self.keywords = keywords
        travelMode = "walk"
        self.needsClarification = needsClarification
    }

    public static let durationRange = 5...120
    public static let budgetRange = 0...10_000
    public static let maxListItems = 3
    public static let keywordLength = 2...24

    /// True when nothing searchable was given (then ask instead of listing random places).
    public var isEmptyRequest: Bool {
        durationMinutes == nil && budgetPHP == nil && categories.isEmpty && moodTags.isEmpty && keywords.isEmpty
    }
}

public enum ValidationError: Error, Hashable, Sendable {
    case noJSONObject
    case malformedJSON
    case missingKey(String)
    case unexpectedKey(String)
    case wrongType(String)
    case unknownEnumValue(key: String, value: String)
    case tooManyItems(String)
    case unsupportedTravelMode(String)
    case invalidKeyword(String)
}

/// What the planner should do with a model reply.
public enum ValidationOutcome: Hashable, Sendable {
    case valid(OutingPreferences)
    /// Well-formed but cannot be searched yet; ask one short question.
    case needsClarification(OutingPreferences, ClarificationReason)
    case invalid([ValidationError])
}

public enum ClarificationReason: String, Hashable, Sendable {
    case modelAsked, budgetOutOfRange, durationOutOfRange, nothingToSearch
}

public enum PreferenceValidator {
    static let keys = ["durationMinutes", "budgetPHP", "categories", "moodTags", "keywords", "travelMode", "needsClarification"]

    /// Extracts the first balanced JSON object, ignoring any `<think>` block or surrounding prose.
    public static func extractJSONObject(from text: String) -> String? {
        var body = text
        if let end = body.range(of: "</think>") { body = String(body[end.upperBound...]) }
        guard let start = body.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        var index = start
        while index < body.endIndex {
            let ch = body[index]
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(body[start...index]) }
            }
            index = body.index(after: index)
        }
        return nil
    }

    public static func validate(_ modelOutput: String) -> ValidationOutcome {
        guard let json = extractJSONObject(from: modelOutput) else { return .invalid([.noJSONObject]) }
        guard let data = json.data(using: .utf8),
              case let .object(object)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .invalid([.malformedJSON])
        }
        var errors: [ValidationError] = []
        for key in keys where object[key] == nil { errors.append(.missingKey(key)) }
        for key in object.keys.sorted() where !keys.contains(key) { errors.append(.unexpectedKey(key)) }

        let duration = optionalInt(object["durationMinutes"], key: "durationMinutes", errors: &errors)
        let budget = optionalInt(object["budgetPHP"], key: "budgetPHP", errors: &errors)
        let categories: [PlaceCategory] = enumList(object["categories"], key: "categories", errors: &errors)
        let moods: [MoodTag] = enumList(object["moodTags"], key: "moodTags", errors: &errors)
        let keywords = keywordList(object["keywords"], errors: &errors)

        switch object["travelMode"] {
        case nil: break
        case let .string(mode)?: if mode != "walk" { errors.append(.unsupportedTravelMode(mode)) }
        default: errors.append(.wrongType("travelMode"))
        }
        var asked = false
        switch object["needsClarification"] {
        case nil: break
        case let .bool(flag)?: asked = flag
        default: errors.append(.wrongType("needsClarification"))
        }
        guard errors.isEmpty else { return .invalid(errors) }

        var prefs = OutingPreferences(durationMinutes: duration, budgetPHP: budget, categories: categories,
                                      moodTags: moods, keywords: keywords, needsClarification: asked)
        if let budget, !OutingPreferences.budgetRange.contains(budget) {
            prefs.budgetPHP = nil
            return .needsClarification(prefs, .budgetOutOfRange)
        }
        if let duration, !OutingPreferences.durationRange.contains(duration) {
            prefs.durationMinutes = nil
            return .needsClarification(prefs, .durationOutOfRange)
        }
        // Ask only when nothing usable was extracted (the prompt's own rule). A model that fills in
        // categories/keywords/moods/duration and also says "ask" is resolved in favour of its data.
        if prefs.isEmptyRequest { return .needsClarification(prefs, asked ? .modelAsked : .nothingToSearch) }
        return .valid(prefs)
    }

    private static func optionalInt(_ value: JSONValue?, key: String, errors: inout [ValidationError]) -> Int? {
        switch value {
        case nil, .null?: return nil
        case let .number(double)?:
            guard double.isFinite, double == double.rounded(), abs(double) < 1_000_000 else {
                errors.append(.wrongType(key)); return nil
            }
            return Int(double)
        default:
            errors.append(.wrongType(key)); return nil
        }
    }

    /// Words that are moods, place kinds or filler, not something to match in a name or cuisine.
    static let keywordStopList: Set<String> = [
        "quiet", "tahimik", "nature", "relax", "active", "curious", "park", "cafe", "coffee", "kape", "food", "pagkain",
        "museum", "library", "scenic", "place", "lugar", "good", "best", "masarap", "nearby", "malapit", "walk", "lakad",
        "opening hours", "open", "bukas", "cheap", "mura", "restaurant", "kainan",
    ]

    private static func keywordList(_ value: JSONValue?, errors: inout [ValidationError]) -> [String] {
        guard let value else { return [] }
        guard case let .array(array) = value else { errors.append(.wrongType("keywords")); return [] }
        if array.count > OutingPreferences.maxListItems { errors.append(.tooManyItems("keywords")) }
        var result: [String] = []
        for item in array {
            guard case let .string(raw) = item else { errors.append(.wrongType("keywords")); continue }
            let word = raw.lowercased().trimmingCharacters(in: .whitespaces)
            let allowed = word.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) || $0 == " " || $0 == "-" }
            guard OutingPreferences.keywordLength.contains(word.count), allowed else {
                errors.append(.invalidKeyword(raw)); continue
            }
            if !result.contains(word) && !keywordStopList.contains(word) { result.append(word) }
        }
        return result
    }

    private static func enumList<E: RawRepresentable & Hashable>(_ value: JSONValue?, key: String,
                                                                  errors: inout [ValidationError]) -> [E] where E.RawValue == String {
        guard let value else { return [] }
        guard case let .array(array) = value else { errors.append(.wrongType(key)); return [] }
        if array.count > OutingPreferences.maxListItems { errors.append(.tooManyItems(key)) }
        var result: [E] = []
        for item in array {
            guard case let .string(raw) = item else { errors.append(.wrongType(key)); continue }
            guard let parsed = E(rawValue: raw) else { errors.append(.unknownEnumValue(key: key, value: raw)); continue }
            if !result.contains(parsed) { result.append(parsed) }
        }
        return result
    }
}

/// Minimal JSON tree so type checks behave identically on iOS and Linux.
enum JSONValue: Decodable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
}
