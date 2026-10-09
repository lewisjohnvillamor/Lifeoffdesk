import Foundation
import LifeOffDeskCore

/// One "Para sa'yo" suggestion as shown on the Adventures tab.
struct RecommendationCard: Equatable {
    var candidate: PlaceRecommender.Candidate
    var text: String
    /// nil = the on-device model picked it; otherwise why the computed pick is shown.
    var computedReason: String?
    var alternatives: Int
    /// Second-pass AI check of this pick ("AI check: swak sa hilig mo"); nil when it did not run.
    var judge: JudgeVerdict?
}

enum RecommendationState: Equatable {
    case idle
    case working
    case shown(RecommendationCard)
    case empty(String)
}

extension AppModel {
    private static let historyKey = "recommend.history.v1"
    private static let savedKey = "recommend.saved.v1"

    static func loadSavedPlaces() -> [Place] {
        guard let data = UserDefaults.standard.data(forKey: savedKey) else { return [] }
        return (try? JSONDecoder().decode([Place].self, from: data)) ?? []
    }

    private var recommendationHistory: PlaceRecommender.History {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
                  let history = try? JSONDecoder().decode(PlaceRecommender.History.self, from: data) else { return .init() }
            return history
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.historyKey) }
    }

    /// Reads what your adventures passed (your taste), ranks unvisited nearby places, then lets the
    /// on-device model pick one of the top three and the reasons to show.
    func recommendPlace() {
        guard recommendation != .working, let content else { return }
        recommendation = .working
        let origin = currentPosition ?? historyWalks.max { $0.startedAt < $1.startedAt }?.lastSample?.coordinate
            ?? content.region.center
        let taste = PlaceRecommender.Taste(places: discoveries.values.flatMap { $0 })
        let discovered = discoveredPlaceIDs
        let history = recommendationHistory
        let graph = walkingGraph
        Task { [weak self] in
            guard let self else { return }
            await self.ensureChunks(around: [origin], reach: PlaceRecommender.maxMeters)
            let catalog = self.content?.catalog ?? content.catalog
            let candidates = await Task.detached(priority: .userInitiated) {
                PlaceRecommender.candidates(catalog: catalog, origin: origin, graph: graph, taste: taste,
                                            discoveredIDs: discovered, history: history, now: Date())
            }.value
            guard let fallback = RecommendationCopy.computed(candidates) else {
                self.recommendation = .empty(taste.total == 0
                    ? "Wala pang malapit na lugar na mairerekomenda dito. Mag-adventure muna para makilala kita!"
                    : "Naubos na ang bagong lugar na swak sa'yo sa malapit. Subukan ulit bukas o mag-explore ng bagong area.")
                return
            }
            var card = RecommendationCard(candidate: fallback.0, text: fallback.1, computedReason: nil,
                                          alternatives: candidates.count)
            let recent = history.recentCategories
            do {
                // The AI picks; instant rule checks (distance, taste, repeats) cross-check it and move
                // to the next candidate if it fails. No second AI pass, so no extra waiting.
                let result = try await self.ai.run { engine -> (Int, [PlaceRecommender.ReasonID], JudgeVerdict?, String?) in
                    let (outcome, _) = await RecommendationPrompt.choose(candidates, engine: engine)
                    guard case let .valid(choice) = outcome else {
                        if case let .engineError(message) = outcome { return (0, [], nil, message) }
                        return (0, [], nil, "AI reply was rejected")
                    }
                    let order = [choice.index] + candidates.indices.filter { $0 != choice.index }
                    for index in order {
                        let verdict = RecommendationCheck.verdict(candidates[index], taste: taste, recent: recent)
                        if verdict.verdict == .good {
                            let reasons = index == choice.index ? choice.reasons
                                : Array([PlaceRecommender.ReasonID.likesCuisine, .likesCategory, .nearby]
                                    .filter { candidates[index].reasons[$0] != nil }.prefix(2))
                            return (index, reasons, verdict, nil)
                        }
                    }
                    let verdict = RecommendationCheck.verdict(candidates[choice.index], taste: taste, recent: recent)
                    return (choice.index, choice.reasons, verdict, nil)
                }
                if let problem = result.3 {
                    card.computedReason = problem
                } else {
                    let picked = candidates[result.0]
                    card = RecommendationCard(candidate: picked, text: RecommendationCopy.render(picked, reasons: result.1),
                                              computedReason: nil, alternatives: candidates.count, judge: result.2)
                }
            } catch {
                card.computedReason = "On-device AI unavailable"
            }
            if card.judge == nil {
                card.judge = RecommendationCheck.verdict(card.candidate, taste: taste, recent: recent)
            }
            var updated = self.recommendationHistory
            updated.record(card.candidate.place, .shown, at: Date())
            self.recommendationHistory = updated
            self.recommendation = .shown(card)
        }
    }

    func saveRecommendation() {
        guard case let .shown(card) = recommendation else { return }
        let place = card.candidate.place
        var history = recommendationHistory
        history.record(place, .saved, at: Date())
        recommendationHistory = history
        if !savedPlaces.contains(where: { $0.id == place.id }) { savedPlaces.insert(place, at: 0) }
        persistSavedPlaces()
        recommendation = .idle
    }

    /// "Not for me": never suggested again; shows the next one.
    func dismissRecommendation() {
        guard case let .shown(card) = recommendation else { return }
        var history = recommendationHistory
        history.record(card.candidate.place, .dismissed, at: Date())
        recommendationHistory = history
        recommendation = .idle
        recommendPlace()
    }

    func goToRecommendation() {
        guard case let .shown(card) = recommendation else { return }
        choose(card.candidate.place)
        selectedTab = .map
    }

    func removeSavedPlace(_ place: Place) {
        savedPlaces.removeAll { $0.id == place.id }
        persistSavedPlaces()
    }

    func clearRecommendations() {
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        savedPlaces = []
        recommendation = .idle
    }

    private func persistSavedPlaces() {
        UserDefaults.standard.set(try? JSONEncoder().encode(savedPlaces), forKey: Self.savedKey)
    }
}
