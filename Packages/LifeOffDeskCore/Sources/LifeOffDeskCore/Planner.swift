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
                     options: SearchOptions = SearchOptions()) async -> (PlannerResponse, PlannerTrace) {
        let (outcome, trace) = await extract(request)
        switch outcome {
        case nil, .invalid?:
            return (.failed, trace)
        case let .needsClarification(prefs, reason)?:
            return (.clarify(prefs, question: PlannerCopy.clarification(reason)), trace)
        case let .valid(prefs)?:
            return (Self.respond(prefs, catalog: catalog, origin: origin, options: options), trace)
        }
    }

    /// Deterministic part, also used by manual filters (which are not Local AI evidence).
    public static func respond(_ prefs: OutingPreferences, catalog: PlaceCatalog, origin: DistanceOrigin,
                               options: SearchOptions) -> PlannerResponse {
        let suggestions = PlaceSearch.suggest(prefs, catalog: catalog, origin: origin, options: options)
        guard !suggestions.isEmpty else { return .noMatch(prefs) }
        return .suggestions(prefs, intro: PlannerCopy.intro(prefs: prefs, count: suggestions.count, origin: origin,
                                                            radiusMeters: options.radiusMeters), suggestions)
    }
}
