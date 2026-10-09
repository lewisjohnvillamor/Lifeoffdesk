import Foundation
import LifeOffDeskCore

enum HistoryState: Equatable {
    case idle
    case searching
    /// AI-extracted filters applied to saved adventures (IDs in display order).
    case results([UUID])
    case clarify(String)
    case failed(String)
}

enum NarrationState: Equatable {
    case working
    /// AI-selected highlights rendered with computed values.
    case ai(String)
    /// The model was unavailable or its reply was rejected; the computed summary is shown instead.
    case fallback(String, reason: String)
}

/// P0-12 history search, P0-13 grounded narration, P0-14 preferences, P0-15 adaptive context.
/// All model work goes through `ai.run` (one serialized coordinator); records stay deterministic.
extension AppModel {
    /// Computed exploration and bundled evidence for ranking and hard access filters.
    var searchContext: SearchContext {
        SearchContext(passedPlaceIDs: discoveredPlaceIDs, evidence: content?.evidence ?? [], now: Date())
    }

    // MARK: History search (real saved adventures only; sample data never mixes in)

    var historySearchAvailable: Bool { !demoMode && !finishedWalks.isEmpty }

    private func historySummaries() -> [AdventureSummary] {
        finishedWalks.map { walk in
            AdventureSummary(session: walk, photoCount: moments.filter { $0.sessionID == walk.id }.count,
                             nearPlaces: discovered(in: walk))
        }
    }

