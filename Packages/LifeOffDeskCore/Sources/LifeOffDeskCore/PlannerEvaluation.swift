import Foundation

/// Runs eval/taglish-cases.json through the real planner and scores intent separately from
/// schema validity. Results describe the machine they ran on; only an iPhone run is phone evidence.
public enum PlannerEvaluation {
    public struct Case: Decodable, Sendable {
        public var id: Int
        public var prompt: String
        public var expectedConstraints: [String: JSONLiteral]
    }

    public struct CaseFile: Decodable, Sendable {
        public var cases: [Case]
    }

    /// Small literal type for expected values in the case file.
    public enum JSONLiteral: Decodable, Hashable, Sendable {
        case bool(Bool), int(Int), string(String), strings([String])

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(Bool.self) { self = .bool(v) }
            else if let v = try? c.decode(Int.self) { self = .int(v) }
            else if let v = try? c.decode(String.self) { self = .string(v) }
            else { self = .strings(try c.decode([String].self)) }
        }
    }

    public struct CaseResult: Codable, Hashable, Sendable {
        public var id: Int
        public var prompt: String
        public var rawOutputs: [String]
        public var attemptSeconds: [Double]
        public var schemaValid: Bool
        public var outcome: String
        public var preferences: String?
        public var suggestionIDs: [String]
        public var allSuggestionsInCatalog: Bool
        public var intentPass: Bool
        public var notes: [String]
    }

    public static func run(cases: [Case], planner: Planner, catalog: PlaceCatalog, origin: DistanceOrigin) async -> [CaseResult] {
        var results: [CaseResult] = []
        for testCase in cases {
            let (response, trace) = await planner.plan(testCase.prompt, catalog: catalog, origin: origin)
            results.append(score(testCase, response: response, trace: trace, catalog: catalog))
        }
        return results
    }

    public static func score(_ testCase: Case, response: PlannerResponse, trace: PlannerTrace, catalog: PlaceCatalog) -> CaseResult {
        var notes: [String] = []
        let lastOutcome = trace.attempts.last?.outcome
        let schemaValid: Bool
        switch lastOutcome {
        case .valid?, .needsClarification?: schemaValid = true
        default: schemaValid = false
        }
        if let error = trace.engineError { notes.append("engine error: \(error)") }
        if trace.attempts.count > 1 { notes.append("used repair attempt") }

        var prefs: OutingPreferences?
        var suggestions: [Suggestion] = []
        let outcomeName: String
        switch response {
        case let .suggestions(p, _, s): prefs = p; suggestions = s; outcomeName = "suggestions"
        case let .noMatch(p): prefs = p; outcomeName = "noMatch"
        case let .clarify(p, _): prefs = p; outcomeName = "clarify"
        case .failed: outcomeName = "failed"
        }
        let inCatalog = suggestions.allSatisfy { catalog.place(id: $0.id) == $0.place }

        var pass = schemaValid
        for (key, expected) in testCase.expectedConstraints.sorted(by: { $0.key < $1.key }) {
            let ok: Bool
            switch (key, expected) {
            case let ("durationMinutes", .int(v)): ok = prefs?.durationMinutes == v
            case let ("budgetPHP", .int(v)): ok = prefs?.budgetPHP == v
            case let ("categories", .strings(v)): ok = Set(v).isSubset(of: Set(prefs?.categories.map(\.rawValue) ?? []))
            case let ("moodTags", .strings(v)): ok = Set(v).isSubset(of: Set(prefs?.moodTags.map(\.rawValue) ?? []))
            case let ("travelMode", .string(v)): ok = prefs?.travelMode == v
            case let ("needsClarification", .bool(v)): ok = (outcomeName == "clarify") == v
            case ("unsupportedFact", _):
                // The app never asserts live hours: every card carries an hours label or there are no cards.
                ok = outcomeName != "failed" && suggestions.allSatisfy { s in
                    s.uncertainties.contains { if case .hoursUnverified = $0 { return true }; return false } || s.place.openingHours != nil
                }
            case ("mustNotInventPlace", _):
                ok = inCatalog && !suggestions.contains { $0.place.name.localizedCaseInsensitiveContains("secret moon") }
            case ("expectedSearchOutcome", _): ok = outcomeName == "noMatch" || outcomeName == "clarify"
            default: ok = false; notes.append("unknown expectation \(key)")
            }
            if !ok { notes.append("expected \(key)=\(expected)") }
            pass = pass && ok
        }
        let prefsText = prefs.map { p in
            "duration=\(p.durationMinutes.map(String.init) ?? "null") budget=\(p.budgetPHP.map(String.init) ?? "null") " +
            "categories=\(p.categories.map(\.rawValue)) moods=\(p.moodTags.map(\.rawValue)) clarify=\(p.needsClarification)"
        }
        return CaseResult(id: testCase.id, prompt: testCase.prompt,
                          rawOutputs: trace.attempts.map(\.rawOutput), attemptSeconds: trace.attempts.map(\.seconds),
                          schemaValid: schemaValid, outcome: outcomeName, preferences: prefsText,
                          suggestionIDs: suggestions.map(\.id), allSuggestionsInCatalog: inCatalog,
                          intentPass: pass, notes: notes)
    }
}
