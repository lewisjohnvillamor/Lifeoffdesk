import Foundation

/// A local text-generation backend (llama.cpp on the phone). Tests use a scripted fake;
/// a scripted fake is never evidence of Local AI.
public protocol IntentEngine: Sendable {
    func complete(prompt: String, grammar: String?, maxTokens: Int) async throws -> String
}

public enum PlannerResponse: Hashable, Sendable {
    case suggestions(OutingPreferences, intro: String, [Suggestion])
    case noMatch(OutingPreferences)
    case clarify(OutingPreferences?, question: String)
    case failed
}

public struct PlannerAttempt: Hashable, Sendable {
    public var rawOutput: String
    public var seconds: Double
    public var outcome: ValidationOutcome
}

public struct PlannerTrace: Hashable, Sendable {
    public var attempts: [PlannerAttempt] = []
    public var engineError: String?
    /// Fields filled from saved preferences (shown to the user; the request always wins).
    public var appliedSaved: [String] = []

    /// Why no usable answer came back, for the UI (nil when the model produced one).
    public var failureReason: String? {
        if let engineError { return "Engine: \(engineError)" }
        guard let last = attempts.last, case let .invalid(errors) = last.outcome else { return nil }
        return "The model's reply was rejected \(attempts.count == 2 ? "twice" : "") (\(errors.map { "\($0)" }.joined(separator: ", ")))."
    }
}

/// Runs: model intent extraction → validation (one bounded repair) → deterministic search.
public struct Planner: Sendable {
    public var engine: IntentEngine
    public var maxTokens: Int
    public var useGrammar: Bool

    public init(engine: IntentEngine, maxTokens: Int = 160, useGrammar: Bool = true) {
        self.engine = engine
        self.maxTokens = maxTokens
        self.useGrammar = useGrammar
    }

    public func extract(_ request: String) async -> (ValidationOutcome?, PlannerTrace) {
        var trace = PlannerTrace()
        var repair: String?
        for _ in 0..<2 {
            let prompt = PlannerPrompt.chatML(request: request, repairNote: repair)
            let start = Date()
            let output: String
            do {
                output = try await engine.complete(prompt: prompt, grammar: useGrammar ? PlannerPrompt.grammar : nil,
                                                   maxTokens: maxTokens)
            } catch {
                trace.engineError = "\(error)"
                return (nil, trace)
            }
            let outcome = PreferenceValidator.validate(output)
            trace.attempts.append(PlannerAttempt(rawOutput: output, seconds: Date().timeIntervalSince(start), outcome: outcome))
            if case let .invalid(errors) = outcome {
                repair = PlannerPrompt.repairNote(for: errors)
                continue
            }
            return (outcome, trace)
        }
        return (trace.attempts.last?.outcome, trace)
    }

    public func plan(_ request: String, catalog: PlaceCatalog, origin: DistanceOrigin,
                     options: SearchOptions = SearchOptions(), graph: WalkingGraph? = nil,
                     context: SearchContext = SearchContext(), saved: PreferenceProfile? = nil) async -> (PlannerResponse, PlannerTrace) {
        let (outcome, trace) = await extract(request)
        return Self.answer(outcome, trace: trace, request: request, catalog: catalog, origin: origin, options: options,
                           graph: graph, context: context, saved: saved)
    }

    /// Turns a validated extraction into places (deterministic). Split from `extract` so the app can
    /// run the model while it is still waiting for a GPS fix.
    public static func answer(_ outcome: ValidationOutcome?, trace: PlannerTrace, request: String, catalog: PlaceCatalog,
                              origin: DistanceOrigin, options: SearchOptions = SearchOptions(), graph: WalkingGraph? = nil,
                              context: SearchContext = SearchContext(),
                              saved: PreferenceProfile? = nil) -> (PlannerResponse, PlannerTrace) {
        switch outcome {
        case nil, .invalid?:
            return (.failed, trace)
        case let .needsClarification(prefs, reason)?:
            return (.clarify(AccessWords.grounded(prefs, in: request), question: PlannerCopy.clarification(reason)), trace)
        case let .valid(extracted)?:
            let prefs = AccessWords.grounded(extracted, in: request)
            // A radius left at the default is not an explicit choice, so a saved radius may apply.
            let explicit = options.radiusMeters == SearchOptions.defaultRadiusMeters ? nil : options.radiusMeters
            let resolved = PreferenceResolver.resolve(request: prefs, saved: saved, radiusMeters: explicit)
            var trace = trace
            trace.appliedSaved = resolved.fromSaved
            let resolvedOptions = SearchOptions(radiusMeters: resolved.radiusMeters, limit: options.limit)
            return (Self.respond(resolved.prefs, catalog: catalog, origin: origin, options: resolvedOptions, graph: graph,
                                 context: context), trace)
        }
    }

    /// Deterministic part, also used by manual filters (which are not Local AI evidence).
    public static func respond(_ prefs: OutingPreferences, catalog: PlaceCatalog, origin: DistanceOrigin,
                               options: SearchOptions, graph: WalkingGraph? = nil,
                               context: SearchContext = SearchContext()) -> PlannerResponse {
        // The path itself cannot be checked (no routing): explain, and let the user choose a venue-only filter.
        if prefs.routeAccess { return .clarify(prefs, question: PlannerCopy.routeAccessUnsupported) }
        let suggestions = PlaceSearch.suggest(prefs, catalog: catalog, origin: origin, options: options, graph: graph,
                                              context: context)
        guard !suggestions.isEmpty else { return .noMatch(prefs) }
        return .suggestions(prefs, intro: PlannerCopy.intro(prefs: prefs, count: suggestions.count, origin: origin,
                                                            radiusMeters: options.radiusMeters,
                                                            byStreets: suggestions.contains { $0.street != nil }), suggestions)
    }
}

/// Access requirements only count when the request actually mentions access. A small model can
/// read "lakad lang" (just walking) as a route-accessibility need; that must not trigger the
/// accessibility filter or its clarification. Deterministic keyword check on the user's own words.
public enum AccessWords {
    static let words = ["wheelchair", "wheel chair", "pwd", "accessible", "accessibility", "step-free", "step free",
                        "stepfree", "ramp", "rampa", "elevator", "lift", "stroller", "saklay", "crutch", "walker",
                        "kapansanan", "disability", "disabled", "mobility", "hagdan", "stairs", "baby carriage"]

    public static func mentioned(in request: String) -> Bool {
        let text = request.lowercased()
        return words.contains { text.contains($0) }
    }

    public static func grounded(_ prefs: OutingPreferences, in request: String) -> OutingPreferences {
        guard !mentioned(in: request) else { return prefs }
        var p = prefs
        p.routeAccess = false
        p.accessNeeds = []
        return p
    }
}