    func searchHistory(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        historyTask?.cancel()
        historyState = .searching
        let now = Date(), zone = TimeZone.current
        historyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (outcome, _) = try await self.ai.run { engine in
                    await HistoryQueryPrompt.extract(question, engine: engine, now: now, timeZone: zone)
                }
                guard !Task.isCancelled else { return }
                switch outcome {
                case let .valid(.query(query)): self.applyHistoryQuery(query, now: now, timeZone: zone)
                case let .valid(.clarify(question)): self.historyState = .clarify(question)
                case .invalid: self.historyState = .failed("Hindi ko na-intindihan. Subukan ulit o gamitin ang calendar.")
                case let .engineError(message): self.historyState = .failed(message)
                }
            } catch InferenceError.stale, InferenceError.cancelled {
                if !Task.isCancelled { self.historyState = .idle }
            } catch {
                self.historyState = .failed("On-device AI unavailable (\(error)). Calendar and list still work.")
            }
        }
    }

    /// Re-runs the deterministic search (after a chip is removed, a save or a delete).
    func applyHistoryQuery(_ query: HistoryQueryV1, now: Date = Date(), timeZone: TimeZone = .current) {
        historyQuery = query
        historyState = .results(HistorySearch.search(query, in: historySummaries(), now: now, timeZone: timeZone))
    }

    func clearHistorySearch() {
        historyTask?.cancel()
        historyQuery = nil
        historyState = .idle
    }

    // MARK: Grounded recap narration

    func recapFacts(for session: WalkSession) -> RecapFacts {
        RecapFacts.compute(recap: recap(for: session), placesPassed: discovered(in: session),
                           photoCount: moments(for: session).count)
    }

    /// Cached AI narration for this exact facts/model/prompt version, if any.
    func cachedNarration(for session: WalkSession) -> String? {
        guard !isDemo(session), let store else { return nil }
        let facts = recapFacts(for: session)
        let key = NarrationRecord.key(facts: facts, modelID: AIService.modelFileName)
        guard let record = store.loadNarrations().first(where: { $0.key == key }) else { return nil }
        return RecapNarrator.render(record.choice, facts: facts)
    }

    /// Never blocks Finish: the adventure is already saved before this is offered.
    func requestNarration(for session: WalkSession) {
        let facts = recapFacts(for: session)
        if let cached = cachedNarration(for: session) { narrations[session.id] = .ai(cached); return }
        narrations[session.id] = .working
        let id = session.id, demo = isDemo(session)
        Task { [weak self] in
            guard let self else { return }
            let fallback = RecapNarrator.computedSummary(facts)
            do {
                let (outcome, _) = try await self.ai.run { await RecapNarrationPrompt.choose(facts: facts, engine: $0) }
                // Deleted or erased meanwhile: never resurrect it.
                guard demo || self.finishedWalks.contains(where: { $0.id == id }) else { self.narrations[id] = nil; return }
                switch outcome {
                case let .valid(choice):
                    guard let text = RecapNarrator.render(choice, facts: facts) else {
                        self.narrations[id] = .fallback(fallback, reason: "AI reply could not be rendered"); return
                    }
                    if !demo {
                        try? self.store?.saveNarration(NarrationRecord(sessionID: id, key: NarrationRecord.key(
                            facts: facts, modelID: AIService.modelFileName), choice: choice, createdAt: Date()))
                    }
                    self.narrations[id] = .ai(text)
                case .invalid: self.narrations[id] = .fallback(fallback, reason: "AI reply was rejected")
                case let .engineError(message): self.narrations[id] = .fallback(fallback, reason: message)
                }
            } catch InferenceError.stale {
                self.narrations[id] = nil
            } catch {
                self.narrations[id] = .fallback(fallback, reason: "On-device AI unavailable")
            }
        }
    }

    // MARK: Preferences (explicit save/edit/reset only)

    @discardableResult
    func savePreferences(_ profile: PreferenceProfile) -> Bool {
        guard preferencesLocked == nil, let store else { return false }
        do {
            var p = profile.normalized()
            p.updatedAt = Date()
            try store.savePreferences(p)
            preferenceProfile = p
            preferencesProblem = nil
            return true
        } catch {
            preferencesProblem = "Not saved: \(error)"
            return false
        }
    }

    func resetPreferences() {
        guard preferencesLocked == nil, let store else { return }
        do {
            try store.resetPreferences()
            preferenceProfile = nil
            preferencesProblem = nil
        } catch {
            preferencesProblem = "Reset failed: \(error)"
        }
    }

    /// "Save these preferences" from the current planner result (the user tapped it).
    func savePlannerPreferences() -> Bool {
        guard case let .answered(.suggestions(prefs, _, _), _) = plannerState else { return false }
        return savePreferences(PreferenceProfile.from(prefs, radiusMeters: searchRadiusMeters))
    }

    // MARK: Planner follow-ups chosen by the user (deterministic re-runs of the extracted intent)

    /// Route accessibility is unsupported; the user chose a venue-entrance filter instead.
    func searchVenueEntranceOnly(_ prefs: OutingPreferences) {
        var p = prefs
        p.routeAccess = false
        if !p.accessNeeds.contains(.stepFreeEntrance) { p.accessNeeds.append(.stepFreeEntrance) }
        rerun(p)
    }

    /// The user removed the access requirement to see unverified places.
    func searchWithoutAccessNeeds(_ prefs: OutingPreferences) {
        var p = prefs
        p.accessNeeds = []
        p.routeAccess = false
        rerun(p)
    }

    private func rerun(_ prefs: OutingPreferences) {
        guard let content, let origin = distanceOrigin else { return }
        var usedAI = false
        if case let .answered(_, used) = plannerState { usedAI = used }
        let response = Planner.respond(prefs, catalog: content.catalog, origin: origin,
                                       options: SearchOptions(radiusMeters: searchRadiusMeters),
                                       graph: walkingGraph, context: searchContext)
        plannerState = .answered(response, usedAI: usedAI)
    }

    /// Off-street part of all adventures (raw trail not matched to a mapped street), for Me.
    var offStreetMeters: Double {
        stats.unmatchedByWalk.values.flatMap { $0 }.reduce(0) { total, line in
            zip(line, line.dropFirst()).reduce(total) { $0 + Geo.distanceMeters($1.0, $1.1) }
        }
    }
}
